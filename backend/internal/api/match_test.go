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

func TestAcceptingAndProgressSendOnlyGenericAlerts(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("a"))
	registerToken(t, h, sam, tok("b"))
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	f.reset()

	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	if got := f.to(tok("a")); len(got) != 1 || got[0].n.Title != "Help is on the way" || strings.Contains(got[0].n.Body, "Sam") {
		t.Fatalf("the person is told once it's accepted, without a name, got %v", got)
	}
	progress(t, h, sam, id, "on_my_way", nil)
	got := f.to(tok("a"))
	last := got[len(got)-1].n
	if last.Body != "Your volunteer is on the way." || strings.Contains(last.Body, "Sam") {
		t.Fatalf("progress alerts name nobody, got %v", last)
	}
}

func postAppt(t *testing.T, h http.Handler, token string, body map[string]interface{}) (int, map[string]interface{}) {
	t.Helper()
	rec := doRequest(t, h, http.MethodPost, "/api/appointments", token, body)
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return rec.Code, out
}

func ridesOnBoard(t *testing.T, h http.Handler, token string) []map[string]interface{} {
	t.Helper()
	var out []map[string]interface{}
	for _, r := range board(t, h, token) {
		if m := asMap(t, r); m["category"] == "ride" {
			out = append(out, m)
		}
	}
	return out
}

func TestMarkingAnAppointmentAsNeedingARideShowsItToVolunteersAndAdmins(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	registerToken(t, h, sam, tok("b"))
	f.reset()

	code, out := postAppt(t, h, jane, map[string]interface{}{"title": "DDS visit", "location": "DDS, Eisenhower Dr", "startsAt": "2026-12-03T15:00:00Z", "needsRide": true})
	appt := asMap(t, out["appointment"])
	if code != http.StatusCreated || appt["needsRide"] != true {
		t.Fatalf("an appointment that needs a ride: got %d %v", code, appt)
	}
	for name, token := range map[string]string{"volunteer": sam, "admin": ada} {
		rides := ridesOnBoard(t, h, token)
		if len(rides) != 1 {
			t.Fatalf("the %s should see the ride, got %v", name, rides)
		}
		a := asMap(t, rides[0]["appointment"])
		if rides[0]["name"] != "Jane Doe" || a["title"] != "DDS visit" || a["location"] != "DDS, Eisenhower Dr" {
			t.Fatalf("the %s should see who, what and where, got %v", name, rides[0])
		}
	}
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Body != "Someone needs a ride. Open the Help tab to see." {
		t.Fatalf("volunteers get one generic alert, got %v", got)
	}

	// It's on their list of appointments as needing a ride.
	var list map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", jane, nil), &list)
	if asMap(t, list["appointments"].([]interface{})[0])["needsRide"] != true {
		t.Fatalf("the appointment should say it needs a ride")
	}
}

func TestAnAppointmentWithoutARideIsNeverOnTheBoard(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	postAppt(t, h, jane, map[string]interface{}{"title": "Private thing", "startsAt": "2026-12-03T15:00:00Z"})
	if got := board(t, h, sam); len(got) != 0 {
		t.Fatalf("an appointment nobody needs a ride to stays private, got %v", got)
	}
}

func TestTurningTheRideOnAndOffLater(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	_, out := postAppt(t, h, jane, map[string]interface{}{"title": "DDS visit", "startsAt": "2026-12-03T15:00:00Z"})
	id := asMap(t, out["appointment"])["id"].(string)

	patch := func(body map[string]interface{}) (int, map[string]interface{}) {
		rec := doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, jane, body)
		var o map[string]interface{}
		decodeJSON(t, rec, &o)
		return rec.Code, o
	}
	if code, o := patch(map[string]interface{}{"needsRide": true}); code != http.StatusOK || asMap(t, o["appointment"])["needsRide"] != true {
		t.Fatalf("turning the ride on: got %d %v", code, o)
	}
	// Saving again with it still on doesn't make a second request.
	patch(map[string]interface{}{"needsRide": true})
	patch(map[string]interface{}{"title": "DDS visit (moved)"})
	if rides := ridesOnBoard(t, h, sam); len(rides) != 1 {
		t.Fatalf("one ride, however many times it's saved, got %d", len(rides))
	}
	if code, o := patch(map[string]interface{}{"needsRide": false}); code != http.StatusOK || asMap(t, o["appointment"])["needsRide"] != false {
		t.Fatalf("turning the ride off: got %d %v", code, o)
	}
	if rides := ridesOnBoard(t, h, sam); len(rides) != 0 {
		t.Fatalf("turning it off removes the ride from the board, got %v", rides)
	}
}

func TestChangingOrCancellingARideTellsTheVolunteerWhoAccepted(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, sam, tok("b"))
	_, out := postAppt(t, h, jane, map[string]interface{}{"title": "DDS visit", "startsAt": "2026-12-03T15:00:00Z", "needsRide": true})
	id := asMap(t, out["appointment"])["id"].(string)
	rideID := ridesOnBoard(t, h, sam)[0]["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+rideID+"/claim", sam, nil)
	f.reset()

	// A new time: Sam is told, with no names or times in the alert.
	doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, jane, map[string]interface{}{"startsAt": "2026-12-03T17:00:00Z"})
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Title != "The time of a ride changed" {
		t.Fatalf("Sam should hear the time changed, got %v", got)
	}
	f.reset()

	// Deleting the appointment cancels the ride and tells Sam.
	if code := doRequest(t, h, http.MethodDelete, "/api/appointments/"+id, jane, nil).Code; code != http.StatusOK {
		t.Fatalf("delete: expected 200, got %d", code)
	}
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Title != "A ride was cancelled" {
		t.Fatalf("Sam should hear it was cancelled, got %v", got)
	}
	if rides := ridesOnBoard(t, h, sam); len(rides) != 0 {
		t.Fatalf("a cancelled ride leaves the board, got %v", rides)
	}
}

func TestAnAllDayAppointmentCannotNeedARide(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	if code, _ := postAppt(t, h, jane, map[string]interface{}{"title": "Court", "startsAt": "2026-12-03T05:00:00Z", "allDay": true, "needsRide": true}); code != http.StatusBadRequest {
		t.Fatalf("an all-day ride: expected 400, got %d", code)
	}
	var list map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", jane, nil), &list)
	if len(list["appointments"].([]interface{})) != 0 {
		t.Fatalf("a refused appointment must not be left behind, got %v", list)
	}
	// Making an existing ride appointment all-day cancels the ride rather than leaving it stranded.
	_, out := postAppt(t, h, jane, map[string]interface{}{"title": "DDS", "startsAt": "2026-12-03T15:00:00Z", "needsRide": true})
	id := asMap(t, out["appointment"])["id"].(string)
	doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, jane, map[string]interface{}{"allDay": true})
	var after map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", jane, nil), &after)
	if asMap(t, after["appointments"].([]interface{})[0])["needsRide"] != false {
		t.Fatalf("an all-day appointment has no ride, got %v", after)
	}
}

func TestAFinishedRideLetsThePersonAskAgainForTheSameAppointment(t *testing.T) {
	h := newTestServer(t)
	jane, sam, _, id := matchedRide(t, h)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil)
	var list map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", jane, nil), &list)
	appt := asMap(t, list["appointments"].([]interface{})[0])
	if appt["needsRide"] != false {
		t.Fatalf("a finished ride no longer needs one, got %v", appt)
	}
	rec := doRequest(t, h, http.MethodPatch, "/api/appointments/"+appt["id"].(string), jane, map[string]interface{}{"needsRide": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("asking again: expected 200, got %d", rec.Code)
	}
}

func TestAskingForBasicItemsFromAList(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, sam, tok("b"))
	post := func(body map[string]interface{}) (int, map[string]interface{}) {
		rec := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, body)
		var out map[string]interface{}
		decodeJSON(t, rec, &out)
		return rec.Code, out
	}
	f.reset()
	code, out := post(map[string]interface{}{"category": "supplies", "items": []string{"socks", "blanket", "socks", "water"}, "note": "Size 10 shoes"})
	req := asMap(t, out["request"])
	if code != http.StatusCreated || req["category"] != "supplies" {
		t.Fatalf("a supplies request: got %d %v", code, out)
	}
	// Repeats are dropped and the list always reads in the same order.
	items := req["items"].([]interface{})
	if len(items) != 3 || items[0] != "water" || items[1] != "socks" || items[2] != "blanket" {
		t.Fatalf("expected water, socks, blanket once each, got %v", items)
	}
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Body != "Someone asked for basic items. Open the Help tab to see." {
		t.Fatalf("volunteers get one generic alert, got %v", got)
	}

	// Volunteers see the items on the board, and the person's own list shows them too.
	entry := asMap(t, board(t, h, sam)[0])
	if entry["category"] != "supplies" || len(entry["items"].([]interface{})) != 3 {
		t.Fatalf("the board should show the items, got %v", entry)
	}
	if mine := myRequest(t, h, jane); mine["category"] != "supplies" {
		t.Fatalf("the person sees their own request as supplies, got %v", mine)
	}

	for name, body := range map[string]map[string]interface{}{
		"nothing picked":     {"category": "supplies", "items": []string{}},
		"an unknown item":    {"category": "supplies", "items": []string{"socks", "a pony"}},
		"too many":           {"category": "supplies", "items": []string{"meal", "water", "snacks", "socks", "underwear", "shirt", "pants", "shoes", "coat", "hat_gloves", "blanket"}},
		"items on a non-sup": {"category": "food", "items": []string{"socks"}},
	} {
		if code, _ := post(body); code != http.StatusBadRequest {
			t.Fatalf("%s: expected 400, got %d", name, code)
		}
	}
}

func TestAVolunteerCanMarkTheItemsReady(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("a"))
	_, out := func() (int, map[string]interface{}) {
		rec := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, map[string]interface{}{"category": "supplies", "items": []string{"socks"}})
		var o map[string]interface{}
		decodeJSON(t, rec, &o)
		return rec.Code, o
	}()
	id := asMap(t, out["request"])["id"].(string)
	matchVolunteer(t, h, sam, id)
	f.reset()
	if code := progress(t, h, sam, id, "ready", nil); code != http.StatusOK {
		t.Fatalf("ready: expected 200, got %d", code)
	}
	if mine := myRequest(t, h, jane); mine["progress"] != "ready" {
		t.Fatalf("the person should see their items are ready, got %v", mine)
	}
	if got := f.to(tok("a")); len(got) != 1 || got[0].n.Body != "Your items are ready." {
		t.Fatalf("a generic alert, got %v", got)
	}
	// "Ready" is only for items, not a ride.
	ride, rideSam, _, rideID := matchedRide(t, h)
	_ = ride
	if code := progress(t, h, rideSam, rideID, "ready", nil); code != http.StatusBadRequest {
		t.Fatalf("ready on a ride: expected 400, got %d", code)
	}
}

func TestTheHelpHistoryShowsSuppliesRequestsAsSupplies(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	rec := doRequest(t, h, http.MethodPost, "/api/help-requests", jane, map[string]interface{}{"category": "supplies", "items": []string{"blanket"}})
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	id := asMap(t, out["request"])["id"].(string)
	matchVolunteer(t, h, sam, id)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil)
	var history map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/help-history", ada, nil), &history)
	entries := history["history"].([]interface{})
	if len(entries) != 1 || asMap(t, entries[0])["category"] != "supplies" {
		t.Fatalf("history should call it supplies, got %v", entries)
	}
}

func TestTheBoardListsRidesFirstSoonestAppointmentFirst(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	createHelp(t, h, jane, map[string]interface{}{"category": "food", "note": "first asked, not a ride"})
	postAppt(t, h, jane, map[string]interface{}{"title": "Later visit", "startsAt": "2026-12-09T15:00:00Z", "needsRide": true})
	postAppt(t, h, jane, map[string]interface{}{"title": "Sooner visit", "startsAt": "2026-12-03T15:00:00Z", "needsRide": true})

	var titles []string
	for _, r := range board(t, h, sam) {
		m := asMap(t, r)
		if appt, ok := m["appointment"].(map[string]interface{}); ok && appt != nil {
			titles = append(titles, appt["title"].(string))
		} else {
			titles = append(titles, "(not a ride)")
		}
	}
	if len(titles) != 3 || titles[0] != "Sooner visit" || titles[1] != "Later visit" || titles[2] != "(not a ride)" {
		t.Fatalf("rides should come first, soonest first, got %v", titles)
	}
}
