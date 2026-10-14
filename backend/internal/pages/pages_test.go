package pages

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func get(t *testing.T, h http.HandlerFunc) (int, string, http.Header) {
	t.Helper()
	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	return rec.Code, rec.Body.String(), rec.Header()
}

func TestThePrivacyPolicyNamesWhoWeAreAndWhatWeDo(t *testing.T) {
	t.Setenv("CONTACT_EMAIL", "")
	code, body, header := get(t, Privacy())
	if code != http.StatusOK || !strings.HasPrefix(header.Get("Content-Type"), "text/html") {
		t.Fatalf("expected an HTML page, got %d %s", code, header.Get("Content-Type"))
	}
	for _, want := range []string{
		"Ground to Growth Initiative", "1305 Barnard Street #2041", "Privacy Policy", Updated,
		"200 meters", "do <strong>not</strong> sell", "Delete my data", "911", "988", "OpenStreetMap",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("the privacy policy should say %q", want)
		}
	}
	if strings.Contains(body, "mailto:") {
		t.Fatalf("with no contact email set there should be no mailto link")
	}
	if strings.Contains(body, "{{") || strings.Contains(body, "<no value>") {
		t.Fatalf("the page must not show template leftovers")
	}
}

func TestTheContactEmailIsShownWhenSetAndEscaped(t *testing.T) {
	t.Setenv("CONTACT_EMAIL", `help@example.org"><script>alert(1)</script>`)
	_, body, _ := get(t, Privacy())
	if strings.Contains(body, "<script>alert(1)</script>") {
		t.Fatalf("the email must be escaped")
	}
	t.Setenv("CONTACT_EMAIL", "help@example.org")
	_, body, _ = get(t, Privacy())
	if !strings.Contains(body, `href="mailto:help@example.org"`) {
		t.Fatalf("the contact email should be a mailto link")
	}
	_, support, _ := get(t, Support())
	if !strings.Contains(support, "help@example.org") || !strings.Contains(support, "/privacy") {
		t.Fatalf("the support page should show the contact and link to the policy")
	}
}

func TestTheSupportPageHasEmergencyNumbersAndHowToDeleteData(t *testing.T) {
	_, body, _ := get(t, Support())
	for _, want := range []string{"911", "988", "Delete my data", "recovery code"} {
		if !strings.Contains(body, want) {
			t.Fatalf("support should say %q", want)
		}
	}
}

func TestThePagesAllowTheirOwnStylesButNothingElse(t *testing.T) {
	_, _, header := get(t, Privacy())
	csp := header.Get("Content-Security-Policy")
	if !strings.Contains(csp, "style-src 'unsafe-inline'") || !strings.Contains(csp, "default-src 'none'") || strings.Contains(csp, "script-src") {
		t.Fatalf("the page may use its inline styles and nothing else, got %q", csp)
	}
}
