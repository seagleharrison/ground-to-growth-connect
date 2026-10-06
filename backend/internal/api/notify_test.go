package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"

	"ground-to-growth-connect-backend/internal/push"
)

type sentPush struct {
	token, env string
	n          push.Notification
}

type fakePush struct {
	mu     sync.Mutex
	sent   []sentPush
	reject map[string]error
}

func (f *fakePush) Send(_ context.Context, token, env string, n push.Notification) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := f.reject[token]; err != nil {
		return err
	}
	f.sent = append(f.sent, sentPush{token, env, n})
	return nil
}

func (f *fakePush) to(token string) []sentPush {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []sentPush
	for _, s := range f.sent {
		if s.token == token {
			out = append(out, s)
		}
	}
	return out
}

func (f *fakePush) reset() {
	f.mu.Lock()
	f.sent = nil
	f.mu.Unlock()
}

func pushServer(t *testing.T) (http.Handler, *fakePush) {
	t.Helper()
	f := &fakePush{reject: map[string]error{}}
	h, _, _ := setupTestServerWithOptions(t, WithPush(f), withPushSync())
	return h, f
}

func tok(n string) string { return strings.Repeat(n, 32) } // 32 hex chars

func registerToken(t *testing.T, h http.Handler, who, token string) {
	t.Helper()
	rec := doRequest(t, h, http.MethodPut, "/api/push-token", who, map[string]interface{}{"token": token, "environment": "sandbox"})
	if rec.Code != http.StatusOK {
		t.Fatalf("register token: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPushTokenValidation(t *testing.T) {
	h, _ := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	for name, body := range map[string]map[string]interface{}{
		"not hex":         {"token": "zzzz" + tok("a")},
		"too short":       {"token": "abcd"},
		"bad environment": {"token": tok("a"), "environment": "staging"},
		"missing":         {},
	} {
		if code := doRequest(t, h, http.MethodPut, "/api/push-token", jane, body).Code; code != http.StatusBadRequest {
			t.Fatalf("%s: expected 400, got %d", name, code)
		}
	}
	if code := doRequest(t, h, http.MethodPut, "/api/push-token", "", map[string]interface{}{"token": tok("a")}).Code; code != http.StatusUnauthorized {
		t.Fatalf("no auth: expected 401, got %d", code)
	}
}

func TestMessageSendsAnAlertWithNoTextAndNoNames(t *testing.T) {
	h, f := pushServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	adaToken, adaU := newAdmin(t, h)
	registerToken(t, h, adaToken, tok("a"))
	_ = adaU

	if code := send(t, h, jane, idOf(adaU), "my secret address is 12 Oak Street"); code != http.StatusCreated {
		t.Fatalf("send: expected 201, got %d", code)
	}
	got := f.to(tok("a"))
	if len(got) != 1 {
		t.Fatalf("expected one alert, got %d", len(got))
	}
	n := got[0].n
	if got[0].env != "sandbox" {
		t.Fatalf("expected the token's environment to be used, got %q", got[0].env)
	}
	all := n.Title + " " + n.Body
	for _, leak := range []string{"secret", "Oak Street", "Jane", "Doe"} {
		if strings.Contains(all, leak) {
			t.Fatalf("an alert must not contain %q: %v", leak, n)
		}
	}
	if n.Badge == nil || *n.Badge != 1 {
		t.Fatalf("the badge should be the unread count (1), got %v", n.Badge)
	}
	if n.Data["kind"] != "message" || n.Data["userId"] != idOf(janeU) {
		t.Fatalf("data should say who it's from by id only: %v", n.Data)
	}
}

func TestNoTokenMeansNoAlertAndNothingBreaks(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := newAdmin(t, h)
	if code := send(t, h, jane, idOf(adaU), "hello"); code != http.StatusCreated {
		t.Fatalf("send should work without any tokens, got %d", code)
	}
	if len(f.sent) != 0 {
		t.Fatalf("nobody had a token, so nothing should be sent")
	}
}

func TestServerWorksWithPushTurnedOff(t *testing.T) {
	h := newTestServer(t) // no sender configured
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	_, adaU := newAdmin(t, h)
	registerToken(t, h, jane, tok("b"))
	if code := send(t, h, jane, idOf(adaU), "hello"); code != http.StatusCreated {
		t.Fatalf("send with push off: expected 201, got %d", code)
	}
}

func TestANewHelpRequestAlertsApprovedStaffButNotPendingBlockedOrPausedOnes(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	pending, _ := unapprovedVolunteer(t, h, "Pending Pat")
	blockedVol, blockedU := registerUser(t, h, map[string]interface{}{"name": "Blocked Bo", "personType": "volunteer", "staffCode": testStaffCode})
	paused, pausedU := registerUser(t, h, map[string]interface{}{"name": "Paused Pam", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, ada, tok("1"))
	registerToken(t, h, sam, tok("2"))
	registerToken(t, h, pending, tok("3"))
	registerToken(t, h, blockedVol, tok("4"))
	registerToken(t, h, paused, tok("5"))
	registerToken(t, h, jane, tok("6"))
	doRequest(t, h, http.MethodPost, "/api/blocks", jane, map[string]interface{}{"userId": idOf(blockedU)})
	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(pausedU)+"/pause", ada, nil)
	f.reset()

	createHelp(t, h, jane, map[string]interface{}{"category": "ride", "note": "private note about my situation"})

	for token, want := range map[string]int{tok("1"): 1, tok("2"): 1, tok("3"): 0, tok("4"): 0, tok("5"): 0, tok("6"): 0} {
		if got := len(f.to(token)); got != want {
			t.Fatalf("token %q: expected %d alerts, got %d", token[:2], want, got)
		}
	}
	n := f.to(tok("2"))[0].n
	if strings.Contains(n.Title+n.Body, "private note") || strings.Contains(n.Title+n.Body, "Jane") {
		t.Fatalf("the alert must not carry the note or the name: %v", n)
	}
}

func TestClaimingTellsThePersonSomeoneIsHelping(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("a"))
	id := createHelp(t, h, jane, map[string]interface{}{"category": "ride"})["id"].(string)
	f.reset()

	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	got := f.to(tok("a"))
	if len(got) != 1 || got[0].n.Title != "Help is on the way" || strings.Contains(got[0].n.Body, "Sam") {
		t.Fatalf("expected one generic alert, got %v", got)
	}
	// Claiming it again does not alert twice.
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/claim", sam, nil)
	if len(f.to(tok("a"))) != 1 {
		t.Fatalf("a repeated claim must not send another alert")
	}
}

func TestAdminsAreToldAboutReportsAndNewVolunteers(t *testing.T) {
	h, f := pushServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	registerToken(t, h, ada, tok("a"))

	unapprovedVolunteer(t, h, "New Nia")
	got := f.to(tok("a"))
	if len(got) != 1 || got[0].n.Title != "A volunteer needs approval" {
		t.Fatalf("admin should hear about the new volunteer, got %v", got)
	}

	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	_ = sam
	f.reset()
	doRequest(t, h, http.MethodPost, "/api/reports", jane, map[string]interface{}{"userId": idOf(samU), "reason": "creepy"})
	got = f.to(tok("a"))
	if len(got) != 1 || got[0].n.Title != "New report" || strings.Contains(got[0].n.Body, "creepy") || strings.Contains(got[0].n.Body, "Sam") {
		t.Fatalf("admin should be told generically about the report, got %v", got)
	}

	// A person switching to volunteer is also announced.
	f.reset()
	pat, _ := registerUser(t, h, map[string]interface{}{"name": "Pat"})
	patchMe(t, h, pat, map[string]interface{}{"personType": "volunteer", "staffCode": testStaffCode})
	if len(f.to(tok("a"))) != 1 {
		t.Fatalf("a participant becoming a volunteer should alert admins")
	}
}

func TestApprovalTellsTheVolunteer(t *testing.T) {
	h, f := pushServer(t)
	ada, _ := newAdmin(t, h)
	nia, niaU := unapprovedVolunteer(t, h, "New Nia")
	registerToken(t, h, nia, tok("c"))
	_ = ada
	doRequest(t, h, http.MethodPost, "/api/admin/volunteers/"+idOf(niaU)+"/approve", ada, nil)
	got := f.to(tok("c"))
	if len(got) != 1 || got[0].n.Title != "You're approved" {
		t.Fatalf("expected an approval alert, got %v", got)
	}
}

func TestATokenMovesToWhoeverSignsInOnThatPhoneAndLeavesOnSignOut(t *testing.T) {
	h, f := pushServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	bob, bobU := registerUser(t, h, map[string]interface{}{"name": "Bob"})
	_, adaU := newAdmin(t, h)

	// Same phone: Jane signs in, then Bob does.
	registerToken(t, h, jane, tok("a"))
	registerToken(t, h, bob, tok("a"))
	// A message for Jane must not reach Bob's phone-in-hand any more.
	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada Three", "personType": "admin", "staffCode": testStaffCode})
	var adaMe map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/me", ada, nil), &adaMe)
	send(t, h, ada, idOf(janeU), "for Jane")
	if len(f.to(tok("a"))) != 0 {
		t.Fatalf("Jane's alert must not go to the phone Bob now holds")
	}
	send(t, h, ada, idOf(bobU), "for Bob")
	if len(f.to(tok("a"))) != 1 {
		t.Fatalf("Bob's alert should reach his phone")
	}

	// Sign-out removes it.
	if code := doRequest(t, h, http.MethodDelete, "/api/push-token", bob, map[string]interface{}{"token": tok("a")}).Code; code != http.StatusOK {
		t.Fatalf("unregister: expected 200, got %d", code)
	}
	f.reset()
	send(t, h, ada, idOf(bobU), "again")
	if len(f.sent) != 0 {
		t.Fatalf("after sign-out nothing should be sent")
	}
	_ = adaU
}

func TestOnePersonCannotRemoveSomeoneElsesToken(t *testing.T) {
	h, f := pushServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	mallory, _ := registerUser(t, h, map[string]interface{}{"name": "Mallory"})
	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("a"))
	doRequest(t, h, http.MethodDelete, "/api/push-token", mallory, map[string]interface{}{"token": tok("a")})
	send(t, h, ada, idOf(janeU), "hi")
	if len(f.to(tok("a"))) != 1 {
		t.Fatalf("Mallory must not be able to remove Jane's token")
	}
}

func TestAStaleTokenIsForgottenAfterApplesays410(t *testing.T) {
	h, f := pushServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("d"))
	f.reject[tok("d")] = push.ErrUnregistered

	send(t, h, ada, idOf(janeU), "one")
	delete(f.reject, tok("d")) // if it were still stored, the next send would now succeed
	send(t, h, ada, idOf(janeU), "two")
	if len(f.to(tok("d"))) != 0 {
		t.Fatalf("a token Apple said is dead must be forgotten")
	}
}

func TestOtherPushErrorsDoNotForgetTheTokenOrBreakTheRequest(t *testing.T) {
	h, f := pushServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := registerUser(t, h, map[string]interface{}{"name": "Ada", "personType": "admin", "staffCode": testStaffCode})
	registerToken(t, h, jane, tok("e"))
	f.reject[tok("e")] = http.ErrHandlerTimeout
	if code := send(t, h, ada, idOf(janeU), "one"); code != http.StatusCreated {
		t.Fatalf("a push failure must not fail the message, got %d", code)
	}
	delete(f.reject, tok("e"))
	send(t, h, ada, idOf(janeU), "two")
	if len(f.to(tok("e"))) != 1 {
		t.Fatalf("a temporary failure should keep the token")
	}
}

func TestDeletingAnAccountDeletesItsTokens(t *testing.T) {
	h, db := setupTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	registerToken(t, h, jane, tok("f"))
	doRequest(t, h, http.MethodDelete, "/api/account", jane, nil)
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM push_tokens`).Scan(&n)
	if n != 0 {
		t.Fatalf("expected tokens to go with the account, found %d", n)
	}
}

func TestAPersonKeepsAtMostTenPhones(t *testing.T) {
	h, db := setupTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	for i := 0; i < 14; i++ {
		registerToken(t, h, jane, fmt.Sprintf("%032x", i+1))
	}
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM push_tokens`).Scan(&n)
	if n != maxTokensPerUser {
		t.Fatalf("expected %d tokens, found %d", maxTokensPerUser, n)
	}
}
