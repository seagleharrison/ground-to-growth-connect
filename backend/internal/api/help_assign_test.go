package api

import (
	"net/http"
	"strings"
	"testing"
)

func askVolunteer(t *testing.T, h http.Handler, adminToken string, volunteer map[string]interface{}, requestID string) int {
	t.Helper()
	return doRequest(t, h, http.MethodPost, "/api/admin/help-requests/"+requestID+"/ask", adminToken, map[string]interface{}{"volunteerId": idOf(volunteer)}).Code
}

func TestAnAdminCanPingAVolunteerAboutARequestInChat(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, adaU := newAdmin(t, h)
	registerToken(t, h, sam, tok("b"))
	id := createHelp(t, h, jane, map[string]interface{}{"category": "supplies", "items": []string{"socks", "blanket", "water"}, "note": "private note"})["id"].(string)
	f.reset()

	if code := askVolunteer(t, h, ada, samU, id); code != http.StatusOK {
		t.Fatalf("ping: expected 200, got %d", code)
	}

	// The message waits in their chat with the admin: first names only, and what is needed.
	var thread map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(adaU), sam, nil), &thread)
	msgs := thread["messages"].([]interface{})
	if len(msgs) != 1 {
		t.Fatalf("expected one message from the admin, got %v", msgs)
	}
	body := asMap(t, msgs[0])["body"].(string)
	for _, want := range []string{"Sam", "Jane", "water, socks and a blanket"} {
		if !strings.Contains(body, want) {
			t.Fatalf("the message should mention %q, got %q", want, body)
		}
	}
	for _, leak := range []string{"Doe", "Helper", "private note"} {
		if strings.Contains(body, leak) {
			t.Fatalf("the message must not carry %q, got %q", leak, body)
		}
	}

	// The alert is the usual generic one, and pinging does not hand the request over.
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Body != "You have a new message." {
		t.Fatalf("expected one generic alert, got %v", got)
	}
	if len(board(t, h, sam)) != 0 {
		t.Fatalf("a ping is only a question: the request is not theirs until an admin assigns it")
	}
}

func TestAPingForARideNamesTheDestinationAndTime(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	ada, adaU := newAdmin(t, h)
	_, out := postAppt(t, h, jane, map[string]interface{}{"title": "DDS visit", "startsAt": "2026-12-03T15:00:00Z", "needsRide": true})
	_ = out
	rideID := ridesOnBoard(t, h, ada)[0]["id"].(string)

	if code := askVolunteer(t, h, ada, samU, rideID); code != http.StatusOK {
		t.Fatalf("ping: expected 200, got %d", code)
	}
	var thread map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(adaU), sam, nil), &thread)
	body := asMap(t, thread["messages"].([]interface{})[0])["body"].(string)
	// 15:00 UTC is 10:00 AM in Savannah in December.
	if !strings.Contains(body, "a ride to DDS visit on Thu Dec 3 at 10:00 AM") {
		t.Fatalf("a ride ping should say where and when in local time, got %q", body)
	}
}

func TestOnlyAdminsCanPingOrAssignAndOnlyApprovedVolunteersCanBePicked(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	_, pendingU := unapprovedVolunteer(t, h, "Pending Pat")
	ada, adaU := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)

	for who, token := range map[string]string{"participant": jane, "volunteer": sam} {
		if code := askVolunteer(t, h, token, samU, id); code != http.StatusForbidden {
			t.Fatalf("a %s pinging: expected 403, got %d", who, code)
		}
		if code := assignTo(t, h, token, samU, id); code != http.StatusForbidden {
			t.Fatalf("a %s assigning: expected 403, got %d", who, code)
		}
	}
	if code := askVolunteer(t, h, ada, pendingU, id); code != http.StatusConflict {
		t.Fatalf("pinging someone not yet approved: expected 409, got %d", code)
	}
	if code := assignTo(t, h, ada, pendingU, id); code != http.StatusConflict {
		t.Fatalf("assigning someone not yet approved: expected 409, got %d", code)
	}
	// The pick has to be a volunteer, and the request has to exist and still be open.
	if code := assignTo(t, h, ada, janeU, id); code != http.StatusNotFound {
		t.Fatalf("assigning a participant: expected 404, got %d", code)
	}
	if code := assignTo(t, h, ada, adaU, id); code != http.StatusNotFound {
		t.Fatalf("assigning an admin as a volunteer: expected 404, got %d", code)
	}
	if code := assignTo(t, h, ada, samU, "no-such-request"); code != http.StatusNotFound {
		t.Fatalf("an unknown request: expected 404, got %d", code)
	}
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", jane, nil)
	if code := assignTo(t, h, ada, samU, id); code != http.StatusNotFound {
		t.Fatalf("a finished request can't be assigned: expected 404, got %d", code)
	}
}

func TestAssigningTellsBothSidesWithoutNamesAndLogsIt(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	registerToken(t, h, jane, tok("a"))
	registerToken(t, h, sam, tok("b"))
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	f.reset()

	if code := assignTo(t, h, ada, samU, id); code != http.StatusOK {
		t.Fatalf("assign: expected 200, got %d", code)
	}
	if got := f.to(tok("a")); len(got) != 1 || got[0].n.Title != "Help is on the way" || strings.Contains(got[0].n.Body, "Sam") {
		t.Fatalf("the person is told once, without a name, got %v", got)
	}
	if got := f.to(tok("b")); len(got) != 1 || got[0].n.Title != "You've been given a request" || strings.Contains(got[0].n.Body, "Jane") {
		t.Fatalf("the volunteer is told once, without a name, got %v", got)
	}
	// Their list now has it; they can start the usual steps.
	if len(board(t, h, sam)) != 1 {
		t.Fatalf("the volunteer should see the request they were given")
	}
	if code := progress(t, h, sam, id, "on_my_way", nil); code != http.StatusOK {
		t.Fatalf("progress after being assigned: expected 200, got %d", code)
	}
}
