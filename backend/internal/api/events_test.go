package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEventsArePublicAndCacheable(t *testing.T) {
	h := newTestServer(t)

	rec := doRequest(t, h, http.MethodGet, "/api/events", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 without signing in, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("unexpected content type %q", ct)
	}
	var body struct {
		UpdatedAt string                   `json:"updatedAt"`
		Events    []map[string]interface{} `json:"events"`
	}
	decodeJSON(t, rec, &body)
	if body.UpdatedAt == "" {
		t.Fatalf("expected real content, got %+v", body)
	}

	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatal("expected an ETag")
	}

	req := httptest.NewRequest(http.MethodGet, "/api/events", nil)
	req.Header.Set("If-None-Match", etag)
	again := httptest.NewRecorder()
	h.ServeHTTP(again, req)
	if again.Code != http.StatusNotModified || again.Body.Len() != 0 {
		t.Fatalf("expected an empty 304, got %d with %d bytes", again.Code, again.Body.Len())
	}
}
