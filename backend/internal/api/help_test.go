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
	ada, _ := newAdmin(t, h)

	req := createHelp(t, h, jane, map[string]interface{}{"category": "food", "note": "Need to get to my appointment"})
	id := req["id"].(string)
	if req["status"] != "open" || req["note"] != "Need to get to my appointment" {
		t.Fatalf("unexpected new request: %v", req)
	}

	// The admin sees it, with who asked. The volunteer sees nothing yet.
	list := board(t, h, ada)
	if len(list) != 1 {
		t.Fatalf("expected 1 request on the admin's board, got %d", len(list))
	}
	first := asMap(t, list[0])
	if first["name"] != "Jane Doe" || first["category"] != "food" {
		t.Fatalf("unexpected board entry: %v", first)
	}
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("a volunteer should not see a request nobody has given them")
	}

	// The admin assigns it: Sam then sees it, and Jane sees Sam's first name.
	matchVolunteer(t, h, sam, id)
	if len(board(t, h, sam)) != 1 {
		t.Fatalf("an assigned request should be on the volunteer's list")
	}
	var mine map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/help-requests/mine", jane, nil), &mine)
	r0 := asMap(t, mine["requests"].([]interface{})[0])
	if r0["status"] != "claimed" || r0["helperName"] != "Sam" {
		t.Fatalf("participant should see Sam helping, got %v", r0)
	}

	// Sam can hand it back; it returns to the admin as open and leaves Sam's list.
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/release", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("release: expected 200, got %d", code)
	}
	if asMap(t, board(t, h, ada)[0])["status"] != "open" {
		t.Fatalf("a handed-back request should be open again for the admin")
	}
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("a handed-back request should leave the volunteer's list")
	}
	matchVolunteer(t, h, sam, id)
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("complete: expected 200, got %d", code)
	}
	if len(board(t, h, sam)) != 0 || len(board(t, h, ada)) != 0 {
		t.Fatalf("a finished request should leave every board")
	}
}

func TestVolunteersCannotTakeRequestsOnlyAnAdminAssignsThem(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusForbidden {
		t.Fatalf("a volunteer taking a request: expected 403, got %d", code)
	}
	matchVolunteer(t, h, sam, id)
	if len(board(t, h, pat)) != 0 {
		t.Fatalf("a request given to Sam must not show for Pat")
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/release", pat, nil).Code; code != http.StatusNotFound {
		t.Fatalf("someone else cannot release it: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", pat, nil).Code; code != http.StatusNotFound {
		t.Fatalf("someone else cannot complete it: expected 404, got %d", code)
	}
	// An admin can move it to Pat; Sam no longer has it.
	matchVolunteer(t, h, pat, id)
	if len(board(t, h, sam)) != 0 || len(board(t, h, pat)) != 1 {
		t.Fatalf("reassigning should move it from Sam to Pat")
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

	rideID := createHelp(t, h, jane, map[string]interface{}{"category": "ride", "appointmentId": asMap(t, a1["appointment"])["id"]})["id"].(string)
	matchVolunteer(t, h, sam, rideID)

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
	ada, _ := newAdmin(t, h)
	var a map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{"title": "Visit", "startsAt": "2026-10-10T14:00:00Z"}), &a)
	apptID := asMap(t, a["appointment"])["id"].(string)
	createHelp(t, h, jane, map[string]interface{}{"category": "documents", "appointmentId": apptID})

	doRequest(t, h, http.MethodDelete, "/api/appointments/"+apptID, jane, nil)
	entry := asMap(t, board(t, h, ada)[0])
	if entry["appointment"] != nil {
		t.Fatalf("a deleted appointment should disappear from the request, got %v", entry["appointment"])
	}
}

func TestClaimedRequestReturnsToTheAdminWhenTheVolunteerLeaves(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	matchVolunteer(t, h, sam, id)
	doRequest(t, h, http.MethodDelete, "/api/account", sam, nil)

	entry := asMap(t, board(t, h, ada)[0])
	if entry["status"] != "open" {
		t.Fatalf("a request whose volunteer left should be open again, got %v", entry["status"])
	}
	matchVolunteer(t, h, pat, id)
	if len(board(t, h, pat)) != 1 {
		t.Fatalf("should be assignable again")
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

// matchVolunteer has an admin assign a request to a volunteer: it is theirs
// straight away. People ask the admins, and the admins do the matching.
func matchVolunteer(t *testing.T, h http.Handler, volunteerToken, requestID string) {
	t.Helper()
	admin, _ := newAdmin(t, h)
	var me map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/me", volunteerToken, nil), &me)
	volID := asMap(t, me["user"])["id"].(string)
	rec := doRequest(t, h, http.MethodPost, "/api/admin/help-requests/"+requestID+"/assign", admin, map[string]interface{}{"volunteerId": volID})
	if rec.Code != http.StatusOK {
		t.Fatalf("assign: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

// assignTo has the given admin give a request to a volunteer, and says what the server answered.
func assignTo(t *testing.T, h http.Handler, adminToken string, volunteer map[string]interface{}, requestID string) int {
	t.Helper()
	return doRequest(t, h, http.MethodPost, "/api/admin/help-requests/"+requestID+"/assign", adminToken, map[string]interface{}{"volunteerId": idOf(volunteer)}).Code
}
