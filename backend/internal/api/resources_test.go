package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestResourcesArePublicAndCacheable(t *testing.T) {
	h := newTestServer(t)

	rec := doRequest(t, h, http.MethodGet, "/api/resources", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 without signing in, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("unexpected content type %q", ct)
	}
	var body struct {
		UpdatedAt      string                   `json:"updatedAt"`
		DocumentGuides []map[string]interface{} `json:"documentGuides"`
		Places         []map[string]interface{} `json:"places"`
	}
	decodeJSON(t, rec, &body)
	if body.UpdatedAt == "" || len(body.DocumentGuides) == 0 || len(body.Places) == 0 {
		t.Fatalf("expected real content, got %+v", body)
	}

	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatal("expected an ETag")
	}

	// Asking again with the ETag gets a tiny "nothing new" instead of the whole thing.
	req := httptest.NewRequest(http.MethodGet, "/api/resources", nil)
	req.Header.Set("If-None-Match", etag)
	again := httptest.NewRecorder()
	h.ServeHTTP(again, req)
	if again.Code != http.StatusNotModified || again.Body.Len() != 0 {
		t.Fatalf("expected an empty 304, got %d with %d bytes", again.Code, again.Body.Len())
	}

	// A different ETag (the app has an older copy) gets the full content.
	req = httptest.NewRequest(http.MethodGet, "/api/resources", nil)
	req.Header.Set("If-None-Match", `"stale"`)
	fresh := httptest.NewRecorder()
	h.ServeHTTP(fresh, req)
	if fresh.Code != http.StatusOK || fresh.Body.Len() == 0 {
		t.Fatalf("expected full content for a stale ETag, got %d", fresh.Code)
	}
}

type sourceReport struct {
	Total       int `json:"total"`
	CannotCheck []struct {
		URL    string `json:"url"`
		Status int    `json:"status"`
	} `json:"cannotCheck"`
	NeedsAttention []struct {
		URL    string `json:"url"`
		Reason string `json:"reason"`
		Status int    `json:"status"`
	} `json:"needsAttention"`
}

func TestSourceReportIsAdminOnly(t *testing.T) {
	h := newTestServer(t)
	participant, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	volunteer, _ := registerUser(t, h, map[string]interface{}{"name": "Vic", "personType": "volunteer", "staffCode": testStaffCode})
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})

	if code := doRequest(t, h, http.MethodGet, "/api/analytics/sources", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("no token: expected 401, got %d", code)
	}
	for name, token := range map[string]string{"participant": participant, "volunteer": volunteer} {
		if code := doRequest(t, h, http.MethodGet, "/api/analytics/sources", token, nil).Code; code != http.StatusForbidden {
			t.Fatalf("%s: expected 403, got %d", name, code)
		}
		if code := doRequest(t, h, http.MethodPost, "/api/analytics/sources/reviewed", token, map[string]interface{}{"url": "x"}).Code; code != http.StatusForbidden {
			t.Fatalf("%s: marking reviewed must be refused, got %d", name, code)
		}
	}
	if code := doRequest(t, h, http.MethodGet, "/api/analytics/sources", admin, nil).Code; code != http.StatusOK {
		t.Fatalf("admin: expected 200, got %d", code)
	}
}

func TestAdminSeesFlaggedPagesAndCanClearThem(t *testing.T) {
	h, db := setupTestServer(t)
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})

	mustExec := func(q string, args ...interface{}) {
		t.Helper()
		if _, err := db.Exec(q, args...); err != nil {
			t.Fatal(err)
		}
	}
	mustExec(`INSERT INTO source_checks (url, status, content_hash, reviewed_hash, checked_at, first_checked_at)
	          VALUES ('https://example.org/fine', 200, 'a', 'a', '2026-09-21T00:00:00.000Z', '2026-09-01T00:00:00.000Z')`)
	mustExec(`INSERT INTO source_checks (url, status, content_hash, reviewed_hash, checked_at, first_checked_at)
	          VALUES ('https://example.org/changed', 200, 'b2', 'b1', '2026-09-21T00:00:00.000Z', '2026-09-01T00:00:00.000Z')`)
	mustExec(`INSERT INTO source_checks (url, status, checked_at, first_checked_at)
	          VALUES ('https://example.org/gone', 404, '2026-09-21T00:00:00.000Z', '2026-09-01T00:00:00.000Z')`)

	mustExec(`INSERT INTO source_checks (url, status, checked_at, first_checked_at)
	          VALUES ('https://example.org/blocks-bots', 403, '2026-09-21T00:00:00.000Z', '2026-09-01T00:00:00.000Z')`)

	get := func() sourceReport {
		rec := doRequest(t, h, http.MethodGet, "/api/analytics/sources", admin, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("got %d: %s", rec.Code, rec.Body.String())
		}
		var r sourceReport
		decodeJSON(t, rec, &r)
		return r
	}

	r := get()
	if r.Total != 4 || len(r.NeedsAttention) != 2 {
		t.Fatalf("expected 4 watched and 2 flagged, got %+v", r)
	}
	if len(r.CannotCheck) != 1 || r.CannotCheck[0].URL != "https://example.org/blocks-bots" {
		t.Fatalf("the site that blocks automatic checks belongs in its own list: %+v", r)
	}

	for _, url := range []string{"https://example.org/changed", "https://example.org/gone"} {
		rec := doRequest(t, h, http.MethodPost, "/api/analytics/sources/reviewed", admin, map[string]interface{}{"url": url})
		if rec.Code != http.StatusOK {
			t.Fatalf("reviewing %s: %d %s", url, rec.Code, rec.Body.String())
		}
	}
	if r := get(); len(r.NeedsAttention) != 0 {
		t.Fatalf("everything was reviewed, expected nothing flagged: %+v", r)
	}

	if code := doRequest(t, h, http.MethodPost, "/api/analytics/sources/reviewed", admin, map[string]interface{}{"url": "https://example.org/unknown"}).Code; code != http.StatusNotFound {
		t.Fatalf("unknown page: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/analytics/sources/reviewed", admin, map[string]interface{}{}).Code; code != http.StatusBadRequest {
		t.Fatalf("missing url: expected 400, got %d", code)
	}
}
