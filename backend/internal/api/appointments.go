package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"ground-to-growth-connect-backend/internal/cryptox"
)

// A participant's own appointments — private to them alone. Unlike location
// or documents, staff have no endpoint that can ever see this table.

type appointmentJSON struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Notes     *string `json:"notes"`
	Location  *string `json:"location"`
	StartsAt  string  `json:"startsAt"`
	CreatedAt string  `json:"createdAt"`
}

func scanAppointment(row interface {
	Scan(dest ...interface{}) error
}) (appointmentJSON, error) {
	var a appointmentJSON
	var titleEnc, notesEnc, locationEnc []byte
	if err := row.Scan(&a.ID, &titleEnc, &notesEnc, &locationEnc, &a.StartsAt, &a.CreatedAt); err != nil {
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
		`INSERT INTO appointments (user_id, title_encrypted, notes_encrypted, location_encrypted, starts_at)
		 VALUES (?, ?, ?, ?, ?)
		 RETURNING id, title_encrypted, notes_encrypted, location_encrypted, starts_at, created_at`,
		u.ID, titleEnc, notesEnc, locationEnc, body.StartsAt,
	)
	appt, err := scanAppointment(row)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{"appointment": appt})
}

func (s *Server) handleListAppointments(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT id, title_encrypted, notes_encrypted, location_encrypted, starts_at, created_at
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

	writeJSON(w, http.StatusOK, map[string]interface{}{"appointments": appointments})
}

type updateAppointmentRequest struct {
	Title    *string `json:"title"`
	Notes    *string `json:"notes"`
	Location *string `json:"location"`
	StartsAt *string `json:"startsAt"`
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
	err := s.db.QueryRow(
		`SELECT title_encrypted, notes_encrypted, location_encrypted, starts_at FROM appointments WHERE id = ? AND user_id = ?`,
		id, u.ID,
	).Scan(&titleEnc, &notesEnc, &locationEnc, &startsAt)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}

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

	row := s.db.QueryRow(
		`UPDATE appointments SET title_encrypted = ?, notes_encrypted = ?, location_encrypted = ?, starts_at = ?
		 WHERE id = ? AND user_id = ?
		 RETURNING id, title_encrypted, notes_encrypted, location_encrypted, starts_at, created_at`,
		titleEnc, notesEnc, locationEnc, startsAt, id, u.ID,
	)
	appt, err := scanAppointment(row)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"appointment": appt})
}

func (s *Server) handleDeleteAppointment(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")

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
