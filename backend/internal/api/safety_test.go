package api

import (
	"net/http"
	"strings"
	"testing"
)

func newAdmin(t *testing.T, h http.Handler) (string, map[string]interface{}) {
	t.Helper()
	return registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})
}

func unapprovedVolunteer(t *testing.T, h http.Handler, name string) (string, map[string]interface{}) {
	t.Helper()
	return registerUser(t, h, map[string]interface{}{"name": name, "personType": "volunteer", "staffCode": testStaffCode, "_unapproved": true})
}

func TestNewVolunteerSeesNothingUntilAnAdminApprovesThem(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := unapprovedVolunteer(t, h, "Sam Helper")
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	for _, path := range []string{"/api/help-requests", "/api/locations/latest", "/api/documents/on-file"} {
		if code := doRequest(t, h, http.MethodGet, path, sam, nil).Code; code != http.StatusForbidden {
			t.Fatalf("%s for an unapproved volunteer: expected 403, got %d", path, code)
		}
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusForbidden {
		t.Fatalf("claim by an unapproved volunteer: expected 403, got %d", code)
	}
	if code := send(t, h, sam, idOf(janeU), "hi"); code != http.StatusForbidden {
		t.Fatalf("message by an unapproved volunteer: expected 403, got %d", code)
	}
	if len(conversations(t, h, sam)) != 0 {
		t.Fatalf("an unapproved volunteer should have no contacts")
	}

	// Only an admin can approve.
	if code := doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/approve", sam, nil).Code; code != http.StatusForbidden {
		t.Fatalf("self-approval: expected 403, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/approve", ada, nil).Code; code != http.StatusOK {
		t.Fatalf("admin approval: expected 200, got %d", code)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/help-requests", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("after approval the board should open, got %d", code)
	}
}

func TestAdminSeesWhoIsWaitingForApproval(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)
	unapprovedVolunteer(t, h, "Pending Pat")
	registerUser(t, h, map[string]interface{}{"name": "Approved Al", "personType": "volunteer", "staffCode": testStaffCode})

	var out map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/volunteers", ada, nil), &out)
	vols := out["volunteers"].([]interface{})
	if len(vols) != 2 {
		t.Fatalf("expected 2 volunteers, got %d", len(vols))
	}
	first := asMap(t, vols[0])
	if first["name"] != "Pending Pat" || first["approved"] != false {
		t.Fatalf("pending volunteers should come first, got %v", first)
	}
}

func TestSwitchingToVolunteerStartsUnapprovedAndLeavingStaffReleasesRequests(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	pat, patU := registerUser(t, h, map[string]interface{}{"name": "Pat"})
	ada, _ := newAdmin(t, h)

	patchMe(t, h, pat, map[string]interface{}{"personType": "volunteer", "staffCode": testStaffCode})
	if code := doRequest(t, h, http.MethodGet, "/api/help-requests", pat, nil).Code; code != http.StatusForbidden {
		t.Fatalf("a newly switched volunteer needs approval, got %d", code)
	}
	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(patU)+"/approve", ada, nil)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", pat, nil)

	patchMe(t, h, pat, map[string]interface{}{"personType": "homeless"})
	if asMap(t, board(t, h, ada)[0])["status"] != "open" {
		t.Fatalf("someone who stops being a volunteer should hand back what they took on")
	}
}

func TestOldVolunteerChatsStayReadableButClosed(t *testing.T) {
	h, db := setupTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	seedMessage(t, db, idOf(samU), idOf(janeU), "On my way")

	if code := send(t, h, sam, idOf(janeU), "Hey, can we talk?"); code != http.StatusForbidden {
		t.Fatalf("volunteer to participant: expected 403, got %d", code)
	}
	if code := send(t, h, jane, idOf(samU), "thanks"); code != http.StatusForbidden {
		t.Fatalf("participant to volunteer: expected 403, got %d", code)
	}
	// The history is still there to read, marked closed.
	var thread map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(samU), jane, nil), &thread)
	if len(thread["messages"].([]interface{})) != 1 || thread["canSend"] != false {
		t.Fatalf("closed thread should be readable but not sendable, got %v", thread)
	}
	for _, c := range conversations(t, h, sam) {
		if c["userId"] == idOf(janeU) && c["canSend"] != false {
			t.Fatalf("the volunteer's list should show the chat as closed")
		}
	}
}

func TestParticipantCanAlwaysReachTheTeam(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := newAdmin(t, h)
	if code := send(t, h, jane, idOf(adaU), "I need help"); code != http.StatusCreated {
		t.Fatalf("participant to the team: expected 201, got %d", code)
	}
}

func TestBlockingAVolunteerEndsTheirHelpAndHidesTheRequest(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)

	rec := doRequest(t, h, http.MethodPost, "/api/blocks", jane, map[string]interface{}{"userId": idOf(samU)})
	if rec.Code != http.StatusOK {
		t.Fatalf("block: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// The request is back for someone else, and Sam can no longer see or take it.
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("a blocked volunteer should not see the person's requests")
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusNotFound {
		t.Fatalf("blocked volunteer claiming: expected 404, got %d", code)
	}
	if asMap(t, board(t, h, pat)[0])["status"] != "open" {
		t.Fatalf("the request should be open again for others")
	}
	if code := send(t, h, sam, idOf(janeU), "hello?"); code != http.StatusForbidden {
		t.Fatalf("blocked volunteer messaging: expected 403, got %d", code)
	}

	var list map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/blocks", jane, nil), &list)
	blocked := list["blocked"].([]interface{})
	if len(blocked) != 1 || asMap(t, blocked[0])["name"] != "Sam" {
		t.Fatalf("expected Sam in the blocked list (first name), got %v", blocked)
	}

	doRequest(t, h, http.MethodDelete, "/api/blocks/"+idOf(samU), jane, nil)
	if len(board(t, h, sam)) != 1 {
		t.Fatalf("after unblocking, Sam can see the request again")
	}
}

func TestBlockingRules(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := newAdmin(t, h)
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})

	if code := doRequest(t, h, http.MethodPost, "/api/blocks", jane, map[string]interface{}{"userId": idOf(adaU)}).Code; code != http.StatusBadRequest {
		t.Fatalf("blocking the team: expected 400, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/blocks", jane, map[string]interface{}{"userId": idOf(janeU)}).Code; code != http.StatusNotFound {
		t.Fatalf("blocking yourself: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/blocks", sam, map[string]interface{}{"userId": idOf(janeU)}).Code; code != http.StatusForbidden {
		t.Fatalf("a volunteer blocking a participant: expected 403, got %d", code)
	}
}

func TestReportingAVolunteerBlocksThemAtOnceAndAdminsSeeIt(t *testing.T) {
	h, db := setupTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)

	rec := doRequest(t, h, http.MethodPost, "/api/reports", jane, map[string]interface{}{"userId": idOf(samU), "reason": "Made me uncomfortable"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("report: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var created map[string]interface{}
	decodeJSON(t, rec, &created)
	if created["blocked"] != true {
		t.Fatalf("reporting a volunteer should protect the reporter straight away")
	}
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("the reported volunteer should lose sight of the reporter's request")
	}

	var reports map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/reports", ada, nil), &reports)
	list := reports["reports"].([]interface{})
	r0 := asMap(t, list[0])
	if len(list) != 1 || r0["reason"] != "Made me uncomfortable" || asMap(t, r0["subject"])["name"] != "Sam" || asMap(t, r0["reporter"])["name"] != "Jane Doe" {
		t.Fatalf("unexpected report list: %v", list)
	}

	var raw []byte
	if err := db.QueryRow(`SELECT reason_encrypted FROM reports LIMIT 1`).Scan(&raw); err != nil || strings.Contains(string(raw), "uncomfortable") {
		t.Fatalf("the reason must be encrypted at rest")
	}

	if code := doRequest(t, h, http.MethodGet, "/api/reports", jane, nil).Code; code != http.StatusForbidden {
		t.Fatalf("reports are admin-only, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/reports/"+r0["id"].(string)+"/resolve", ada, nil).Code; code != http.StatusOK {
		t.Fatalf("resolve: expected 200, got %d", code)
	}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/reports", ada, nil), &reports)
	if asMap(t, reports["reports"].([]interface{})[0])["status"] != "resolved" {
		t.Fatalf("expected the report to be resolved")
	}
}

func TestReportValidation(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	if code := doRequest(t, h, http.MethodPost, "/api/reports", jane, map[string]interface{}{"userId": idOf(janeU)}).Code; code != http.StatusNotFound {
		t.Fatalf("reporting yourself: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/reports", jane, map[string]interface{}{}).Code; code != http.StatusBadRequest {
		t.Fatalf("no user: expected 400, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/reports", "", map[string]interface{}{"userId": "x"}).Code; code != http.StatusUnauthorized {
		t.Fatalf("no auth: expected 401, got %d", code)
	}
}

func TestAdminCanReviewConversationsAndEveryLookIsLogged(t *testing.T) {
	h, db := setupTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	seedMessage(t, db, idOf(samU), idOf(janeU), "I'll pick you up at nine")
	seedMessage(t, db, idOf(janeU), idOf(samU), "Thank you")

	// The overview shows who is talking, but not what is said.
	rec := doRequest(t, h, http.MethodGet, "/api/admin/conversations", ada, nil)
	if strings.Contains(rec.Body.String(), "pick you up") {
		t.Fatalf("the overview must not contain message text")
	}
	var overview map[string]interface{}
	decodeJSON(t, rec, &overview)
	list := overview["conversations"].([]interface{})
	if len(list) != 1 || asMap(t, list[0])["count"].(float64) != 2 {
		t.Fatalf("expected one conversation of 2 messages, got %v", list)
	}

	var log map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/access-log", ada, nil), &log)
	if len(log["log"].([]interface{})) != 0 {
		t.Fatalf("nothing has been read yet, so nothing should be logged")
	}

	rec = doRequest(t, h, http.MethodGet, "/api/admin/conversations/"+idOf(janeU)+"/"+idOf(samU), ada, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "I'll pick you up at nine") {
		t.Fatalf("admin should be able to read the conversation, got %d: %s", rec.Code, rec.Body.String())
	}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/access-log", ada, nil), &log)
	entries := log["log"].([]interface{})
	if len(entries) != 1 || asMap(t, entries[0])["admin"] != "Ada Admin" {
		t.Fatalf("reading must be logged with the admin's name, got %v", entries)
	}

	for _, who := range []string{jane, sam} {
		if code := doRequest(t, h, http.MethodGet, "/api/admin/conversations", who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("only admins can review: expected 403, got %d", code)
		}
		if code := doRequest(t, h, http.MethodGet, "/api/admin/conversations/"+idOf(janeU)+"/"+idOf(samU), who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("only admins can read: expected 403, got %d", code)
		}
	}
	if code := doRequest(t, h, http.MethodGet, "/api/admin/conversations/"+idOf(janeU)+"/nobody", ada, nil).Code; code != http.StatusNotFound {
		t.Fatalf("no such conversation: expected 404, got %d", code)
	}
}

func TestAConversationWithAnOpenReportIsFlagged(t *testing.T) {
	h, db := setupTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	seedMessage(t, db, idOf(samU), idOf(janeU), "hello")
	doRequest(t, h, http.MethodPost, "/api/reports", jane, map[string]interface{}{"userId": idOf(samU)})

	var overview map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/conversations", ada, nil), &overview)
	if asMap(t, overview["conversations"].([]interface{})[0])["flagged"] != true {
		t.Fatalf("a conversation with an open report should be flagged for review")
	}
}

func TestPausingAVolunteerStopsTheirMessagingAndHelpAtOnce(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)

	if code := doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/pause", ada, nil).Code; code != http.StatusOK {
		t.Fatalf("pause: expected 200, got %d", code)
	}
	if code := send(t, h, sam, idOf(janeU), "hi"); code != http.StatusForbidden {
		t.Fatalf("paused volunteer messaging: expected 403, got %d", code)
	}
	if asMap(t, board(t, h, ada)[0])["status"] != "open" {
		t.Fatalf("pausing should hand their requests back")
	}
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusForbidden {
		t.Fatalf("paused volunteer claiming: expected 403, got %d", code)
	}
	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/unpause", ada, nil)
	if code := doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil).Code; code != http.StatusOK {
		t.Fatalf("after unpausing: expected 200, got %d", code)
	}
}

func TestRevokingApprovalTakesAccessAwayAndFreesTheirRequests(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)

	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/revoke", ada, nil)
	if code := doRequest(t, h, http.MethodGet, "/api/help-requests", sam, nil).Code; code != http.StatusForbidden {
		t.Fatalf("revoked volunteer: expected 403, got %d", code)
	}
	if asMap(t, board(t, h, ada)[0])["status"] != "open" {
		t.Fatalf("revoking should free their requests")
	}
}

func TestOnlyAdminsManageVolunteers(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	for _, who := range []string{jane, sam} {
		for _, action := range []string{"approve", "revoke", "pause", "unpause"} {
			if code := doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(samU)+"/"+action, who, nil).Code; code != http.StatusForbidden {
				t.Fatalf("%s as non-admin: expected 403, got %d", action, code)
			}
		}
		if code := doRequest(t, h, http.MethodGet, "/api/admin/volunteers", who, nil).Code; code != http.StatusForbidden {
			t.Fatalf("listing volunteers as non-admin: expected 403, got %d", code)
		}
	}
}
