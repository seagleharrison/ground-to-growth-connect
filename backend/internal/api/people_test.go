package api

import (
	"net/http"
	"strings"
	"testing"
)

func peopleList(t *testing.T, h http.Handler, token, group string) []interface{} {
	t.Helper()
	rec := doRequest(t, h, http.MethodGet, "/api/admin/people?group="+group, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("people %s: expected 200, got %d: %s", group, rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	return out["people"].([]interface{})
}

func TestAdminsSeeEveryoneRegisteredInTwoLists(t *testing.T) {
	h := newTestServer(t)
	_, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe", "phone": "912-555-0101"})
	registerUser(t, h, map[string]interface{}{"name": "Bob Smith", "phone": "912-555-0102"})
	_, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode, "_unapproved": true})
	ada, _ := newAdmin(t, h)

	serve := peopleList(t, h, ada, "serve")
	if len(serve) != 2 {
		t.Fatalf("expected 2 people served, got %d", len(serve))
	}
	names := map[string]bool{}
	for _, p := range serve {
		m := asMap(t, p)
		names[m["name"].(string)] = true
		if m["role"] != "participant" {
			t.Fatalf("people we serve are participants, got %v", m)
		}
	}
	if !names["Jane Doe"] || !names["Bob Smith"] {
		t.Fatalf("both participants should be listed, got %v", names)
	}

	staff := peopleList(t, h, ada, "staff")
	roles := map[string]map[string]interface{}{}
	for _, p := range staff {
		m := asMap(t, p)
		roles[m["name"].(string)] = m
	}
	if roles["Sam Helper"]["role"] != "volunteer" || roles["Sam Helper"]["approved"] != false {
		t.Fatalf("a volunteer waiting for approval should show as such, got %v", roles["Sam Helper"])
	}
	if roles["Ada Admin"]["role"] != "admin" || roles["Ada Admin"]["approved"] != true {
		t.Fatalf("the admin should be listed as approved, got %v", roles["Ada Admin"])
	}
	_, _ = janeU, samU
}

func TestThePeopleListsAreForAdminsOnly(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, _ := registerUser(t, h, map[string]interface{}{"name": "Sam", "personType": "volunteer", "staffCode": testStaffCode})
	for _, who := range []string{jane, sam, ""} {
		want := http.StatusForbidden
		if who == "" {
			want = http.StatusUnauthorized
		}
		if code := doRequest(t, h, http.MethodGet, "/api/admin/people?group=serve", who, nil).Code; code != want {
			t.Fatalf("list for a non-admin: expected %d, got %d", want, code)
		}
		if code := doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(janeU), who, nil).Code; code != want {
			t.Fatalf("profile for a non-admin: expected %d, got %d", want, code)
		}
	}
}

func TestAProfileShowsWhoSomeoneIsAndWhereTheyStand(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe", "email": "jane@example.com", "gender": "female", "phone": "912-555-0101"})
	ada, _ := newAdmin(t, h)
	doRequest(t, h, http.MethodPost, "/api/consent", jane, map[string]interface{}{"granted": true})
	doRequest(t, h, http.MethodPost, "/api/locations", jane, map[string]interface{}{"latitude": 32.08, "longitude": -81.09})
	doRequest(t, h, http.MethodPost, "/api/appointments", jane, map[string]interface{}{"title": "Secret clinic visit", "startsAt": "2026-12-01T15:00:00Z"})
	send(t, h, jane, idOf(func() map[string]interface{} {
		_, u := registerUser(t, h, map[string]interface{}{"name": "Ada Two", "personType": "admin", "staffCode": testStaffCode})
		return u
	}()), "a private message")

	rec := doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(janeU), ada, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("profile: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var out map[string]interface{}
	decodeJSON(t, rec, &out)
	p := asMap(t, out["person"])
	if p["name"] != "Jane Doe" || p["email"] != "jane@example.com" || p["gender"] != "female" || p["phone"] == nil {
		t.Fatalf("the profile should show what they gave us, got %v", p)
	}
	if p["sharing"] != true || p["lastCheckIn"] == nil {
		t.Fatalf("a person sharing their location shows when they last checked in, got %v", p)
	}
	// Nothing private to the person is ever in a profile.
	body := rec.Body.String()
	for _, secret := range []string{"Secret clinic visit", "a private message", "32.08", "-81.09", "latitude"} {
		if strings.Contains(body, secret) {
			t.Fatalf("a profile must not include %q", secret)
		}
	}
}

func TestLastCheckInIsHiddenOnceSharingIsOff(t *testing.T) {
	h := newTestServer(t)
	jane, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, _ := newAdmin(t, h)
	doRequest(t, h, http.MethodPost, "/api/consent", jane, map[string]interface{}{"granted": true})
	doRequest(t, h, http.MethodPost, "/api/locations", jane, map[string]interface{}{"latitude": 32.08, "longitude": -81.09})
	doRequest(t, h, http.MethodPost, "/api/consent", jane, map[string]interface{}{"granted": false})

	var out map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(janeU), ada, nil), &out)
	p := asMap(t, out["person"])
	if p["sharing"] != false || p["lastCheckIn"] != nil {
		t.Fatalf("once sharing is off there is no check-in to show, got %v", p)
	}
}

func TestEveryProfileLookIsRecordedButNotYourOwn(t *testing.T) {
	h, db := setupTestServer(t)
	_, janeU := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	ada, adaU := newAdmin(t, h)

	count := func() int {
		var n int
		if err := db.QueryRow(`SELECT COUNT(*) FROM profile_access_log`).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(janeU), ada, nil)
	doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(janeU), ada, nil)
	if n := count(); n != 2 {
		t.Fatalf("two looks should be two log rows, got %d", n)
	}
	var admin, subject string
	if err := db.QueryRow(`SELECT admin_id, subject_id FROM profile_access_log LIMIT 1`).Scan(&admin, &subject); err != nil || admin != idOf(adaU) || subject != idOf(janeU) {
		t.Fatalf("the log should say who looked at whom, got %q %q (%v)", admin, subject, err)
	}
	doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(adaU), ada, nil)
	if n := count(); n != 2 {
		t.Fatalf("looking at your own profile is not recorded, got %d", n)
	}
	// The list itself reveals little and isn't logged per person.
	peopleList(t, h, ada, "serve")
	if n := count(); n != 2 {
		t.Fatalf("the list is not a profile look, got %d", n)
	}
}

func TestProfileEdgeCases(t *testing.T) {
	h := newTestServer(t)
	ada, _ := newAdmin(t, h)
	if code := doRequest(t, h, http.MethodGet, "/api/admin/people/nobody", ada, nil).Code; code != http.StatusNotFound {
		t.Fatalf("unknown person: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/admin/people?group=everyone", ada, nil).Code; code != http.StatusBadRequest {
		t.Fatalf("bad group: expected 400, got %d", code)
	}
	if code := doRequest(t, h, http.MethodGet, "/api/admin/people", ada, nil).Code; code != http.StatusBadRequest {
		t.Fatalf("missing group: expected 400, got %d", code)
	}
}

func TestAVolunteersProfileShowsApprovalAndHowTheyHaveDone(t *testing.T) {
	h := newTestServer(t)
	jane, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	sam, samU := registerUser(t, h, map[string]interface{}{"name": "Sam Helper", "personType": "volunteer", "staffCode": testStaffCode})
	ada, _ := newAdmin(t, h)
	id := createHelp(t, h, jane, map[string]interface{}{"category": "food"})["id"].(string)
	matchVolunteer(t, h, sam, id)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/complete", sam, nil)
	doRequest(t, h, http.MethodPost, "/api/help-requests/"+id+"/rating", jane, map[string]interface{}{"value": 1})

	var out map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/admin/people/"+idOf(samU), ada, nil), &out)
	p := asMap(t, out["person"])
	if p["role"] != "volunteer" || p["approved"] != true || p["helped"] != float64(1) || p["thumbsUp"] != float64(1) {
		t.Fatalf("the volunteer's profile should show approval, help given and thumbs, got %v", p)
	}
}
