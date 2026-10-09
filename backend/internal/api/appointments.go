package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

// A participant's own appointments — private to them alone. Unlike location
// or documents, staff have no endpoint that can ever see this table.

type appointmentJSON struct {
	ID       string  `json:"id"`
	Title    string  `json:"title"`
	Notes    *string `json:"notes"`
	Location *string `json:"location"`
	StartsAt string  `json:"startsAt"`
	EndsAt   *string `json:"endsAt"`
	AllDay   bool    `json:"allDay"`
	// appointment (something to attend, can ask for a ride) | event (their own).
	Kind string `json:"kind"`
	// True while there is an open or matched ride request for this appointment.
	NeedsRide bool   `json:"needsRide"`
	CreatedAt string `json:"createdAt"`
}

const appointmentColumns = `id, title_encrypted, notes_encrypted, location_encrypted, starts_at, ends_at, all_day, kind, created_at`

func scanAppointment(row interface {
	Scan(dest ...interface{}) error
}) (appointmentJSON, error) {
	var a appointmentJSON
	var titleEnc, notesEnc, locationEnc []byte
	if err := row.Scan(&a.ID, &titleEnc, &notesEnc, &locationEnc, &a.StartsAt, &a.EndsAt, &a.AllDay, &a.Kind, &a.CreatedAt); err != nil {
		return a, err
	}
	title, err := cryptox.DecryptString(titleEnc)
	if err != nil {
		return a, err
	}
	if title != nil {
		a.Title = *title
	}
	notes, err := cryptox.DecryptString(notesEnc)
	if err != nil {
		return a, err
	}
	a.Notes = notes
	location, err := cryptox.DecryptString(locationEnc)
	if err != nil {
		return a, err
	}
	a.Location = location
	return a, nil
}

type createAppointmentRequest struct {
	Title    string  `json:"title"`
	Notes    *string `json:"notes"`
	Location *string `json:"location"`
	StartsAt string  `json:"startsAt"`
	EndsAt   *string `json:"endsAt"`
	AllDay   bool    `json:"allDay"`
	Kind     string  `json:"kind"`
	// "I need a ride": volunteers and admins see a ride request for this one.
	NeedsRide bool `json:"needsRide"`
}

var appointmentKinds = []string{"appointment", "event"}

// checkEnd validates an optional end time: a real date-time, after the start.
// A blank end means "no end time".
func checkEnd(startsAt string, endsAt *string) (*string, string) {
	if endsAt == nil || strings.TrimSpace(*endsAt) == "" {
		return nil, ""
	}
	end, err := time.Parse(time.RFC3339, *endsAt)
	if err != nil {
		return nil, "endsAt must be an ISO 8601 date-time"
	}
	start, err := time.Parse(time.RFC3339, startsAt)
	if err != nil {
		return nil, "startsAt must be an ISO 8601 date-time"
	}
	if !end.After(start) {
		return nil, "The end has to be after the start."
	}
	return endsAt, ""
}

func (s *Server) handleCreateAppointment(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	var body createAppointmentRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}

	title := strings.TrimSpace(body.Title)
	if title == "" {
		writeError(w, http.StatusBadRequest, "title is required")
		return
	}
	if _, err := time.Parse(time.RFC3339, body.StartsAt); err != nil {
		writeError(w, http.StatusBadRequest, "startsAt must be an ISO 8601 date-time")
		return
	}

	endsAt, problem := checkEnd(body.StartsAt, body.EndsAt)
	if problem != "" {
		writeError(w, http.StatusBadRequest, problem)
		return
	}
	kind := body.Kind
	if kind == "" {
		kind = "appointment"
	}
	if !contains(appointmentKinds, kind) {
		writeError(w, http.StatusBadRequest, "kind must be appointment or event")
		return
	}
	if body.NeedsRide && kind != "appointment" {
		writeError(w, http.StatusBadRequest, "Only an appointment can have a ride.")
		return
	}

	titleEnc, err := cryptox.EncryptString(&title)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	notesEnc, err := cryptox.EncryptString(trimmedOrNil(body.Notes))
	if err != nil {
		writeInternalError(w, err)
		return
	}
	locationEnc, err := cryptox.EncryptString(trimmedOrNil(body.Location))
	if err != nil {
		writeInternalError(w, err)
		return
	}

	row := s.db.QueryRow(
		`INSERT INTO appointments (user_id, title_encrypted, notes_encrypted, location_encrypted, starts_at, ends_at, all_day, kind)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 RETURNING `+appointmentColumns,
		u.ID, titleEnc, notesEnc, locationEnc, body.StartsAt, endsAt, body.AllDay, kind,
	)
	appt, err := scanAppointment(row)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if body.NeedsRide {
		if status, msg, err := s.setRide(u.ID, appt.ID, true, appt.AllDay); err != nil {
			writeInternalError(w, err)
			return
		} else if status != 0 {
			// The appointment is saved; only the ride wasn't, and they're told why.
			_, _ = s.db.Exec(`DELETE FROM appointments WHERE id = ?`, appt.ID)
			writeError(w, status, msg)
			return
		}
		appt.NeedsRide = true
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{"appointment": appt})
}

func (s *Server) handleListAppointments(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT `+appointmentColumns+`
		 FROM appointments WHERE user_id = ? ORDER BY starts_at ASC`,
		u.ID,
	)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	appointments := []appointmentJSON{}
	for rows.Next() {
		appt, err := scanAppointment(rows)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		appointments = append(appointments, appt)
	}
	rows.Close()
	rides := s.activeRideAppointments(u.ID)
	for i := range appointments {
		appointments[i].NeedsRide = rides[appointments[i].ID]
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"appointments": appointments})
}

type updateAppointmentRequest struct {
	Title    *string `json:"title"`
	Notes    *string `json:"notes"`
	Location *string `json:"location"`
	StartsAt *string `json:"startsAt"`
	// An empty endsAt clears the end time.
	EndsAt    *string `json:"endsAt"`
	AllDay    *bool   `json:"allDay"`
	Kind      *string `json:"kind"`
	NeedsRide *bool   `json:"needsRide"`
}

func (s *Server) handleUpdateAppointment(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")

	var body updateAppointmentRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}

	var titleEnc, notesEnc, locationEnc []byte
	var startsAt string
	var endsAt *string
	var allDay bool
	var oldStart, kind string
	err := s.db.QueryRow(
		`SELECT title_encrypted, notes_encrypted, location_encrypted, starts_at, ends_at, all_day, kind FROM appointments WHERE id = ? AND user_id = ?`,
		id, u.ID,
	).Scan(&titleEnc, &notesEnc, &locationEnc, &startsAt, &endsAt, &allDay, &kind)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	oldStart = startsAt

	if body.Title != nil {
		title := strings.TrimSpace(*body.Title)
		if title == "" {
			writeError(w, http.StatusBadRequest, "title cannot be empty")
			return
		}
		if titleEnc, err = cryptox.EncryptString(&title); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	if body.Notes != nil {
		if notesEnc, err = cryptox.EncryptString(trimmedOrNil(body.Notes)); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	if body.Location != nil {
		if locationEnc, err = cryptox.EncryptString(trimmedOrNil(body.Location)); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	if body.StartsAt != nil {
		if _, err := time.Parse(time.RFC3339, *body.StartsAt); err != nil {
			writeError(w, http.StatusBadRequest, "startsAt must be an ISO 8601 date-time")
			return
		}
		startsAt = *body.StartsAt
	}
	if body.EndsAt != nil {
		endsAt = body.EndsAt
	}
	if body.AllDay != nil {
		allDay = *body.AllDay
	}
	if body.Kind != nil {
		if !contains(appointmentKinds, *body.Kind) {
			writeError(w, http.StatusBadRequest, "kind must be appointment or event")
			return
		}
		kind = *body.Kind
	}
	// Whatever changed, the end still has to come after the start.
	endsAt, problem := checkEnd(startsAt, endsAt)
	if problem != "" {
		writeError(w, http.StatusBadRequest, problem)
		return
	}

	row := s.db.QueryRow(
		`UPDATE appointments SET title_encrypted = ?, notes_encrypted = ?, location_encrypted = ?, starts_at = ?, ends_at = ?, all_day = ?, kind = ?
		 WHERE id = ? AND user_id = ?
		 RETURNING `+appointmentColumns,
		titleEnc, notesEnc, locationEnc, startsAt, endsAt, allDay, kind, id, u.ID,
	)
	appt, err := scanAppointment(row)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	// An all-day appointment can't have a ride; otherwise follow what they asked.
	want := s.rideActive(appt.ID)
	if body.NeedsRide != nil {
		want = *body.NeedsRide
	}
	if appt.AllDay && want && body.NeedsRide != nil {
		writeError(w, http.StatusBadRequest, "A ride needs a start time, so it can't be an all-day appointment.")
		return
	}
	if appt.Kind != "appointment" && want && body.NeedsRide != nil && *body.NeedsRide {
		writeError(w, http.StatusBadRequest, "Only an appointment can have a ride.")
		return
	}
	// An all-day item, or an event, has no ride; one that had one loses it.
	if appt.AllDay || appt.Kind != "appointment" {
		want = false
	}
	if status, msg, err := s.setRide(u.ID, appt.ID, want, appt.AllDay); err != nil {
		writeInternalError(w, err)
		return
	} else if status != 0 {
		writeError(w, status, msg)
		return
	}
	appt.NeedsRide = want
	// If the time moved on a ride that has a volunteer, they need to know.
	if want && body.StartsAt != nil && *body.StartsAt != oldStart {
		s.notifyRideChange(appt.ID, "The time of a ride changed", "Open the Help tab to see the new time.")
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"appointment": appt})
}

func (s *Server) handleDeleteAppointment(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")

	// Deleting the appointment cancels any ride that was asked for it.
	if _, _, err := s.setRide(u.ID, id, false, false); err != nil {
		writeInternalError(w, err)
		return
	}
	res, err := s.db.Exec(`DELETE FROM appointments WHERE id = ? AND user_id = ?`, id, u.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

// trimmedOrNil turns a provided-but-blank optional field into nil (so it's
// stored as genuinely absent, not an encrypted empty string), matching how
// clearing an optional profile field already works.
func trimmedOrNil(s *string) *string {
	if s == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*s)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

// rideActive is true while an appointment has a ride request still open or
// matched with a volunteer.
func (s *Server) rideActive(apptID string) bool {
	var n int
	_ = s.db.QueryRow(`SELECT COUNT(*) FROM help_requests WHERE appointment_id = ? AND category = 'ride' AND status != 'done'`, apptID).Scan(&n)
	return n > 0
}

func (s *Server) activeRideAppointments(userID string) map[string]bool {
	out := map[string]bool{}
	rows, err := s.db.Query(`SELECT appointment_id FROM help_requests WHERE user_id = ? AND category = 'ride' AND status != 'done' AND appointment_id IS NOT NULL`, userID)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			out[id] = true
		}
	}
	return out
}

// setRide makes the ride request for an appointment match what the person
// wants: on creates one (and tells the volunteers and admins), off removes it
// and tells any volunteer who had taken it. It returns an HTTP status and
// message when the person should be told why it didn't work.
func (s *Server) setRide(userID, apptID string, want, allDay bool) (int, string, error) {
	active := s.rideActive(apptID)
	if want && !active {
		if allDay {
			return http.StatusBadRequest, "A ride needs a start time, so it can't be an all-day appointment.", nil
		}
		if _, err := s.insertHelpRequest(userID, "ride", nil, apptID, nil); err == errTooManyRequests {
			return http.StatusConflict, "You already have several open requests. Mark some as done first.", nil
		} else if err != nil {
			return 0, "", err
		}
		return 0, "", nil
	}
	if !want && active {
		s.notifyRideChange(apptID, "A ride was cancelled", "The person no longer needs it. Open the Help tab.")
		if _, err := s.db.Exec(`DELETE FROM help_requests WHERE appointment_id = ? AND category = 'ride' AND status != 'done'`, apptID); err != nil {
			return 0, "", err
		}
	}
	return 0, "", nil
}

// notifyRideChange tells the volunteer matched to an appointment's ride, if
// there is one. Alerts name no one.
func (s *Server) notifyRideChange(apptID, title, body string) {
	var volunteerID sql.NullString
	err := s.db.QueryRow(`SELECT claimed_by FROM help_requests WHERE appointment_id = ? AND category = 'ride' AND status = 'claimed'`, apptID).Scan(&volunteerID)
	if err != nil || !volunteerID.Valid {
		return
	}
	s.notifyUser(volunteerID.String, push.Notification{Title: title, Body: body, Data: map[string]string{"kind": "help"}})
}
