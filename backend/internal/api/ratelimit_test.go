package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestAdminSignupIsRefusedWhenNoInviteCodeIsConfigured(t *testing.T) {
	h := newTestServer(t)
	t.Setenv("STAFF_INVITE_CODE", "")

	// Neither the old built-in default nor an empty code gets anyone in.
	for _, code := range []string{"g2g-staff", ""} {
		rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
			"name": "Would-be Admin", "phone": "912-555-0100", "personType": "admin", "staffCode": code,
		})
		if rec.Code != http.StatusForbidden {
			t.Fatalf("staffCode %q: expected 403 with no STAFF_INVITE_CODE set, got %d: %s", code, rec.Code, rec.Body.String())
		}
	}

	// Switching an existing account to admin is refused the same way.
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	rec := doRequest(t, h, http.MethodPatch, "/api/me", token, map[string]interface{}{
		"personType": "admin", "staffCode": "g2g-staff",
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("switch to admin: expected 403 with no STAFF_INVITE_CODE set, got %d: %s", rec.Code, rec.Body.String())
	}

	// Everyone else can still sign up.
	registerUser(t, h, map[string]interface{}{"name": "Val Unteer", "personType": "volunteer"})
}

func TestAdminSignupStillWorksWithTheConfiguredCode(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Real Admin", "phone": "912-555-0100", "personType": "admin", "staffCode": "g2g-staff",
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("old default code should not work when a different code is set, got %d", rec.Code)
	}
	registerUser(t, h, map[string]interface{}{"name": "Real Admin", "personType": "admin", "staffCode": testStaffCode})
}

func postFrom(h http.Handler, path, remoteAddr string, headers map[string]string, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = remoteAddr
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestSignupIsRateLimitedPerIP(t *testing.T) {
	h, _, _ := setupTestServerWithOptions(t, withRateLimits(newRateLimiter(3, time.Hour), nil))
	body := `{"name":"Jane Doe","phone":"912-555-0100"}`

	for i := 0; i < 3; i++ {
		if rec := postFrom(h, "/api/users", "203.0.113.5:4000", nil, body); rec.Code != http.StatusCreated {
			t.Fatalf("sign-up %d: expected 201, got %d: %s", i+1, rec.Code, rec.Body.String())
		}
	}
	rec := postFrom(h, "/api/users", "203.0.113.5:4001", nil, body)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("4th sign-up from the same IP: expected 429, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatalf("expected a Retry-After header on 429")
	}

	// A different address has its own allowance.
	if rec := postFrom(h, "/api/users", "198.51.100.7:4000", nil, body); rec.Code != http.StatusCreated {
		t.Fatalf("other IP: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRecoveryIsRateLimitedPerIP(t *testing.T) {
	h, _, _ := setupTestServerWithOptions(t, withRateLimits(nil, newRateLimiter(2, 15*time.Minute)))
	body := `{"code":"AAAA-BBBB-CCCC"}`

	for i := 0; i < 2; i++ {
		if rec := postFrom(h, "/api/recover", "203.0.113.5:4000", nil, body); rec.Code != http.StatusNotFound {
			t.Fatalf("guess %d: expected 404, got %d: %s", i+1, rec.Code, rec.Body.String())
		}
	}
	if rec := postFrom(h, "/api/recover", "203.0.113.5:4000", nil, body); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("3rd guess: expected 429, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRateLimitUsesTheConfiguredProxyHeader(t *testing.T) {
	t.Setenv("CLIENT_IP_HEADER", "X-Forwarded-For")
	h, _, _ := setupTestServerWithOptions(t, withRateLimits(nil, newRateLimiter(1, time.Hour)))
	body := `{"code":"AAAA-BBBB-CCCC"}`
	proxy := "10.0.0.2:5000" // every request arrives from the proxy

	if rec := postFrom(h, "/api/recover", proxy, map[string]string{"X-Forwarded-For": "203.0.113.5"}, body); rec.Code != http.StatusNotFound {
		t.Fatalf("first client: expected 404, got %d", rec.Code)
	}
	if rec := postFrom(h, "/api/recover", proxy, map[string]string{"X-Forwarded-For": "198.51.100.7"}, body); rec.Code != http.StatusNotFound {
		t.Fatalf("second client behind the same proxy should have its own allowance, got %d", rec.Code)
	}
	// A client can't dodge the limit by prepending its own fake address: the
	// last entry, added by the proxy, is the one that counts.
	if rec := postFrom(h, "/api/recover", proxy, map[string]string{"X-Forwarded-For": "1.2.3.4, 203.0.113.5"}, body); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("first client again: expected 429, got %d", rec.Code)
	}
}

func TestRateLimiterWindowResets(t *testing.T) {
	now := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)
	l := newRateLimiter(2, time.Minute)
	l.now = func() time.Time { return now }

	for i := 0; i < 2; i++ {
		if ok, _ := l.allow("a"); !ok {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
	ok, retry := l.allow("a")
	if ok || retry != time.Minute {
		t.Fatalf("expected refusal with a 1m wait, got ok=%v retry=%v", ok, retry)
	}

	now = now.Add(time.Minute)
	if ok, _ := l.allow("a"); !ok {
		t.Fatalf("a new window should allow requests again")
	}
	if len(l.hits) != 1 {
		t.Fatalf("expected the sweep to keep only live windows, got %d", len(l.hits))
	}
}
