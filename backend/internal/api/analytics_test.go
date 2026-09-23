package api

import (
	"net/http"
	"strings"
	"testing"
)

type analyticsPayload struct {
	People struct {
		Participants, Volunteers, Admins int
	}
	Sharing struct {
		ParticipantsSharing, ActiveLast24Hours, ActiveLast7Days int
	}
	Documents struct {
		ParticipantsUsingStorage, ParticipantsWithAllThree, DocumentsStored int
	}
	Daily []struct {
		Date              string
		Signups, CheckIns int
	}
}

func getAnalytics(t *testing.T, h http.Handler, token string) analyticsPayload {
	t.Helper()
	rec := doRequest(t, h, http.MethodGet, "/api/analytics", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /api/analytics: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var out analyticsPayload
	decodeJSON(t, rec, &out)
	return out
}

func TestAnalyticsIsAdminOnly(t *testing.T) {
	h := newTestServer(t)
	participant, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	volunteer, _ := registerUser(t, h, map[string]interface{}{"name": "Vic", "personType": "volunteer", "staffCode": testStaffCode})
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})

	if code := doRequest(t, h, http.MethodGet, "/api/analytics", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("no token: expected 401, got %d", code)
	}
	for name, token := range map[string]string{"participant": participant, "volunteer": volunteer} {
		if code := doRequest(t, h, http.MethodGet, "/api/analytics", token, nil).Code; code != http.StatusForbidden {
			t.Fatalf("%s: expected 403, got %d", name, code)
		}
	}
	getAnalytics(t, h, admin) // an admin gets in
}

func TestAnalyticsAccessFollowsTheCurrentAccountType(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	getAnalytics(t, h, token)

	// Stepping down from admin takes the analytics away straight away.
	patchMe(t, h, token, map[string]interface{}{"personType": "volunteer", "staffCode": testStaffCode})
	if code := doRequest(t, h, http.MethodGet, "/api/analytics", token, nil).Code; code != http.StatusForbidden {
		t.Fatalf("a former admin must lose access, got %d", code)
	}
}

func TestAnalyticsCountsPeopleSharingAndActivity(t *testing.T) {
	h := newTestServer(t)
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	registerUser(t, h, map[string]interface{}{"name": "Vic", "personType": "volunteer", "staffCode": testStaffCode})
	sharing, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	registerUser(t, h, map[string]interface{}{"name": "Not Sharing"})

	if code := doRequest(t, h, http.MethodPost, "/api/consent", sharing, map[string]interface{}{"granted": true}).Code; code != http.StatusOK {
		t.Fatalf("consent: %d", code)
	}
	for i := 0; i < 3; i++ {
		rec := doRequest(t, h, http.MethodPost, "/api/locations", sharing, map[string]interface{}{"latitude": 32.08, "longitude": -81.09})
		if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
			t.Fatalf("location: %d %s", rec.Code, rec.Body.String())
		}
	}

	a := getAnalytics(t, h, admin)
	if a.People.Participants != 2 || a.People.Volunteers != 1 || a.People.Admins != 1 {
		t.Fatalf("unexpected people counts: %+v", a.People)
	}
	if a.Sharing.ParticipantsSharing != 1 {
		t.Fatalf("expected 1 participant sharing, got %d", a.Sharing.ParticipantsSharing)
	}
	if a.Sharing.ActiveLast24Hours != 1 || a.Sharing.ActiveLast7Days != 1 {
		t.Fatalf("one person checked in recently (three times): %+v", a.Sharing)
	}

	if len(a.Daily) != analyticsDays {
		t.Fatalf("expected %d days, got %d", analyticsDays, len(a.Daily))
	}
	today := a.Daily[len(a.Daily)-1]
	if today.Signups != 4 || today.CheckIns != 3 {
		t.Fatalf("today should show 4 sign-ups and 3 check-ins, got %+v", today)
	}
	for i := 1; i < len(a.Daily); i++ {
		if a.Daily[i-1].Date >= a.Daily[i].Date {
			t.Fatalf("days must run oldest to newest: %v", a.Daily)
		}
	}
}

func TestAnalyticsIsAggregateOnly(t *testing.T) {
	h := newTestServer(t)
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	registerUser(t, h, map[string]interface{}{"name": "Secret Person", "email": "secret@example.org"})

	rec := doRequest(t, h, http.MethodGet, "/api/analytics", admin, nil)
	body := rec.Body.String()
	for _, leak := range []string{"Secret Person", "secret@example.org", "latitude", "token"} {
		if strings.Contains(body, leak) {
			t.Fatalf("analytics must not contain %q: %s", leak, body)
		}
	}
}

func TestAnalyticsCountsDocuments(t *testing.T) {
	h := newTestServer(t)
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	full, _ := registerUser(t, h, map[string]interface{}{"name": "Has Everything"})
	partial, _ := registerUser(t, h, map[string]interface{}{"name": "Has One"})

	for _, token := range []string{full, partial} {
		if code := doRequest(t, h, http.MethodPost, "/api/consent/documents", token, map[string]interface{}{"granted": true}).Code; code != http.StatusOK {
			t.Fatalf("document consent: %d", code)
		}
	}
	for _, docType := range []string{"government_id", "social_security_card", "birth_certificate"} {
		uploadTestDocument(t, h, full, docType, "file for "+docType)
	}
	uploadTestDocument(t, h, partial, "government_id", "only an id")
	uploadTestDocument(t, h, partial, "other", "some other paper") // "other" does not count toward the three

	a := getAnalytics(t, h, admin)
	if a.Documents.ParticipantsUsingStorage != 2 || a.Documents.ParticipantsWithAllThree != 1 || a.Documents.DocumentsStored != 5 {
		t.Fatalf("unexpected document counts: %+v", a.Documents)
	}
}
