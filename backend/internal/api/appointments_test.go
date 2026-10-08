package api

import (
	"net/http"
	"testing"
)

func TestAppointmentCRUD(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	rec := doRequest(t, h, http.MethodPost, "/api/appointments", token, map[string]interface{}{
		"title":    "Case worker check-in",
		"notes":    "Bring ID",
		"location": "Union Mission",
		"startsAt": "2026-10-01T14:00:00Z",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
	var created map[string]interface{}
	decodeJSON(t, rec, &created)
	appt := created["appointment"].(map[string]interface{})
	if appt["title"] != "Case worker check-in" || appt["notes"] != "Bring ID" || appt["location"] != "Union Mission" {
		t.Fatalf("unexpected created appointment: %v", appt)
	}
	id := appt["id"].(string)
	if id == "" {
		t.Fatalf("expected a non-empty id")
	}

	rec = doRequest(t, h, http.MethodGet, "/api/appointments", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list: expected 200, got %d", rec.Code)
	}
	var listed map[string]interface{}
	decodeJSON(t, rec, &listed)
	appointments := listed["appointments"].([]interface{})
	if len(appointments) != 1 {
		t.Fatalf("expected 1 appointment, got %d", len(appointments))
	}

	rec = doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, token, map[string]interface{}{
		"notes": "Bring ID and recovery code",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("update: expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var updated map[string]interface{}
	decodeJSON(t, rec, &updated)
	updatedAppt := updated["appointment"].(map[string]interface{})
	if updatedAppt["notes"] != "Bring ID and recovery code" {
		t.Fatalf("expected notes to update, got %v", updatedAppt)
	}
	if updatedAppt["title"] != "Case worker check-in" {
		t.Fatalf("expected title to stay the same when not included in the update, got %v", updatedAppt)
	}

	rec = doRequest(t, h, http.MethodDelete, "/api/appointments/"+id, token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete: expected 200, got %d", rec.Code)
	}

	rec = doRequest(t, h, http.MethodGet, "/api/appointments", token, nil)
	decodeJSON(t, rec, &listed)
	if len(listed["appointments"].([]interface{})) != 0 {
		t.Fatalf("expected no appointments after delete")
	}
}

func TestAppointmentValidation(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	if code := doRequest(t, h, http.MethodPost, "/api/appointments", token, map[string]interface{}{
		"title": "", "startsAt": "2026-10-01T14:00:00Z",
	}).Code; code != http.StatusBadRequest {
		t.Fatalf("empty title: expected 400, got %d", code)
	}

	if code := doRequest(t, h, http.MethodPost, "/api/appointments", token, map[string]interface{}{
		"title": "Something", "startsAt": "not-a-date",
	}).Code; code != http.StatusBadRequest {
		t.Fatalf("bad startsAt: expected 400, got %d", code)
	}
}

func TestAppointmentsAreEncryptedAtRest(t *testing.T) {
	h, db := setupTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})

	doRequest(t, h, http.MethodPost, "/api/appointments", token, map[string]interface{}{
		"title": "Very Private Meeting", "startsAt": "2026-10-01T14:00:00Z",
	})

	var raw []byte
	if err := db.QueryRow(`SELECT title_encrypted FROM appointments LIMIT 1`).Scan(&raw); err != nil {
		t.Fatalf("query: %v", err)
	}
	if string(raw) == "Very Private Meeting" {
		t.Fatalf("title must not be stored in plaintext")
	}
}

func TestAppointmentsArePrivatePerUserAndNeverVisibleToStaff(t *testing.T) {
	h := newTestServer(t)
	alice, _ := registerUser(t, h, map[string]interface{}{"name": "Alice"})
	bob, _ := registerUser(t, h, map[string]interface{}{"name": "Bob"})
	admin, _ := registerUser(t, h, map[string]interface{}{"name": "Ada Admin", "personType": "admin", "staffCode": testStaffCode})

	doRequest(t, h, http.MethodPost, "/api/appointments", alice, map[string]interface{}{
		"title": "Alice's appointment", "startsAt": "2026-10-01T14:00:00Z",
	})

	// Bob cannot see Alice's appointments.
	var bobList map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", bob, nil), &bobList)
	if len(bobList["appointments"].([]interface{})) != 0 {
		t.Fatalf("Bob should not see Alice's appointments")
	}

	// There is no staff endpoint for appointments at all.
	if code := doRequest(t, h, http.MethodGet, "/api/appointments/on-file", admin, nil).Code; code != http.StatusNotFound {
		t.Fatalf("expected no such staff route, got %d", code)
	}

	// Bob cannot update or delete Alice's appointment by guessing nothing —
	// there's no way to list her id, but even a well-formed request for a
	// nonexistent-to-Bob id must 404, not leak or modify Alice's row.
	var aliceList map[string]interface{}
	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", alice, nil), &aliceList)
	aliceApptID := aliceList["appointments"].([]interface{})[0].(map[string]interface{})["id"].(string)

	if code := doRequest(t, h, http.MethodPatch, "/api/appointments/"+aliceApptID, bob, map[string]interface{}{"title": "Hijacked"}).Code; code != http.StatusNotFound {
		t.Fatalf("Bob updating Alice's appointment: expected 404, got %d", code)
	}
	if code := doRequest(t, h, http.MethodDelete, "/api/appointments/"+aliceApptID, bob, nil).Code; code != http.StatusNotFound {
		t.Fatalf("Bob deleting Alice's appointment: expected 404, got %d", code)
	}

	decodeJSON(t, doRequest(t, h, http.MethodGet, "/api/appointments", alice, nil), &aliceList)
	if len(aliceList["appointments"].([]interface{})) != 1 {
		t.Fatalf("Alice's appointment should be untouched")
	}
}

func TestAppointmentsRequireAuth(t *testing.T) {
	h := newTestServer(t)
	if code := doRequest(t, h, http.MethodGet, "/api/appointments", "", nil).Code; code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", code)
	}
	if code := doRequest(t, h, http.MethodPost, "/api/appointments", "", map[string]interface{}{"title": "x", "startsAt": "2026-10-01T14:00:00Z"}).Code; code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", code)
	}
}

func TestAppointmentsCanHaveAnEndTimeAndBeAllDay(t *testing.T) {
	h := newTestServer(t)
	token, _ := registerUser(t, h, map[string]interface{}{"name": "Jane Doe"})
	post := func(body map[string]interface{}) (int, map[string]interface{}) {
		rec := doRequest(t, h, http.MethodPost, "/api/appointments", token, body)
		var out map[string]interface{}
		decodeJSON(t, rec, &out)
		return rec.Code, out
	}

	// An old-style appointment (no end, not all day) still works.
	code, out := post(map[string]interface{}{"title": "Check-in", "startsAt": "2026-10-01T14:00:00Z"})
	plain := out["appointment"].(map[string]interface{})
	if code != http.StatusCreated || plain["endsAt"] != nil || plain["allDay"] != false {
		t.Fatalf("plain appointment: got %d %v", code, plain)
	}

	code, out = post(map[string]interface{}{"title": "DDS", "startsAt": "2026-10-01T14:00:00Z", "endsAt": "2026-10-01T15:30:00Z"})
	timed := out["appointment"].(map[string]interface{})
	if code != http.StatusCreated || timed["endsAt"] != "2026-10-01T15:30:00Z" {
		t.Fatalf("timed appointment: got %d %v", code, timed)
	}

	code, out = post(map[string]interface{}{"title": "Court date", "startsAt": "2026-10-02T04:00:00Z", "allDay": true})
	allDay := out["appointment"].(map[string]interface{})
	if code != http.StatusCreated || allDay["allDay"] != true {
		t.Fatalf("all-day appointment: got %d %v", code, allDay)
	}

	// The end has to come after the start, at creation and when edited.
	if code, _ := post(map[string]interface{}{"title": "Backwards", "startsAt": "2026-10-01T14:00:00Z", "endsAt": "2026-10-01T13:00:00Z"}); code != http.StatusBadRequest {
		t.Fatalf("end before start: expected 400, got %d", code)
	}
	if code, _ := post(map[string]interface{}{"title": "Junk", "startsAt": "2026-10-01T14:00:00Z", "endsAt": "tomorrow"}); code != http.StatusBadRequest {
		t.Fatalf("bad end: expected 400, got %d", code)
	}
	id := timed["id"].(string)
	rec := doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, token, map[string]interface{}{"startsAt": "2026-10-01T16:00:00Z"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("moving the start past the end: expected 400, got %d", rec.Code)
	}

	// Moving both works, and a blank end clears it.
	rec = doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, token, map[string]interface{}{
		"startsAt": "2026-10-01T16:00:00Z", "endsAt": "2026-10-01T17:00:00Z",
	})
	var moved map[string]interface{}
	decodeJSON(t, rec, &moved)
	if rec.Code != http.StatusOK || moved["appointment"].(map[string]interface{})["endsAt"] != "2026-10-01T17:00:00Z" {
		t.Fatalf("move: got %d %v", rec.Code, moved)
	}
	rec = doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, token, map[string]interface{}{"endsAt": ""})
	var cleared map[string]interface{}
	decodeJSON(t, rec, &cleared)
	if rec.Code != http.StatusOK || cleared["appointment"].(map[string]interface{})["endsAt"] != nil {
		t.Fatalf("clearing the end: got %d %v", rec.Code, cleared)
	}
	rec = doRequest(t, h, http.MethodPatch, "/api/appointments/"+id, token, map[string]interface{}{"allDay": true})
	var flagged map[string]interface{}
	decodeJSON(t, rec, &flagged)
	if flagged["appointment"].(map[string]interface{})["allDay"] != true {
		t.Fatalf("turning on all-day: got %v", flagged)
	}
}
