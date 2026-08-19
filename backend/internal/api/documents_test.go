package api

import (
	"encoding/base64"
	"net/http"
	"strings"
	"testing"
)

func b64(s string) string {
	return base64.StdEncoding.EncodeToString([]byte(s))
}

func TestDocumentConsentIsIndependentFromLocationConsent(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	// Grant only document-storage consent.
	rec := doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("grant document consent: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var docStatus map[string]interface{}
	rec = doRequest(t, h, http.MethodGet, "/api/consent/documents/status", token, nil)
	decodeJSON(t, rec, &docStatus)
	if docStatus["granted"] != true {
		t.Fatalf("expected document consent granted, got %v", docStatus)
	}

	// Location consent must be completely unaffected.
	var locStatus map[string]interface{}
	rec = doRequest(t, h, http.MethodGet, "/api/consent/status", token, nil)
	decodeJSON(t, rec, &locStatus)
	if locStatus["granted"] != false {
		t.Fatalf("expected location consent to remain false, got %v", locStatus)
	}
}

func TestDocumentDisclosureIsPublicAndDistinctFromLocation(t *testing.T) {
	h := newTestServer(t)

	rec := doRequest(t, h, http.MethodGet, "/api/consent/documents/disclosure", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var docDisclosure map[string]string
	decodeJSON(t, rec, &docDisclosure)

	rec = doRequest(t, h, http.MethodGet, "/api/consent/disclosure", "", nil)
	var locDisclosure map[string]string
	decodeJSON(t, rec, &locDisclosure)

	if docDisclosure["text"] == "" {
		t.Fatal("expected non-empty document disclosure text")
	}
	if docDisclosure["text"] == locDisclosure["text"] {
		t.Fatal("expected document and location disclosure text to differ")
	}
}

func TestUploadDocumentRequiresConsent(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": "government_id",
		"mimeType":     "image/jpeg",
		"fileBase64":   b64("fake image bytes"),
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without document consent, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUploadDocumentRejectsInvalidType(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": "passport-photo-of-my-cat",
		"mimeType":     "image/jpeg",
		"fileBase64":   b64("x"),
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid documentType, got %d", rec.Code)
	}
}

func TestUploadDocumentRejectsInvalidMimeType(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": "government_id",
		"mimeType":     "application/x-executable",
		"fileBase64":   b64("x"),
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid mimeType, got %d", rec.Code)
	}
}

func TestUploadDocumentRejectsBadBase64(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": "government_id",
		"mimeType":     "image/jpeg",
		"fileBase64":   "not valid base64 !!!",
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid base64, got %d", rec.Code)
	}
}

func uploadTestDocument(t *testing.T, h http.Handler, token, docType, content string) documentMetaJSON {
	t.Helper()
	rec := doRequest(t, h, http.MethodPost, "/api/documents", token, map[string]interface{}{
		"documentType": docType,
		"label":        "my test doc",
		"mimeType":     "image/jpeg",
		"fileBase64":   b64(content),
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("upload: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]documentMetaJSON
	decodeJSON(t, rec, &resp)
	return resp["document"]
}

func TestUploadAndListDocuments(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	meta := uploadTestDocument(t, h, token, "government_id", "fake license bytes")
	if meta.ID == "" {
		t.Fatal("expected a document id")
	}
	if meta.Label == nil || *meta.Label != "my test doc" {
		t.Fatalf("expected label to round-trip, got %v", meta.Label)
	}
	if meta.FileSizeBytes != int64(len("fake license bytes")) {
		t.Fatalf("expected file size %d, got %d", len("fake license bytes"), meta.FileSizeBytes)
	}

	rec := doRequest(t, h, http.MethodGet, "/api/documents", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var listResp map[string][]documentMetaJSON
	decodeJSON(t, rec, &listResp)
	if len(listResp["documents"]) != 1 {
		t.Fatalf("expected 1 document, got %d", len(listResp["documents"]))
	}
}

func TestGetDocumentDecryptsCorrectly(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})

	content := "this is definitely a driver's license, trust me"
	meta := uploadTestDocument(t, h, token, "government_id", content)

	rec := doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	gotB64, _ := resp["fileBase64"].(string)
	gotBytes, err := base64.StdEncoding.DecodeString(gotB64)
	if err != nil {
		t.Fatalf("decoding returned base64: %v", err)
	}
	if string(gotBytes) != content {
		t.Fatalf("decrypted content mismatch: got %q, want %q", gotBytes, content)
	}
}

func TestOtherUserCannotGetSomeoneElsesDocument(t *testing.T) {
	h := newTestServer(t)
	ownerToken, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", ownerToken, map[string]interface{}{"granted": true})
	meta := uploadTestDocument(t, h, ownerToken, "social_security_card", "secret ssn card contents")

	otherToken, _ := registerUser(t, h, map[string]interface{}{"name": "Someone Else"})

	rec := doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, otherToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for another user's document, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestOtherUserCannotDeleteSomeoneElsesDocument(t *testing.T) {
	h := newTestServer(t)
	ownerToken, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", ownerToken, map[string]interface{}{"granted": true})
	meta := uploadTestDocument(t, h, ownerToken, "birth_certificate", "birth cert contents")

	otherToken, _ := registerUser(t, h, map[string]interface{}{"name": "Someone Else"})

	rec := doRequest(t, h, http.MethodDelete, "/api/documents/"+meta.ID, otherToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}

	// Owner can still fetch it — the other user's attempt did not delete it.
	rec = doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, ownerToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected owner to still be able to fetch it, got %d", rec.Code)
	}
}

func TestOwnerCanDeleteOwnDocument(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})
	meta := uploadTestDocument(t, h, token, "other", "some other document")

	rec := doRequest(t, h, http.MethodDelete, "/api/documents/"+meta.ID, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, token, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 after deletion, got %d", rec.Code)
	}
}

func TestGetNonexistentDocumentReturns404(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodGet, "/api/documents/does-not-exist", token, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestNonStaffCannotSeeDocumentsOnFile(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodGet, "/api/documents/on-file", token, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-staff, got %d", rec.Code)
	}
}

func TestStaffSeesDocumentTypesOnFileButNeverContent(t *testing.T) {
	h := newTestServer(t)

	participantToken, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", participantToken, map[string]interface{}{"granted": true})
	uploadTestDocument(t, h, participantToken, "government_id", "license contents")
	uploadTestDocument(t, h, participantToken, "social_security_card", "ssn card contents")

	staffToken, _ := registerUser(t, h, map[string]interface{}{
		"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode,
	})

	rec := doRequest(t, h, http.MethodGet, "/api/documents/on-file", staffToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	body := rec.Body.String()
	if strings.Contains(body, "license contents") || strings.Contains(body, "ssn card contents") {
		t.Fatal("staff response must never contain raw document content")
	}

	var resp map[string][]documentsOnFileJSON
	decodeJSON(t, rec, &resp)
	participants := resp["participants"]
	if len(participants) != 1 {
		t.Fatalf("expected 1 participant with documents, got %d", len(participants))
	}
	if participants[0].Name == nil || *participants[0].Name != "Jane Doe" {
		t.Fatalf("expected participant name to decrypt correctly, got %v", participants[0].Name)
	}
	if len(participants[0].DocumentTypes) != 2 {
		t.Fatalf("expected 2 document types on file, got %d: %v", len(participants[0].DocumentTypes), participants[0].DocumentTypes)
	}
}

func TestDocumentAccessIsLogged(t *testing.T) {
	h, db := setupTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true})
	meta := uploadTestDocument(t, h, token, "government_id", "license contents")

	doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, token, nil)
	doRequest(t, h, http.MethodGet, "/api/documents/"+meta.ID, token, nil)

	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM document_access_log WHERE document_id = ?`, meta.ID).Scan(&count); err != nil {
		t.Fatalf("querying access log: %v", err)
	}
	if count != 2 {
		t.Fatalf("expected 2 access log entries, got %d", count)
	}
}
