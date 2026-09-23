package api

import (
	"net/http"
	"testing"
)

func TestHealthEndpoint(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodGet, "/health", "", nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var body map[string]string
	decodeJSON(t, rec, &body)
	if body["status"] != "ok" {
		t.Fatalf("expected status ok, got %v", body)
	}
}

func TestNotFoundRouteReturnsJSON(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodGet, "/api/nope", "", nil)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
	var body map[string]string
	decodeJSON(t, rec, &body)
	if body["error"] == "" {
		t.Fatalf("expected an error message, got %v", body)
	}
}

func TestRegisterCreatesParticipantByDefault(t *testing.T) {
	h := newTestServer(t)
	token, user := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	if token == "" {
		t.Fatal("expected non-empty token")
	}
	if user["personType"] != "homeless" {
		t.Fatalf("expected default personType 'homeless', got %v", user["personType"])
	}
	if user["isStaff"] != false {
		t.Fatalf("expected isStaff false, got %v", user["isStaff"])
	}
	if user["name"] != "Jane Doe" {
		t.Fatalf("expected name to round-trip, got %v", user["name"])
	}
}

func TestRegisterRequiresName(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{"name": "   ", "phone": "912-555-0100"})

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for blank name, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRegisterRequiresPhone(t *testing.T) {
	h := newTestServer(t)
	for name, phone := range map[string]interface{}{"missing": nil, "blank": "   "} {
		body := map[string]interface{}{"name": "Someone"}
		if phone != nil {
			body["phone"] = phone
		}
		rec := doRequest(t, h, http.MethodPost, "/api/users", "", body)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s phone: expected 400, got %d: %s", name, rec.Code, rec.Body.String())
		}
	}
}

func TestRegisterRejectsInvalidPersonType(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Someone", "phone": "912-555-0100", "personType": "wizard",
	})

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid personType, got %d", rec.Code)
	}
}

func TestRegisterRejectsInvalidGender(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Someone", "phone": "912-555-0100", "gender": "not-a-real-option",
	})

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid gender, got %d", rec.Code)
	}
}

func TestRegisterStaffWithoutCodeRejected(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Outreach Sam", "phone": "912-555-0100", "personType": "volunteer",
	})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without staff code, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRegisterStaffWithWrongCodeRejected(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodPost, "/api/users", "", map[string]interface{}{
		"name": "Outreach Sam", "phone": "912-555-0100", "personType": "volunteer", "staffCode": "wrong-code",
	})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 with wrong staff code, got %d", rec.Code)
	}
}

func TestRegisterStaffWithCorrectCodeSucceeds(t *testing.T) {
	h := newTestServer(t)
	_, user := registerUser(t, h, map[string]interface{}{
		"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode,
	})

	if user["isStaff"] != true {
		t.Fatalf("expected isStaff true for volunteer, got %v", user["isStaff"])
	}
}

func TestMeRequiresAuth(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodGet, "/api/me", "", nil)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 with no token, got %d", rec.Code)
	}
}

func TestMeRejectsInvalidToken(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodGet, "/api/me", "not-a-real-token", nil)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 with invalid token, got %d", rec.Code)
	}
}

func TestMeReturnsRegisteredProfile(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe", "email": "jane@example.org"})

	rec := doRequest(t, h, http.MethodGet, "/api/me", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	user, _ := body["user"].(map[string]interface{})
	if user["email"] != "jane@example.org" {
		t.Fatalf("expected email to round-trip, got %v", user["email"])
	}
}

func TestDeleteAccountRemovesUser(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodDelete, "/api/account", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	// The same token must no longer authenticate.
	rec = doRequest(t, h, http.MethodGet, "/api/me", token, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 after account deletion, got %d", rec.Code)
	}
}

func TestConsentDisclosureIsPublic(t *testing.T) {
	h := newTestServer(t)
	rec := doRequest(t, h, http.MethodGet, "/api/consent/disclosure", "", nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 without auth, got %d", rec.Code)
	}
	var body map[string]string
	decodeJSON(t, rec, &body)
	if body["text"] == "" || body["version"] == "" {
		t.Fatalf("expected disclosure text and version, got %v", body)
	}
}

func TestConsentStatusDefaultsToNotGranted(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodGet, "/api/consent/status", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	if body["granted"] != false {
		t.Fatalf("expected granted false before any consent record, got %v", body)
	}
}

func TestConsentGrantThenRevoke(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("grant: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var granted map[string]interface{}
	decodeJSON(t, rec, &granted)
	record, _ := granted["record"].(map[string]interface{})
	if record["granted"] != true {
		t.Fatalf("expected granted true in record, got %v", record)
	}
	if record["granted_at"] == nil {
		t.Fatal("expected granted_at to be set")
	}

	rec = doRequest(t, h, http.MethodGet, "/api/consent/status", token, nil)
	var status map[string]interface{}
	decodeJSON(t, rec, &status)
	if status["granted"] != true {
		t.Fatalf("expected status granted true, got %v", status)
	}

	rec = doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": false})
	if rec.Code != http.StatusOK {
		t.Fatalf("revoke: expected 200, got %d", rec.Code)
	}

	rec = doRequest(t, h, http.MethodGet, "/api/consent/status", token, nil)
	decodeJSON(t, rec, &status)
	if status["granted"] != false {
		t.Fatalf("expected status granted false after revoke, got %v", status)
	}
}

func TestConsentRequiresBooleanGranted(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": "yes"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for non-boolean granted, got %d", rec.Code)
	}
}

func TestConsentHistoryAccumulates(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": true})
	doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": false})

	rec := doRequest(t, h, http.MethodGet, "/api/consent/history", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	records, _ := body["records"].([]interface{})
	if len(records) != 2 {
		t.Fatalf("expected 2 history records, got %d: %v", len(records), records)
	}
}

func TestLocationRequiresConsent(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodPost, "/api/locations", token, map[string]interface{}{
		"latitude": 32.0809, "longitude": -81.0912,
	})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 without consent, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLocationRejectsInvalidCoordinates(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": true})

	rec := doRequest(t, h, http.MethodPost, "/api/locations", token, map[string]interface{}{
		"latitude": 999.0, "longitude": -81.0912,
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for out-of-range latitude, got %d", rec.Code)
	}
}

func TestLocationSubmitAndRetrieveMine(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent", token, map[string]interface{}{"granted": true})

	rec := doRequest(t, h, http.MethodPost, "/api/locations", token, map[string]interface{}{
		"latitude": 32.0809, "longitude": -81.0912, "accuracyMeters": 12.5,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	rec = doRequest(t, h, http.MethodGet, "/api/locations/mine", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	reports, _ := body["reports"].([]interface{})
	if len(reports) != 1 {
		t.Fatalf("expected 1 report, got %d", len(reports))
	}
	report := reports[0].(map[string]interface{})

	lat, _ := report["latitude"].(float64)
	if lat < 32.0 || lat > 32.2 {
		t.Fatalf("decrypted latitude out of expected range: %v", lat)
	}
	// Coordinates should be coarsened, not stored exactly as submitted.
	if lat == 32.0809 {
		t.Fatal("expected latitude to be snapped to the privacy grid, got the exact submitted value")
	}
}

func TestNonStaffCannotSeeLatestLocations(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodGet, "/api/locations/latest", token, nil)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-staff, got %d", rec.Code)
	}
}

func TestStaffSeesLatestConsentedLocation(t *testing.T) {
	h := newTestServer(t)

	participantToken, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	doRequest(t, h, http.MethodPost, "/api/consent", participantToken, map[string]interface{}{"granted": true})
	rec := doRequest(t, h, http.MethodPost, "/api/locations", participantToken, map[string]interface{}{
		"latitude": 32.0809, "longitude": -81.0912,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("submitting location: expected 201, got %d", rec.Code)
	}

	staffToken, _ := registerUser(t, h, map[string]interface{}{
		"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode,
	})

	rec = doRequest(t, h, http.MethodGet, "/api/locations/latest", staffToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	locations, _ := body["locations"].([]interface{})
	if len(locations) != 1 {
		t.Fatalf("expected 1 visible location, got %d", len(locations))
	}
	loc := locations[0].(map[string]interface{})
	if loc["name"] != "Jane Doe" {
		t.Fatalf("expected participant name to decrypt correctly, got %v", loc["name"])
	}
}

func TestStaffDoesNotSeeLocationWithoutConsent(t *testing.T) {
	h := newTestServer(t)

	// Register a participant but never grant consent, and never submit a
	// location (submitting one is blocked without consent anyway) — the
	// staff view must come back empty.
	registerUser(t, h, map[string]interface{}{"name": "No Consent Person"})

	staffToken, _ := registerUser(t, h, map[string]interface{}{
		"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode,
	})

	rec := doRequest(t, h, http.MethodGet, "/api/locations/latest", staffToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	locations, _ := body["locations"].([]interface{})
	if len(locations) != 0 {
		t.Fatalf("expected no visible locations, got %d", len(locations))
	}
}

func TestStaffCanShareAndOtherStaffSeeThem(t *testing.T) {
	h := newTestServer(t)

	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode})
	if code := doRequest(t, h, http.MethodPost, "/api/consent", sam, map[string]interface{}{"granted": true}).Code; code != http.StatusOK {
		t.Fatalf("staff granting location consent: expected 200, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/locations", sam, map[string]interface{}{"latitude": 32.08, "longitude": -81.09}).Code; code != http.StatusCreated {
		t.Fatalf("staff submitting a location: expected 201, got %d", code)
	}

	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})
	rec := doRequest(t, h, http.MethodGet, "/api/locations/latest", ada, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	locations, _ := body["locations"].([]interface{})
	if len(locations) != 1 {
		t.Fatalf("expected to see the sharing volunteer, got %d", len(locations))
	}
	loc := locations[0].(map[string]interface{})
	if loc["name"] != "Outreach Sam" || loc["personType"] != "volunteer" {
		t.Fatalf("expected Outreach Sam the volunteer, got %v", loc)
	}
}

func TestSharingStaffNeverSeeThemselvesInTheList(t *testing.T) {
	h := newTestServer(t)

	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode})
	doRequest(t, h, http.MethodPost, "/api/consent", sam, map[string]interface{}{"granted": true})
	doRequest(t, h, http.MethodPost, "/api/locations", sam, map[string]interface{}{"latitude": 32.08, "longitude": -81.09})

	rec := doRequest(t, h, http.MethodGet, "/api/locations/latest", sam, nil)
	var body map[string]interface{}
	decodeJSON(t, rec, &body)
	locations, _ := body["locations"].([]interface{})
	if len(locations) != 0 {
		t.Fatalf("a sharing staff member must not see their own pin, got %d", len(locations))
	}
}

func TestParticipantsCannotBeReachedByStaffLocationSharing(t *testing.T) {
	// Participants can never call /api/locations/latest at all (withStaff),
	// so a participant granting consent can never see staff pins either way —
	// this just pins down that staff sharing doesn't change who can call it.
	h := newTestServer(t)
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Outreach Sam", "personType": "volunteer", "staffCode": testStaffCode})
	doRequest(t, h, http.MethodPost, "/api/consent", sam, map[string]interface{}{"granted": true})
	doRequest(t, h, http.MethodPost, "/api/locations", sam, map[string]interface{}{"latitude": 32.08, "longitude": -81.09})

	participant, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	if code := doRequest(t, h, http.MethodGet, "/api/locations/latest", participant, nil).Code; code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", code)
	}
}
