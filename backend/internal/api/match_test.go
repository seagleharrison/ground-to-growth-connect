package api

import (
	"net/http"
	"strings"
	"testing"
)

func matchedRide(t *testing.T, h http.Handler) (jane, sam, ada, id string) {
	t.Helper()
	jane, _ = registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ = registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ = newAdmin(t, h)
	appt := doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{"title": "DDS visit", "location": "DDS", "startsAt": "2026-12-01T15:00:00Z"})
	var a map[string]interface{}
	decodeJSON(t, appt, &a)
	id = createHelp(t, h, jane, map[string]interface{}{"category": "ride", "appointmentId": asMap(t, a["appointment"])["id"]})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	approveOffer(t, h, ada, id, "")
	return jane, sam, ada, id
}

func myRequest(t *testing.T, h http.Handler, token string) map[string]interface{} {
	t.Helper()
	var mine map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/help-requests/mine", token, nil), &mine)
	return asMap(t, mine["requests"].([]interface{})[0])
}

func progress(t *testing.T, h http.Handler, token, id, kind string, minutes interface{}) int {
	t.Helper()
	body := map[string]interface{}{"kind": kind}
	if minutes != nil {
		body["minutes"] = minutes
	}
	return doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/progress", token, body).Code
}

func TestARideNeedsAnAppointmentAndNotesStayShort(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	post := func(body map[string]interface{}) int {
		return doRequest(t, h, http.MethodPost, "/api/help-requests", jane, body).Code
	}
	if code := post(map[string]interface{}{"category": "ride"}); code != http.StatusBadRequest {
		t.Fatalf("a ride with no appointment: expected 400, got %d", code)
	}
	var a map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{"title": "DDS", "startsAt": "2026-12-01T15:00:00Z"}), &a)
	apptID := asMap(t, a["appointment"])["id"]
	if code := post(map[string]interface{}{"category": "ride", "appointmentId": apptID}); code != http.StatusCreated {
		t.Fatalf("a ride to an appointment: expected 201, got %d", code)
	}
	// Notes are capped at 140 characters, counted as people see them.
	if code := post(map[string]interface{}{"category": "food", "note": strings.Repeat("a", 140)}); code != http.StatusCreated {
		t.Fatalf("a 140 character note: expected 201, got %d", code)
	}
	if code := post(map[string]interface{}{"category": "food", "note": strings.Repeat("a", 141)}); code != http.StatusBadRequest {
		t.Fatalf("a 141 character note: expected 400, got %d", code)
	}
	if code := post(map[string]interface{}{"category": "food", "note": strings.Repeat("é", 140)}); code != http.StatusCreated {
		t.Fatalf("140 accented characters are 140 characters: expected 201, got %d", code)
	}
}

func TestOffersAreSeenByAdminsAndTheirOwnVolunteerOnly(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)

	adminView := asMap(t, board(t, h, ada)[0])
	if offers := adminView["offers"].([]interface{}); len(offers) != 1 || asMap(t, offers[0])["volunteerName"] != "Sam Helper" {
		t.Fatalf("an admin should see Sam's offer, got %v", adminView["offers"])
	}
	if asMap(t, board(t, h, sam)[0])["myOffer"] != "pending" {
		t.Fatalf("Sam should see his offer is waiting")
	}
	patView := asMap(t, board(t, h, pat)[0])
	if patView["myOffer"] != nil || patView["offers"] != nil {
		t.Fatalf("Pat must not see Sam's offer, got %v", patView)
	}
	if mine := myRequest(t, h, jane); mine["offers"] != nil || mine["myOffer"] != nil {
		t.Fatalf("the person must never see offers, got %v", mine)
	}

	// Sam can take it back before it's confirmed.
	offerID := asMap(t, adminView["offers"].([]interface{})[0])["id"].(string)
	if code := doRequest(t, h, http.MethodDelete, "/api/help-offers/"+offerID, pat, nil).Code; code != http.StatusNotFound {
		t.Fatalf("withdrawing someone else's offer: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodDelete, "/api/help-offers/"+offerID, sam, nil).Code; code != http.StatusOK {
		t.Fatalf("withdrawing his own offer: expected 200, got %d", code)
	}
	if asMap(t, board(t, h, ada)[0])["offers"] != nil {
		t.Fatalf("a withdrawn offer should disappear")
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+offerID+"/approve", ada, nil).Code; code != http.StatusConflict {
		t.Fatalf("approving a withdrawn offer: expected 409, got %d", code)
	}
}

func TestOnlyAdminsCanApproveOrDeclineAnOffer(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	offerID := asMap(t, asMap(t, board(t, h, ada)[0])["offers"].([]interface{})[0])["id"].(string)

	for _, who := range []string{sam, jane} {
		if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+offerID+"/approve", who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("approve by a non-admin: expected 403, got %d", code)
		}
		if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+offerID+"/decline", who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("decline by a non-admin: expected 403, got %d", code)
		}
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+offerID+"/decline", ada, nil).Code; code != http.StatusOK {
		t.Fatalf("decline: expected 200, got %d", code)
	}
	if asMap(t, board(t, h, sam)[0])["myOffer"] != nil || asMap(t, board(t, h, sam)[0])["status"] != "open" {
		t.Fatalf("a declined offer leaves the request open and the offer gone")
	}
	// Sam may offer again later.
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("offering again: expected 200, got %d", code)
	}
}

func TestAnApprovedMatchCannotBeMadeWithAPausedOrBlockedVolunteer(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	offerID := asMap(t, asMap(t, board(t, h, ada)[0])["offers"].([]interface{})[0])["id"].(string)

	// Paused after offering: the admin can't confirm.
	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/pause", ada, nil)
	if code := doRequest(t, h, http.MethodPost, "/api/help-offers/"+offerID+"/approve", ada, nil).Code; code != http.StatusConflict {
		t.Fatalf("approving a paused volunteer: expected 409, got %d", code)
	}
	_ = janeU
}

func TestProgressTapsTellThePersonWhereTheirHelperIsUpTo(t *testing.T) {
	h := newTestServer(t)
	jane, sam, _, id := matchedRide(t, h)

	if code := progress(t, h, sam, id, "on_my_way", nil); code != http.StatusOK {
		t.Fatalf("on my way: expected 200, got %d", code)
	}
	if mine := myRequest(t, h, jane); mine["progress"] != "on_my_way" || mine["helperName"] != "Sam" {
		t.Fatalf("Jane should see Sam on the way, got %v", mine)
	}
	if code := progress(t, h, sam, id, "running_late", float64(20)); code != http.StatusOK {
		t.Fatalf("running late: expected 200, got %d", code)
	}
	if mine := myRequest(t, h, jane); mine["progress"] != "late" || mine["progressMinutes"] != float64(20) {
		t.Fatalf("Jane should see a 20 minute delay, got %v", mine)
	}
	if code := progress(t, h, sam, id, "running_late", float64(7)); code != http.StatusBadRequest {
		t.Fatalf("an odd delay: expected 400, got %d", code)
	}
	if code := progress(t, h, sam, id, "arrived", nil); code != http.StatusOK {
		t.Fatalf("arrived: expected 200, got %d", code)
	}
	if mine := myRequest(t, h, jane); mine["progress"] != "arrived" || mine["progressMinutes"] != nil {
		t.Fatalf("Jane should see Sam has arrived, got %v", mine)
	}
	if code := progress(t, h, sam, id, "teleported", nil); code != http.StatusBadRequest {
		t.Fatalf("an unknown tap: expected 400, got %d", code)
	}
}

func TestOnlyTheMatchedVolunteerCanSendProgress(t *testing.T) {
	h := newTestServer(t)
	jane, _, _, id := matchedRide(t, h)
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	stranger, _ := registerUser(t, h, map[string]interface{}{"name": "Stranger"})

	if code := progress(t, h, jane, id, "on_my_way", nil); code != http.StatusForbidden {
		t.Fatalf("the person sending the volunteer's tap: expected 403, got %d", code)
	}
	if code := progress(t, h, pat, id, "on_my_way", nil); code != http.StatusNotFound {
		t.Fatalf("an unmatched volunteer: expected 404, got %d", code)
	}
	if code := progress(t, h, stranger, id, "unsafe", nil); code != http.StatusNotFound {
		t.Fatalf("a stranger: expected 404, got %d", code)
	}
}

func TestCantMakeItPutsTheRequestBackForOtherVolunteers(t *testing.T) {
	h := newTestServer(t)
	jane, sam, ada, id := matchedRide(t, h)
	progress(t, h, sam, id, "on_my_way", nil)
	if code := progress(t, h, sam, id, "cant_make_it", nil); code != http.StatusOK {
		t.Fatalf("can't make it: expected 200, got %d", code)
	}
	mine := myRequest(t, h, jane)
	if mine["status"] != "open" || mine["helperName"] != nil || mine["progress"] != nil {
		t.Fatalf("the request should be open again with no helper or progress, got %v", mine)
	}
	if asMap(t, board(t, h, ada)[0])["status"] != "open" {
		t.Fatalf("the board should show it open")
	}
	if code := progress(t, h, sam, id, "on_my_way", nil); code != http.StatusNotFound {
		t.Fatalf("Sam is no longer on it: expected 404, got %d", code)
	}
}

func TestThePersonPressingIDontFeelSafeEndsTheMatchBlocksAndAlertsAdmins(t *testing.T) {
	h, f := pushServer(t)
	jane, sam, ada, id := func() (string, string, string, string) {
		return matchedRide(t, h)
	}()
	registerToken(t, h, ada, tok("d"))
	f.reset()

	if code := progress(t, h, jane, id, "unsafe", nil); code != http.StatusOK {
		t.Fatalf("unsafe: expected 200, got %d", code)
	}
	mine := myRequest(t, h, jane)
	if mine["status"] != "open" || mine["helperName"] != nil {
		t.Fatalf("the match should end, got %v", mine)
	}
	// Sam can no longer see or take it.
	for _, r := range board(t, h, sam) {
		if asMap(t, r)["id"] == id {
			t.Fatalf("a volunteer someone felt unsafe with must not see the request again")
		}
	}
	var reports map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/reports", ada, nil), &reports)
	list := reports["reports"].([]interface{})
	if len(list) != 1 || !strings.Contains(asMap(t, list[0])["reason"].(string), "Safety alert") {
		t.Fatalf("admins should find a safety alert in the reports, got %v", list)
	}
	got := f.to(tok("d"))
	if len(got) != 1 || got[0].n.Title != "Safety alert" || strings.Contains(got[0].n.Body, "Jane") || strings.Contains(got[0].n.Body, "Sam") {
		t.Fatalf("every admin gets one generic alert, got %v", got)
	}
}

func TestAVolunteerPressingIDontFeelSafeEndsTheMatchToo(t *testing.T) {
	h := newTestServer(t)
	jane, sam, ada, id := matchedRide(t, h)
	if code := progress(t, h, sam, id, "unsafe", nil); code != http.StatusOK {
		t.Fatalf("unsafe: expected 200, got %d", code)
	}
	if mine := myRequest(t, h, jane); mine["status"] != "open" {
		t.Fatalf("the match should end, got %v", mine)
	}
	var reports map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/reports", ada, nil), &reports)
	if len(reports["reports"].([]interface{})) != 1 {
		t.Fatalf("admins should see the alert")
	}
}

func TestOnlyThePersonHelpedCanRateAndOnlyAdminsSeeIt(t *testing.T) {
	h := newTestServer(t)
	jane, sam, ada, id := matchedRide(t, h)
	rate := func(token string, value int) int {
		return doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/rating", token, map[string]interface{}{"value": value}).Code
	}
	if code := rate(jane, 1); code != http.StatusConflict {
		t.Fatalf("rating before it's done: expected 409, got %d", code)
	}
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil)
	if code := rate(jane, 5); code != http.StatusBadRequest {
		t.Fatalf("rating of 5: expected 400, got %d", code)
	}
	if code := rate(sam, 1); code != http.StatusNotFound {
		t.Fatalf("the volunteer rating their own help: expected 404, got %d", code)
	}
	if code := rate(jane, 1); code != http.StatusOK {
		t.Fatalf("rating: expected 200, got %d", code)
	}
	if myRequest(t, h, jane)["rating"] != float64(1) {
		t.Fatalf("Jane should see her own rating")
	}

	// The volunteer never sees it; the admin sees it by volunteer and in the history.
	var vols map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/volunteers", ada, nil), &vols)
	found := false
	for _, v := range vols["volunteers"].([]interface{}) {
		if asMap(t, v)["name"] == "Sam Helper" {
			found = asMap(t, v)["thumbsUp"] == float64(1) && asMap(t, v)["thumbsDown"] == float64(0)
		}
	}
	if !found {
		t.Fatalf("the admin should see Sam's thumbs up: %v", vols)
	}
	var history map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/help-history", ada, nil), &history)
	entries := history["history"].([]interface{})
	if len(entries) != 1 || asMap(t, entries[0])["rating"] != float64(1) || asMap(t, entries[0])["helper"] != "Sam Helper" {
		t.Fatalf("history should show the rated match, got %v", entries)
	}
	for _, who := range []string{sam, jane} {
		if code := doRequest(t, h, http.MethodGet, "/api/admin/help-history", who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("history for a non-admin: expected 403, got %d", code)
		}
	}
	if strings.Contains(doRequest(t, h, http.MethodGet, "/api/help-requests", sam, nil).Body.String(), "\"rating\":1") {
		t.Fatalf("a volunteer must never see a rating")
	}
}

func TestMatchingAndProgressSendOnlyGenericAlerts(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	registerToken(t, h, jane, tok("a"))
	registerToken(t, h, sam, tok("b"))
	registerToken(t, h, ada, tok("c"))
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	f.reset()

	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	if got := f.to(tok("c")); len(got) != 1 || got[0].n.Title != "A volunteer offered to help" {
		t.Fatalf("the admin should hear about the offer, got %v", got)
	}
	if len(f.to(tok("a"))) != 0 {
		t.Fatalf("the person must not be told about an offer nobody confirmed")
	}
	approveOffer(t, h, ada, id, "")
	if got := f.to(tok("a")); len(got) != 1 || got[0].n.Title != "Help is on the way" {
		t.Fatalf("the person is told once it is confirmed, got %v", got)
	}
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Title != "You're matched" {
		t.Fatalf("the volunteer is told they're matched, got %v", got)
	}
	progress(t, h, sam, id, "on_my_way", nil)
	got := f.to(tok("a"))
	last := got[len(got)-1].n
	if last.Body != "Your volunteer is on the way." || strings.Contains(last.Body, "Sam") {
		t.Fatalf("progress alerts name nobody, got %v", last)
	}
}
