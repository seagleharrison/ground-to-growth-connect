package api

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"testing"

	"ground-to-growth-connect-backend/internal/blobstore"
)

func patchMe(t *testing.T, h http.Handler, token string, body map[string]interface{}) map[string]interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodPatch, "/api/me", token, body)
	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH /api/me: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]map[string]interface{}
	decodeJSON(t, rec, &resp)
	return resp["user"]
}

func getMe(t *testing.T, h http.Handler, token string) map[string]interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodGet, "/api/me", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/me: expected 200, got %d", rec.Code)
	}
	var resp map[string]map[string]interface{}
	decodeJSON(t, rec, &resp)
	return resp["user"]
}

func TestUpdateProfileChangesAndPersistsFields(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{
		"name": "Jane Doe", "email": "jane@example.org", "phone": "912-555-0100", "gender": "female",
	})

	updated := patchMe(t, h, token, map[string]interface{}{
		"name": "  Janet Doe  ", "email": "janet@example.org", "phone": "912-555-0199", "gender": "nonbinary",
	})
	if updated["name"] != "Janet Doe" {
		t.Fatalf("expected trimmed new name, got %v", updated["name"])
	}

	// A fresh read must show the same values — i.e. they were really saved.
	me := getMe(t, h, token)
	if me["name"] != "Janet Doe" || me["email"] != "janet@example.org" ||
		me["phone"] != "912-555-0199" || me["gender"] != "nonbinary" {
		t.Fatalf("changes did not persist: %v", me)
	}
}

func TestUpdateProfileLeavesOmittedFieldsAlone(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{
		"name": "Jane Doe", "email": "jane@example.org", "phone": "912-555-0100", "gender": "female",
	})

	patchMe(t, h, token, map[string]interface{}{"name": "Jane Q. Doe"})

	me := getMe(t, h, token)
	if me["email"] != "jane@example.org" || me["phone"] != "912-555-0100" || me["gender"] != "female" {
		t.Fatalf("omitted fields should be untouched, got %v", me)
	}
}

func TestUpdateProfileEmptyStringClearsOptionalFields(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{
		"name": "Jane Doe", "email": "jane@example.org", "phone": "912-555-0100", "gender": "female",
	})

	patchMe(t, h, token, map[string]interface{}{"email": "", "phone": "  ", "gender": ""})

	me := getMe(t, h, token)
	if me["email"] != nil || me["phone"] != nil || me["gender"] != nil {
		t.Fatalf("expected email/phone/gender cleared, got %v", me)
	}
	if me["name"] != "Jane Doe" {
		t.Fatalf("name must be unaffected, got %v", me["name"])
	}
}

func TestUpdateProfileValidation(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	for _, tc := range []struct {
		name string
		body map[string]interface{}
	}{
		{"empty name", map[string]interface{}{"name": "   "}},
		{"unknown gender", map[string]interface{}{"gender": "banana"}},
	} {
		rec := doRequest(t, h, http.MethodPatch, "/api/me", token, tc.body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: expected 400, got %d", tc.name, rec.Code)
		}
	}

	if getMe(t, h, token)["name"] != "Jane Doe" {
		t.Fatal("a rejected update must not change anything")
	}
}

func TestUpdateProfileCannotPromoteYourselfWithoutTheCode(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	// Asking for a staff role alongside an ordinary edit must be refused as a
	// whole, so a participant can't promote themselves.
	if code := patchMeStatus(t, h, token, map[string]interface{}{"personType": "admin", "name": "Renamed"}); code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", code)
	}

	me := getMe(t, h, token)
	if me["personType"] != "homeless" || me["isStaff"] != false || me["name"] != "Jane Doe" {
		t.Fatalf("a refused request must change nothing, got %v", me)
	}
}

func TestUpdateProfileRequiresAuth(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPatch, "/api/me", "", map[string]interface{}{"name": "x"})
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestProfileDataIsEncryptedAtRest(t *testing.T) {
	h, db := setupTestServer(t)
	token, user := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	patchMe(t, h, token, map[string]interface{}{"name": "Distinctive Updated Name", "email": "secret@example.org"})

	var nameEnc, emailEnc []byte
	if err := db.QueryRow(`SELECT name_encrypted, email_encrypted FROM users WHERE id = ?`, user["id"]).Scan(&nameEnc, &emailEnc); err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(nameEnc, []byte("Distinctive")) || bytes.Contains(emailEnc, []byte("secret@example.org")) {
		t.Fatal("updated profile fields must be stored encrypted, found plaintext")
	}
}

// --- profile picture ---

func TestProfilePictureRoundTrip(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	if getMe(t, h, token)["hasProfilePicture"] != false {
		t.Fatal("new user should not have a profile picture")
	}
	if rec := doRequest(t, h, http.MethodGet, "/api/me/picture", token, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 before upload, got %d", rec.Code)
	}

	pic := []byte("\xff\xd8\xff fake jpeg bytes")
	rec := doRequest(t, h, http.MethodPut, "/api/me/picture", token, map[string]interface{}{
		"mimeType": "image/jpeg", "fileBase64": base64.StdEncoding.EncodeToString(pic),
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("PUT picture: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if getMe(t, h, token)["hasProfilePicture"] != true {
		t.Fatal("profile should report a picture after upload")
	}

	rec = doRequest(t, h, http.MethodGet, "/api/me/picture", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET picture: expected 200, got %d", rec.Code)
	}
	var got map[string]string
	decodeJSON(t, rec, &got)
	back, _ := base64.StdEncoding.DecodeString(got["fileBase64"])
	if !bytes.Equal(back, pic) || got["mimeType"] != "image/jpeg" {
		t.Fatalf("picture did not round-trip: mime=%q equal=%v", got["mimeType"], bytes.Equal(back, pic))
	}
}

func TestProfilePictureCanBeReplacedAndRemoved(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	put := func(content, mime string) {
		rec := doRequest(t, h, http.MethodPut, "/api/me/picture", token, map[string]interface{}{
			"mimeType": mime, "fileBase64": b64(content),
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("PUT: expected 200, got %d: %s", rec.Code, rec.Body.String())
		}
	}
	put("first", "image/jpeg")
	put("second", "image/png")

	rec := doRequest(t, h, http.MethodGet, "/api/me/picture", token, nil)
	var got map[string]string
	decodeJSON(t, rec, &got)
	back, _ := base64.StdEncoding.DecodeString(got["fileBase64"])
	if string(back) != "second" || got["mimeType"] != "image/png" {
		t.Fatalf("expected the replacement picture, got %q (%s)", back, got["mimeType"])
	}

	if rec := doRequest(t, h, http.MethodDelete, "/api/me/picture", token, nil); rec.Code != http.StatusOK {
		t.Fatalf("DELETE picture: expected 200, got %d", rec.Code)
	}
	if getMe(t, h, token)["hasProfilePicture"] != false {
		t.Fatal("profile should report no picture after removal")
	}
	if rec := doRequest(t, h, http.MethodGet, "/api/me/picture", token, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after removal, got %d", rec.Code)
	}
	// Removing when there is nothing to remove is not an error.
	if rec := doRequest(t, h, http.MethodDelete, "/api/me/picture", token, nil); rec.Code != http.StatusOK {
		t.Fatalf("second DELETE: expected 200, got %d", rec.Code)
	}
}

func TestProfilePictureValidation(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	for _, tc := range []struct {
		name string
		body map[string]interface{}
	}{
		{"pdf not allowed", map[string]interface{}{"mimeType": "application/pdf", "fileBase64": b64("x")}},
		{"not base64", map[string]interface{}{"mimeType": "image/jpeg", "fileBase64": "%%%not base64%%%"}},
		{"empty", map[string]interface{}{"mimeType": "image/jpeg", "fileBase64": ""}},
	} {
		rec := doRequest(t, h, http.MethodPut, "/api/me/picture", token, tc.body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: expected 400, got %d", tc.name, rec.Code)
		}
	}
}

func TestProfilePictureOverSizeLimitIsRejected(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	tooBig := strings.Repeat("a", maxProfilePictureBytes+1)
	rec := doRequest(t, h, http.MethodPut, "/api/me/picture", token, map[string]interface{}{
		"mimeType": "image/jpeg", "fileBase64": b64(tooBig),
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for an oversized picture, got %d", rec.Code)
	}
}

func TestProfilePictureIsPrivateToItsOwner(t *testing.T) {
	h := newTestServer(t)
	ownerToken, _ := registerUser(t, h, map[string]interface{}{"name": "Owner"})
	otherToken, _ := registerUser(t, h, map[string]interface{}{"name": "Other"})

	doRequest(t, h, http.MethodPut, "/api/me/picture", ownerToken, map[string]interface{}{
		"mimeType": "image/jpeg", "fileBase64": b64("owner face"),
	})

	// /api/me/picture is always "my own" picture, so another user asking for
	// theirs must never see the owner's.
	if rec := doRequest(t, h, http.MethodGet, "/api/me/picture", otherToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("other user must not get a picture, got %d", rec.Code)
	}
}

func TestProfilePictureIsStoredEncrypted(t *testing.T) {
	h, db, store := setupTestServerWithStore(t)
	token, user := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPut, "/api/me/picture", token, map[string]interface{}{
		"mimeType": "image/jpeg", "fileBase64": b64("PLAINTEXT-PICTURE-BYTES"),
	})

	var key string
	if err := db.QueryRow(`SELECT profile_picture_key FROM users WHERE id = ?`, user["id"]).Scan(&key); err != nil {
		t.Fatal(err)
	}
	raw, err := store.Get(context.Background(), key)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("PLAINTEXT-PICTURE-BYTES")) {
		t.Fatal("stored picture must be encrypted, found plaintext")
	}
}

// --- file size limits & account deletion ---

// Regression test: the global 16kb request cap used to stay in force on the
// document route (a second MaxBytesReader can't raise an outer one), so any
// real photo failed with "file too large". Every earlier test used
// a few dozen bytes and never noticed.
func TestUploadDocumentLargerThanTheGlobalBodyCap(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	photo := bytes.Repeat([]byte("scan"), 100*1024) // 400 KB, like a real phone scan
	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": "government_id", "mimeType": "image/jpeg",
		"fileBase64": base64.StdEncoding.EncodeToString(photo),
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("a 400 KB document should upload, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]documentMetaJSON
	decodeJSON(t, rec, &resp)
	got := doRequest(t, h, http.MethodGet, "/api/documents/"+resp["document"].ID, token, nil)
	var full struct {
		FileBase64 string `json:"fileBase64"`
	}
	decodeJSON(t, got, &full)
	back, _ := base64.StdEncoding.DecodeString(full.FileBase64)
	if !bytes.Equal(back, photo) {
		t.Fatal("large document did not round-trip intact")
	}
}

func TestOrdinaryRoutesStillHaveTheSmallBodyCap(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": strings.Repeat("a", 32*1024),
	})
	if rec.Code == http.StatusCreated {
		t.Fatal("exempting the file routes must not lift the 16kb cap on everything else")
	}
}

func TestDeleteAccountRemovesStoredFiles(t *testing.T) {
	h, db, store := setupTestServerWithStore(t)
	token, user := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})
	uploadTestDocument(t, h, token, "government_id", "id bytes")
	doRequest(t, h, http.MethodPut, "/api/me/picture", token, map[string]interface{}{
		"mimeType": "image/jpeg", "fileBase64": b64("face"),
	})

	var docKey, picKey string
	if err := db.QueryRow(`SELECT storage_key FROM documents WHERE user_id = ?`, user["id"]).Scan(&docKey); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT profile_picture_key FROM users WHERE id = ?`, user["id"]).Scan(&picKey); err != nil {
		t.Fatal(err)
	}

	if rec := doRequest(t, h, http.MethodDelete, "/api/account", token, nil); rec.Code != http.StatusOK {
		t.Fatalf("delete account: expected 200, got %d", rec.Code)
	}

	for _, key := range []string{docKey, picKey} {
		if _, err := store.Get(context.Background(), key); !errors.Is(err, blobstore.ErrNotFound) {
			t.Errorf("file %s should be gone after account deletion, Get returned %v", key, err)
		}
	}
}

// --- changing account type ---

func patchMeStatus(t *testing.T, h http.Handler, token string, body map[string]interface{}) int {
	t.Helper()
	return doRequest(t, h, http.MethodPatch, "/api/me", token, body).Code
}

func TestChangeToStaffNeedsTheStaffCode(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	for name, body := range map[string]map[string]interface{}{
		"no code":    {"personType": "volunteer"},
		"wrong code": {"personType": "admin", "staffCode": "wrong-code"},
	} {
		if code := patchMeStatus(t, h, token, body); code != http.StatusForbidden {
			t.Fatalf("%s: expected 403, got %d", name, code)
		}
	}
	me := getMe(t, h, token)
	if me["personType"] != "homeless" || me["isStaff"] != false {
		t.Fatalf("a refused change must leave the account alone: %v", me)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/locations/latest", token, nil).Code; code != http.StatusForbidden {
		t.Fatalf("still a participant, so the staff map must stay closed: got %d", code)
	}
}

func TestChangeToStaffWithTheRightCode(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	updated := patchMe(t, h, token, map[string]interface{}{"personType": "employee", "staffCode": testStaffCode})
	if updated["personType"] != "employee" || updated["isStaff"] != true {
		t.Fatalf("expected an employee, got %v", updated)
	}
	if got := getMe(t, h, token); got["personType"] != "employee" {
		t.Fatalf("change did not persist: %v", got)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/locations/latest", token, nil).Code; code != http.StatusOK {
		t.Fatalf("staff should now reach the staff map, got %d", code)
	}
}

func TestStaffCanBecomeAParticipantWithoutACode(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})

	updated := patchMe(t, h, token, map[string]interface{}{"personType": "homeless"})
	if updated["personType"] != "homeless" || updated["isStaff"] != false {
		t.Fatalf("expected a participant, got %v", updated)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/locations/latest", token, nil).Code; code != http.StatusForbidden {
		t.Fatalf("a participant must lose staff access, got %d", code)
	}
}

func TestSwitchingStaffRoleAgainNeedsTheCode(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})

	if code := patchMeStatus(t, h, token, map[string]interface{}{"personType": "admin"}); code != http.StatusForbidden {
		t.Fatalf("volunteer -> admin without the code must be refused, got %d", code)
	}
	if got := patchMe(t, h, token, map[string]interface{}{"personType": "admin", "staffCode": testStaffCode}); got["personType"] != "admin" {
		t.Fatalf("expected admin with the code, got %v", got)
	}
}

func TestChangeToAnUnknownAccountTypeIsRejected(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	if code := patchMeStatus(t, h, token, map[string]interface{}{"personType": "superuser", "staffCode": testStaffCode}); code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", code)
	}
}

func TestSendingTheSameAccountTypeIsANoOp(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	updated := patchMe(t, h, token, map[string]interface{}{"personType": "homeless", "name": "Janet Doe"})
	if updated["personType"] != "homeless" || updated["name"] != "Janet Doe" {
		t.Fatalf("unexpected result: %v", updated)
	}
}

func TestBecomingStaffStopsLocationSharing(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	if code := doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": true}).Code; code != http.StatusOK {
		t.Fatalf("granting consent: %d", code)
	}

	patchMe(t, h, token, map[string]interface{}{"personType": "volunteer", "staffCode": testStaffCode})
	patchMe(t, h, token, map[string]interface{}{"personType": "homeless"})

	rec := doRequest(t, h, http.MethodGet, "/api/consent/status", token, nil)
	var status map[string]interface{}
	decodeJSON(t, rec, &status)
	if status["granted"] != false {
		t.Fatalf("switching back must not silently resume sharing: %v", status)
	}
}
