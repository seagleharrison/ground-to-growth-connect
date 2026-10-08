package api

import (
	"database/sql"
	"net/http"
	"testing"

	"ground-to-growth-connect-backend/internal/cryptox"
)

func send(t *testing.T, h http.Handler, token, toID, body string) int {
	t.Helper()
	return doRequest(t, h, http.MethodPost, "/api/messages/"+toID, token, map[string]interface{}{"body": body}).Code
}

func idOf(user map[string]interface{}) string { return user["id"].(string) }

func conversations(t *testing.T, h http.Handler, token string) []map[string]interface{} {
	t.Helper()
	var out map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/conversations", token, nil), &out)
	list := []map[string]interface{}{}
	for _, c := range out["conversations"].([]interface{}) {
		list = append(list, c.(map[string]interface{}))
	}
	return list
}

func TestParticipantCanMessageTheTeamAndTheyReply(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, adaU := registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})

	// Jane sees the team as a contact before anyone has said anything.
	cs := conversations(t, h, jane)
	if len(cs) != 1 || cs[0]["name"] != "Ada" || cs[0]["role"] != "team" {
		t.Fatalf("expected the team as a contact (first name only), got %v", cs)
	}

	if code := send(t, h, jane, idOf(adaU), "Hi, I need some help"); code != http.StatusCreated {
		t.Fatalf("send: expected 201, got %d", code)
	}
	adaView := conversations(t, h, ada)
	if len(adaView) != 1 || adaView[0]["name"] != "Jane Doe" || adaView[0]["unread"].(float64) != 1 {
		t.Fatalf("admin should see Jane with 1 unread, got %v", adaView)
	}

	var thread map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(janeU), ada, nil), &thread)
	msgs := thread["messages"].([]interface{})
	if len(msgs) != 1 || asMap(t, msgs[0])["body"] != "Hi, I need some help" || asMap(t, msgs[0])["fromMe"] != false {
		t.Fatalf("unexpected thread: %v", msgs)
	}
	if conversations(t, h, ada)[0]["unread"].(float64) != 0 {
		t.Fatalf("opening the thread should mark it read")
	}

	send(t, h, ada, idOf(janeU), "On it!")
	if conversations(t, h, jane)[0]["unread"].(float64) != 1 {
		t.Fatalf("Jane should see the reply as unread")
	}
}

// seedMessage writes a message straight into the database, for the chats that
// can no longer be started (volunteer and participant) but may still exist as history.
func seedMessage(t *testing.T, db *sql.DB, fromID, toID, text string) {
	t.Helper()
	enc, err := cryptox.EncryptString(&text)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO messages (sender_id, recipient_id, body_encrypted) VALUES (?, ?, ?)`, fromID, toID, enc); err != nil {
		t.Fatalf("seed message: %v", err)
	}
}

func TestChatOnlyRunsThroughAdmins(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, adaU := newAdmin(t, h)

	// Volunteers and participants never reach each other, even mid-request.
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	matchVolunteer(t, h, sam, id)
	if code := send(t, h, sam, idOf(janeU), "I'll pick you up at 9"); code != http.StatusForbidden {
		t.Fatalf("volunteer to participant: expected 403, got %d", code)
	}
	if code := send(t, h, jane, idOf(samU), "thanks"); code != http.StatusForbidden {
		t.Fatalf("participant to volunteer: expected 403, got %d", code)
	}

	// Admins talk with both.
	if code := send(t, h, jane, idOf(adaU), "hello"); code != http.StatusCreated {
		t.Fatalf("participant to admin: expected 201, got %d", code)
	}
	if code := send(t, h, sam, idOf(adaU), "I'm on it"); code != http.StatusCreated {
		t.Fatalf("volunteer to admin: expected 201, got %d", code)
	}
	if code := send(t, h, ada, idOf(samU), "Thanks Sam"); code != http.StatusCreated {
		t.Fatalf("admin to volunteer: expected 201, got %d", code)
	}
	if code := send(t, h, ada, idOf(janeU), "On it!"); code != http.StatusCreated {
		t.Fatalf("admin to participant: expected 201, got %d", code)
	}

	// Each person's list is just the team, or for the admin, the people they serve.
	for _, c := range conversations(t, h, sam) {
		if c["role"] != "team" {
			t.Fatalf("a volunteer should only see the team, got %v", c)
		}
	}
	for _, c := range conversations(t, h, jane) {
		if c["role"] != "team" {
			t.Fatalf("a participant should only see the team, got %v", c)
		}
	}
	roles := map[string]bool{}
	for _, c := range conversations(t, h, ada) {
		roles[c["role"].(string)] = true
	}
	if !roles["volunteer"] || !roles["participant"] {
		t.Fatalf("an admin should see both volunteers and participants, got %v", roles)
	}
}

func TestAVolunteerNotYetApprovedCannotChat(t *testing.T) {
	h := newTestServer(t)
	pending, _ := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode, "_unapproved": true})
	_, adaU := newAdmin(t, h)
	if code := send(t, h, pending, idOf(adaU), "hi"); code != http.StatusForbidden {
		t.Fatalf("unapproved volunteer: expected 403, got %d", code)
	}
}

func TestChatIsPrivateBetweenTheTwoPeople(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	bob, bobU := registerUser(t, h, map[string]interface{}{"name": "Bob"})
	_, adaU := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	send(t, h, jane, idOf(adaU), "private words")

	// Bob cannot read Jane's thread by guessing ids.
	if code := doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(janeU), bob, nil).Code; code != http.StatusNotFound {
		t.Fatalf("Bob reading a thread with Jane: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(adaU), bob, nil).Code; code != http.StatusOK {
		t.Fatalf("Bob may open his own (empty) thread with the team, got %d", code)
	}
	var thread map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/messages/"+idOf(adaU), bob, nil), &thread)
	if len(thread["messages"].([]interface{})) != 0 {
		t.Fatalf("Bob's thread must not include Jane's messages")
	}
	_ = bobU
}

func TestMessagesAreEncryptedAndValidated(t *testing.T) {
	h, db := setupTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})

	if code := send(t, h, jane, idOf(adaU), "   "); code != http.StatusBadRequest {
		t.Fatalf("blank message: expected 400, got %d", code)
	}
	send(t, h, jane, idOf(adaU), "very secret words")
	var raw []byte
	if err := db.QueryRow(`SELECT body_encrypted FROM messages LIMIT 1`).Scan(&raw); err != nil {
		t.Fatalf("query: %v", err)
	}
	if string(raw) == "very secret words" {
		t.Fatalf("message body must not be stored in plaintext")
	}
	if code := doRequest(t, h, http.MethodGet, "/api/conversations", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("conversations without auth: expected 401, got %d", code)
	}
}

func TestVolunteersCannotMessageEachOtherAndNobodyMessagesThemselves(t *testing.T) {
	h := newTestServer(t)
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	_, patU := registerUser(t, h, map[string]interface{}{"name": "Pat", "personType": "volunteer", "staffCode": testStaffCode})
	ada, adaU := newAdmin(t, h)
	_, benU := newAdmin(t, h)
	if code := send(t, h, sam, idOf(patU), "hi"); code != http.StatusForbidden {
		t.Fatalf("volunteer to volunteer: expected 403, got %d", code)
	}
	if code := send(t, h, ada, idOf(benU), "hi"); code != http.StatusForbidden {
		t.Fatalf("admin to admin: expected 403, got %d", code)
	}
	_ = adaU
	if code := send(t, h, sam, idOf(samU), "hi"); code != http.StatusForbidden {
		t.Fatalf("to self: expected 403, got %d", code)
	}
}

func TestDeletingAnAccountDeletesItsMessages(t *testing.T) {
	h, db := setupTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	send(t, h, jane, idOf(adaU), "hello")
	doRequest(t, h, http.MethodDelete, "/api/account", jane, nil)
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM messages`).Scan(&n)
	if n != 0 {
		t.Fatalf("expected messages to go with the account, found %d", n)
	}
}
