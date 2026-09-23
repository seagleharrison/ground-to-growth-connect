package api

import (
	"net/http"
	"testing"
)

func TestRegisterReturnsAOneTimeRecoveryCode(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Jane Doe", "phone": "912-555-0100",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	code, _ := resp["recoveryCode"].(string)
	if code == "" {
		t.Fatalf("expected a recovery code in the register response, got %v", resp)
	}
	if len(code) < 10 {
		t.Fatalf("recovery code looks too short to be meaningful: %q", code)
	}
}

func TestRecoverSignsBackIntoTheSameAccountAndEndsTheOldSession(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Jane Doe", "phone": "912-555-0100",
	})
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	code := resp["recoveryCode"].(string)
	oldToken := resp["token"].(string)
	userID := resp["user"].(map[string]interface{})["id"]

	// The old device still works until recovery actually happens.
	if got := doRequest(t, h, http.MethodGet, "/api/me", oldToken, nil).Code; got != http.StatusOK {
		t.Fatalf("old token should still work before recovery, got %d", got)
	}

	recoverRec := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": code})
	if recoverRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", recoverRec.Code, recoverRec.Body.String())
	}
	var recovered map[string]interface{}
	decodeJSON(t, recoverRec, &recovered)
	newToken := recovered["token"].(string)
	if newToken == "" || newToken == oldToken {
		t.Fatalf("expected a fresh token, got %v", recovered["token"])
	}
	recoveredUser := recovered["user"].(map[string]interface{})
	if recoveredUser["id"] != userID || recoveredUser["name"] != "Jane Doe" {
		t.Fatalf("expected to recover the same account, got %v", recoveredUser)
	}

	// The new device works...
	if got := doRequest(t, h, http.MethodGet, "/api/me", newToken, nil).Code; got != http.StatusOK {
		t.Fatalf("new token should work, got %d", got)
	}
	// ...and the old, presumably-lost device no longer does.
	if got := doRequest(t, h, http.MethodGet, "/api/me", oldToken, nil).Code; got != http.StatusUnauthorized {
		t.Fatalf("old token should be dead after recovery, got %d", got)
	}
}

func TestRecoverIsCaseAndFormattingInsensitive(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Jane Doe", "phone": "912-555-0100",
	})
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	code := resp["recoveryCode"].(string)

	messy := "  " + toLower(code) + "  "
	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": messy}).Code; got != http.StatusOK {
		t.Fatalf("a differently-cased/spaced but otherwise identical code should still work, got %d", got)
	}
}

func toLower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c - 'A' + 'a'
		}
	}
	return string(b)
}

func TestRecoverRejectsAWrongOrMissingCode(t *testing.T) {
	h := newTestServer(t)
	doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{"name": "Jane Doe", "phone": "912-555-0100"})

	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": "NOPE-NOPE-NOPE"}).Code; got != http.StatusNotFound {
		t.Fatalf("wrong code: expected 404, got %d", got)
	}
	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": ""}).Code; got != http.StatusBadRequest {
		t.Fatalf("empty code: expected 400, got %d", got)
	}
	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{}).Code; got != http.StatusBadRequest {
		t.Fatalf("missing code: expected 400, got %d", got)
	}
}

func TestRecoveryCodesAreUniquePerAccount(t *testing.T) {
	h := newTestServer(t)
	_, a := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, b := registerUser(t, h, map[string]interface{}{"name": "John Roe"})
	if a["id"] == b["id"] {
		t.Fatal("test setup: expected two different accounts")
	}
	// Both recovery codes were consumed by registerUser's response already, so
	// this test only needs to confirm they don't collide — re-derive by
	// registering directly and comparing the raw codes.
	recA := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{"name": "Ada", "phone": "912-555-0101"})
	recB := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{"name": "Bea", "phone": "912-555-0102"})
	var respA, respB map[string]interface{}
	decodeJSON(t, recA, &respA)
	decodeJSON(t, recB, &respB)
	if respA["recoveryCode"] == respB["recoveryCode"] {
		t.Fatal("two different accounts must not get the same recovery code")
	}
}

func TestRegenerateRecoveryCodeReplacesTheOldOne(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{"name": "Jane Doe", "phone": "912-555-0100"})
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	oldCode := resp["recoveryCode"].(string)
	token := resp["token"].(string)

	if code := doRequest(t, h, http.MethodPost, "/api/me/recovery-code", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("must require sign-in, got %d", code)
	}

	regenRec := doRequest(t, h, http.MethodPost, "/api/me/recovery-code", token, nil)
	if regenRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", regenRec.Code, regenRec.Body.String())
	}
	var regenerated map[string]interface{}
	decodeJSON(t, regenRec, &regenerated)
	newCode := regenerated["recoveryCode"].(string)
	if newCode == "" || newCode == oldCode {
		t.Fatalf("expected a different code, got %v", regenerated)
	}

	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": oldCode}).Code; got != http.StatusNotFound {
		t.Fatalf("the old code must stop working, got %d", got)
	}
	if got := doRequest(t, h, http.MethodPost, "/api/recover", "", map[string]interface{}{"code": newCode}).Code; got != http.StatusOK {
		t.Fatalf("the new code must work, got %d", got)
	}
}
