package api

import (
	"net/http"
	"strings"
	"testing"
)

func asMap(t *testing.T, v interface{}) map[string]interface{} {
	t.Helper()
	m, ok := v.(map[string]interface{})
	if !ok {
		t.Fatalf("expected an object, got %v", v)
	}
	return m
}

func createHelp(t *testing.T, h http.Handler, token string, body map[string]interface{}) map[string]interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodPost, "/api/help-requests", token, body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create help request: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return asMap(t, out["request"])
}

func board(t *testing.T, h http.Handler, token string) []interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodGet, "/api/help-requests", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("board: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return out["requests"].([]interface{})
}

func TestHelpRequestLifecycleAcrossParticipantAndVolunteer(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})

	req := createHelp(t, h, jane, map[string]interface{}{"category": "food", "note": "Need to get to my appointment"})
	id := req["id"].(string)
	if req["status"] != "open" || req["note"] != "Need to get to my appointment" {
		t.Fatalf("unexpected new request: %v", req)
	}

	// Volunteer sees it, with who asked.
	list := board(t, h, sam)
	if len(list) != 1 {
		t.Fatalf("expected 1 request on the board, got %d", len(list))
	}
	first := asMap(t, list[0])
	if first["name"] != "Jane Doe" || first["category"] != "food" {
		t.Fatalf("unexpected board entry: %v", first)
	}

	// "I can help" is only an offer: Jane isn't told anyone is coming until an admin confirms.
	rec := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("offer: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var offered map[string]interface{}
	decodeJSON(t, rec, &offered)
	if asMap(t, offered["request"])["myOffer"] != "pending" || asMap(t, offered["request"])["status"] != "open" {
		t.Fatalf("the offer should wait for an admin, got %v", offered)
	}
	var waiting map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/help-requests/mine", jane, nil), &waiting)
	if w0 := asMap(t, waiting["requests"].([]interface{})[0]); w0["status"] != "open" || w0["helperName"] != nil {
		t.Fatalf("Jane must not see a helper before an admin confirms, got %v", w0)
	}
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})
	approveOffer(t, h, admin, id, "")

	// Confirmed: Jane then sees Sam's first name.
	var mine map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/help-requests/mine", jane, nil), &mine)
	r0 := asMap(t, mine["requests"].([]interface{})[0])
	if r0["status"] != "claimed" || r0["helperName"] != "Sam" {
		t.Fatalf("participant should see Sam helping, got %v", r0)
	}

	// Release puts it back; complete closes it and takes it off the board.
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/release", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("release: expected 200, got %d", code)
	}
	if asMap(t, board(t, h, sam)[0])["status"] != "open" {
		t.Fatalf("released request should be open again")
	}
	matchVolunteer(t, h, sam, id)
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("complete: expected 200, got %d", code)
	}
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("a finished request should leave the board")
	}
}

func TestOnlyOneVolunteerCanClaimAtATime(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})
	// Both can offer; the admin picks one.
	for _, v := range []string{sam, pat} {
		if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", v, nil).Code; code != http.StatusOK {
			t.Fatalf("offer: expected 200, got %d", code)
		}
	}
	patOffer := ""
	for _, o := range asMap(t, board(t, h, ada)[0])["offers"].([]interface{}) {
		if asMap(t, o)["volunteerName"] == "Pat" {
			patOffer = asMap(t, o)["id"].(string)
		}
	}
	approveOffer(t, h, ada, id, "Sam")
	if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+patOffer+"/approve", ada, nil).Code; code != http.StatusConflict {
		t.Fatalf("approving the other offer after Sam was matched: expected 409, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", pat, nil).Code; code != http.StatusConflict {
		t.Fatalf("offering once someone is matched: expected 409, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/release", pat, nil).Code; code != http.StatusNotFound {
		t.Fatalf("someone else cannot release it: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", pat, nil).Code; code != http.StatusNotFound {
		t.Fatalf("someone else cannot complete it: expected 404, got %d", code)
	}
}

func TestParticipantsCannotSeeTheBoardOrClaim(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	other, _ := registerUser(t, h, map[string]interface{}{"name": "Other"})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	if code := doRequest(t, h, http.MethodGet, "/api/help-requests", other, nil).Code; code != http.StatusForbidden {
		t.Fatalf("board for a participant: expected 403, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", other, nil).Code; code != http.StatusForbidden {
		t.Fatalf("claim as participant: expected 403, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", other, nil).Code; code != http.StatusNotFound {
		t.Fatalf("another participant closing it: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodDelete, "/api/help-requests/"+id, other, nil).Code; code != http.StatusNotFound {
		t.Fatalf("another participant deleting it: expected 404, got %d", code)
	}
}

func TestHelpRequestValidation(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	if code := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, map[string]interface{}{"category": "pizza"}).Code; code != http.StatusBadRequest {
		t.Fatalf("bad category: expected 400, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, map[string]interface{}{"category": "ride", "appointmentId": "nope"}).Code; code != http.StatusBadRequest {
		t.Fatalf("someone else's/unknown appointment: expected 400, got %d", code)
	}
	for i := 0; i < maxActiveHelpPerUser; i++ {
		createHelp(t, h, jane, map[string]interface{}{"category": "other"})
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, map[string]interface{}{"category": "other"}).Code; code != http.StatusConflict {
		t.Fatalf("too many open requests: expected 409, got %d", code)
	}
}

func TestAttachedAppointmentIsTheOnlyCalendarThingStaffSee(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})

	var a1, a2 map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{
		"title": "DDS ID visit", "notes": "private note", "location": "DDS Savannah", "startsAt": "2026-10-10T14:00:00Z",
	}), &a1)
	decodeJSON(t, doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{
		"title": "Therapy", "startsAt": "2026-10-11T14:00:00Z",
	}), &a2)

	createHelp(t, h, jane, map[string]interface{}{"category": "ride", "appointmentId": asMap(t, a1["appointment"])["id"]})

	entry := asMap(t, board(t, h, sam)[0])
	appt := asMap(t, entry["appointment"])
	if appt["title"] != "DDS ID visit" || appt["location"] != "DDS Savannah" {
		t.Fatalf("volunteer should see the attached appointment, got %v", appt)
	}
	if _, leaked := appt["notes"]; leaked {
		t.Fatalf("appointment notes must never reach staff")
	}
	// Therapy was never attached, so it is nowhere in what staff can fetch.
	rec := doRequest(t, h, http.MethodGet, "/api/help-requests", sam, nil)
	if strings.Contains(rec.Body.String(), "Therapy") {
		t.Fatalf("unattached appointment leaked")
	}
}

func TestDeletingAnAttachedAppointmentKeepsTheRequest(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	var a map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{"title": "Visit", "startsAt": "2026-10-10T14:00:00Z"}), &a)
	apptID := asMap(t, a["appointment"])["id"].(string)
	createHelp(t, h, jane, map[string]interface{}{"category": "ride", "appointmentId": apptID})

	doRequest(t, h, http.MethodDelete, "/api/appointments/"+apptID, jane, nil)
	entry := asMap(t, board(t, h, sam)[0])
	if entry["appointment"] != nil {
		t.Fatalf("a deleted appointment should disappear from the request, got %v", entry["appointment"])
	}
}

func TestClaimedRequestReturnsToBoardWhenTheVolunteerLeaves(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	matchVolunteer(t, h, sam, id)
	doRequest(t, h, http.MethodDelete, "/api/account", sam, nil)

	entry := asMap(t, board(t, h, pat)[0])
	if entry["status"] != "open" {
		t.Fatalf("a request whose volunteer left should be open again, got %v", entry["status"])
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", pat, nil).Code; code != http.StatusOK {
		t.Fatalf("should be claimable again, got %d", code)
	}
}

func TestParticipantCanCloseAndRemoveTheirOwnRequest(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	rec := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", jane, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("participant complete: expected 200, got %d", rec.Code)
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	if asMap(t, out["request"])["status"] != "done" {
		t.Fatalf("expected done, got %v", out)
	}
	if code := doRequest(t, h, http.MethodDelete, "/api/help-requests/"+id, jane, nil).Code; code != http.StatusOK {
		t.Fatalf("delete: expected 200, got %d", code)
	}
}

func TestAdminCanFreeAStuckRequest(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	matchVolunteer(t, h, sam, id)
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/release", ada, nil).Code; code != http.StatusOK {
		t.Fatalf("admin release: expected 200, got %d", code)
	}
}

// matchVolunteer is what "I can help" takes now: the volunteer offers, then an
// admin confirms. It leaves the request claimed by that volunteer.
func matchVolunteer(t *testing.T, h http.Handler, volunteerToken, requestID string) {
	t.Helper()
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+requestID+"/claim", volunteerToken, nil).Code; code != http.StatusOK {
		t.Fatalf("offer: expected 200, got %d", code)
	}
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Match Admin", "personType": "admin", "staffCode": testStaffCode})
	approveOffer(t, h, admin, requestID, "")
}

// approveOffer approves the pending offer on a request (the one from volunteerName
// when given, otherwise the first) and returns the offer's id.
func approveOffer(t *testing.T, h http.Handler, adminToken, requestID, volunteerName string) string {
	t.Helper()
	for _, r := range board(t, h, adminToken) {
		req := asMap(t, r)
		if req["id"] != requestID {
			continue
		}
		offers, _ := req["offers"].([]interface{})
		for _, o := range offers {
			offer := asMap(t, o)
			if volunteerName != "" && offer["volunteerName"] != volunteerName {
				continue
			}
			id := offer["id"].(string)
			if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+id+"/approve", adminToken, nil).Code; code != http.StatusOK {
				t.Fatalf("approve: expected 200, got %d", code)
			}
			return id
		}
	}
	t.Fatalf("no pending offer found on %s", requestID)
	return ""
}
