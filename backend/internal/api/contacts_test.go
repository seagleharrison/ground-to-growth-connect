package api

import (
	"net/http"
	"strings"
	"testing"
)

func contactList(t *testing.T, h http.Handler, token string) []interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodGet, "/api/admin/contacts", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list contacts: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return out["contacts"].([]interface{})
}

func addContact(t *testing.T, h http.Handler, token string, body map[string]interface{}) map[string]interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodPost, "/api/admin/contacts", token, body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("add contact: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return asMap(t, out["contact"])
}

func TestAdminsKeepAContactBookWithNamePhoneEmailAndNotes(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)

	c := addContact(t, h, ada, map[string]interface{}{
		"name": "  Union Mission  ", "phone": "912-355-1234", "email": "intake@example.org", "notes": "Meals at 5. Ask for Denise.",
	})
	if c["name"] != "Union Mission" || c["phone"] != "912-355-1234" || c["email"] != "intake@example.org" || c["notes"] != "Meals at 5. Ask for Denise." {
		t.Fatalf("unexpected contact: %v", c)
	}
	list := contactList(t, h, ada)
	if len(list) != 1 || asMap(t, list[0])["id"] != c["id"] {
		t.Fatalf("the contact should be listed, got %v", list)
	}

	// Edit: only what is sent changes; a blank clears a field; the name can't be emptied.
	id := c["id"].(string)
	rec := doRequest(t, h, http.MethodPatch, "/api/admin/contacts/"+id, ada, map[string]interface{}{"phone": "912-555-0000", "email": ""})
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	u := asMap(t, out["contact"])
	if rec.Code != http.StatusOK || u["phone"] != "912-555-0000" || u["email"] != nil || u["notes"] != "Meals at 5. Ask for Denise." || u["name"] != "Union Mission" {
		t.Fatalf("partial edit: got %d %v", rec.Code, u)
	}
	if code := doRequest(t, h, http.MethodPatch, "/api/admin/contacts/"+id, ada, map[string]interface{}{"name": "  "}).Code; code != http.StatusBadRequest {
		t.Fatalf("emptying the name: expected 400, got %d", code)
	}

	if code := doRequest(t, h, http.MethodDelete, "/api/admin/contacts/"+id, ada, nil).Code; code != http.StatusOK {
		t.Fatalf("delete: expected 200, got %d", code)
	}
	if len(contactList(t, h, ada)) != 0 {
		t.Fatalf("a deleted contact should be gone")
	}
	if code := doRequest(t, h, http.MethodDelete, "/api/admin/contacts/"+id, ada, nil).Code; code != http.StatusNotFound {
		t.Fatalf("deleting twice: expected 404, got %d", code)
	}
}

func TestContactsAreSharedByAdminsAndListedAlphabetically(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)
	bo, _ := newAdmin(t, h)
	addContact(t, h, ada, map[string]interface{}{"name": "zeta clinic"})
	addContact(t, h, bo, map[string]interface{}{"name": "Alpha Shelter"})
	addContact(t, h, ada, map[string]interface{}{"name": "Mid Town Kitchen"})

	var names []string
	for _, c := range contactList(t, h, bo) {
		names = append(names, asMap(t, c)["name"].(string))
	}
	if strings.Join(names, "|") != "Alpha Shelter|Mid Town Kitchen|zeta clinic" {
		t.Fatalf("every admin sees every contact, A to Z ignoring case, got %v", names)
	}
}

func TestOnlyAdminsCanTouchTheContactBook(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := addContact(t, h, ada, map[string]interface{}{"name": "Clinic"})["id"].(string)

	for who, token := range map[string]string{"participant": jane, "volunteer": sam, "signed out": ""} {
		want := http.StatusForbidden
		if token == "" {
			want = http.StatusUnauthorized
		}
		for _, call := range []struct{ method, path string }{
			{http.MethodGet, "/api/admin/contacts"},
			{http.MethodPost, "/api/admin/contacts"},
			{http.MethodPatch, "/api/admin/contacts/" + id},
			{http.MethodDelete, "/api/admin/contacts/" + id},
		} {
			if code := doRequest(t, h, call.method, call.path, token, map[string]interface{}{"name": "x"}).Code; code != want {
				t.Fatalf("%s %s %s: expected %d, got %d", who, call.method, call.path, want, code)
			}
		}
	}
	if len(contactList(t, h, ada)) != 1 {
		t.Fatalf("nothing should have changed")
	}
}

func TestAContactNeedsANameAndIsEncryptedAtRest(t *testing.T) {
	h, db := setupTestServer(t)
	ada, _ := newAdmin(t, h)
	if code := doRequest(t, h, http.MethodPost, "/api/admin/contacts", ada, map[string]interface{}{"phone": "912-555-0101"}).Code; code != http.StatusBadRequest {
		t.Fatalf("no name: expected 400, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/admin/contacts", ada, map[string]interface{}{"name": "   "}).Code; code != http.StatusBadRequest {
		t.Fatalf("blank name: expected 400, got %d", code)
	}
	addContact(t, h, ada, map[string]interface{}{"name": "Dr Quiet", "phone": "912-555-0177", "email": "quiet@example.org", "notes": "private details"})
	var name, phone, email, notes []byte
	if err := db.QueryRow(`SELECT name_encrypted, phone_encrypted, email_encrypted, notes_encrypted FROM contacts`).Scan(&name, &phone, &email, &notes); err != nil {
		t.Fatalf("query: %v", err)
	}
	for field, raw := range map[string][]byte{"name": name, "phone": phone, "email": email, "notes": notes} {
		if strings.Contains(string(raw), "Quiet") || strings.Contains(string(raw), "555") || strings.Contains(string(raw), "example.org") || strings.Contains(string(raw), "private") {
			t.Fatalf("%s must not be stored in plaintext", field)
		}
	}
}

func TestContactsOutliveTheAdminWhoAddedThem(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)
	bo, _ := newAdmin(t, h)
	addContact(t, h, ada, map[string]interface{}{"name": "Clinic"})
	doRequest(t, h, http.MethodDelete, "/api/account", ada, nil)
	if len(contactList(t, h, bo)) != 1 {
		t.Fatalf("the team's contacts must stay when the admin who added one leaves")
	}
}
