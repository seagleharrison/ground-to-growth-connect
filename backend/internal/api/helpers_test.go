package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"ground-to-growth-connect-backend/internal/blobstore"
	"ground-to-growth-connect-backend/internal/dbstore"
)

const testEncryptionKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const testStaffCode = "test-staff-code"

// setupTestServer spins up a real Server backed by a temp-file SQLite
// database, migrated with the actual production schema, so these tests
// exercise the full request path (routing, middleware, SQL, encryption)
// rather than mocks. Most tests only need the handler — use newTestServer
// for those; setupTestServer is for the rare test that also needs direct DB
// access (e.g. to check an audit log row).
func setupTestServer(t *testing.T) (http.Handler, *sql.DB) {
	t.Helper()
	t.Setenv("ENCRYPTION_KEY", testEncryptionKey)
	t.Setenv("STAFF_INVITE_CODE", testStaffCode)
	t.Setenv("CORS_ORIGIN", "http://localhost:5173")
	t.Setenv("CONSENT_VERSION", "1.0")

	dbPath := filepath.Join(t.TempDir(), "test.db")
	db, err := dbstore.Open(dbPath)
	if err != nil {
		t.Fatalf("dbstore.Open: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	schema, err := os.ReadFile(filepath.Join("..", "..", "sql", "001_init.sql"))
	if err != nil {
		t.Fatalf("reading schema: %v", err)
	}
	if err := dbstore.Migrate(db, string(schema)); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	docs, err := blobstore.NewLocalDiskStore(filepath.Join(t.TempDir(), "documents"))
	if err != nil {
		t.Fatalf("blobstore.NewLocalDiskStore: %v", err)
	}

	return NewServer(db, docs), db
}

func newTestServer(t *testing.T) http.Handler {
	t.Helper()
	h, _ := setupTestServer(t)
	return h
}

func doRequest(t *testing.T, h http.Handler, method, path, token string, body interface{}) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		reader = bytes.NewReader(b)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func decodeJSON(t *testing.T, rec *httptest.ResponseRecorder, v interface{}) {
	t.Helper()
	if err := json.Unmarshal(rec.Body.Bytes(), v); err != nil {
		t.Fatalf("decoding response body %q: %v", rec.Body.String(), err)
	}
}

// registerUser is a shared helper for tests that just need a valid account
// and don't care about the registration response shape themselves.
func registerUser(t *testing.T, h http.Handler, payload map[string]interface{}) (token string, user map[string]interface{}) {
	t.Helper()
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", payload)
	if rec.Code != http.StatusCreated {
		t.Fatalf("register: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var resp map[string]interface{}
	decodeJSON(t, rec, &resp)
	token, _ = resp["token"].(string)
	user, _ = resp["user"].(map[string]interface{})
	if token == "" {
		t.Fatalf("register: expected non-empty token, got response %v", resp)
	}
	return token, user
}
