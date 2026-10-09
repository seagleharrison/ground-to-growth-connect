package api

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

var helpCategories = []string{"food", "shelter", "ride", "documents", "clothing", "health", "work", "other", "supplies"}

const (
	maxHelpNoteRunes     = 140
	maxActiveHelpPerUser = 10
)

type helpAppointmentJSON struct {
	ID       string  `json:"id"`
	Title    string  `json:"title"`
	Location *string `json:"location"`
	StartsAt string  `json:"startsAt"`
}

// helpRequestJSON is what the person who asked sees: their own request, who
// (by first name) has said they're helping, and the appointment they attached.
type helpRequestJSON struct {
	ID          string               `json:"id"`
	Category    string               `json:"category"`
	Note        *string              `json:"note"`
	Status      string               `json:"status"`
	CreatedAt   string               `json:"createdAt"`
	ClaimedAt   *string              `json:"claimedAt"`
	HelperName  *string              `json:"helperName"`
	Appointment *helpAppointmentJSON `json:"appointment"`
	// A "supplies" request lists the basic items asked for (codes from supplyItems).
	Items []string `json:"items,omitempty"`
	// Where a match is up to, from the helper's taps: on_my_way | arrived | late | ready.
	Progress        *string `json:"progress"`
	ProgressAt      *string `json:"progressAt"`
	ProgressMinutes *int    `json:"progressMinutes"`
	// How it went, from the person helped (1 or -1). Admins see everyone's;
	// a person sees only their own; volunteers never see it.
	Rating *int `json:"rating"`
}

// staffHelpRequestJSON is the volunteer/admin view: the same plus who asked.
type staffHelpRequestJSON struct {
	helpRequestJSON
	UserID      string `json:"userId"`
	Name        string `json:"name"`
	ClaimedByMe bool   `json:"claimedByMe"`
}

const helpRequestSelect = `
	SELECT hr.id, hr.user_id, u.name_encrypted, hr.category, hr.note_encrypted, hr.status,
	       hr.created_at, hr.claimed_at, hr.claimed_by, h.name_encrypted,
	       a.id, a.title_encrypted, a.location_encrypted, a.starts_at,
	       hr.progress, hr.progress_at, hr.progress_minutes, hr.rating, hr.items
	FROM help_requests hr
	JOIN users u ON u.id = hr.user_id
	LEFT JOIN users h ON h.id = hr.claimed_by
	LEFT JOIN appointments a ON a.id = hr.appointment_id`

func firstName(full string) string {
	if parts := strings.Fields(full); len(parts) > 0 {
		return parts[0]
	}
	return full
}

func scanHelpRequest(row interface {
	Scan(dest ...interface{}) error
}, viewerID string) (staffHelpRequestJSON, error) {
	var r staffHelpRequestJSON
	var nameEnc, noteEnc, helperEnc, apptTitleEnc, apptLocEnc []byte
	var claimedAt, claimedBy, apptID, apptStarts, progress, progressAt, itemsJSON sql.NullString
	var progressMinutes, rating sql.NullInt64
	if err := row.Scan(&r.ID, &r.UserID, &nameEnc, &r.Category, &noteEnc, &r.Status,
		&r.CreatedAt, &claimedAt, &claimedBy, &helperEnc,
		&apptID, &apptTitleEnc, &apptLocEnc, &apptStarts,
		&progress, &progressAt, &progressMinutes, &rating, &itemsJSON); err != nil {
		return r, err
	}
	if rating.Valid {
		v := int(rating.Int64)
		r.Rating = &v
	}
	// A request with items is a supplies request, however it is stored.
	if itemsJSON.Valid && itemsJSON.String != "" {
		var items []string
		if json.Unmarshal([]byte(itemsJSON.String), &items) == nil && len(items) > 0 {
			r.Items = items
			r.Category = "supplies"
		}
	}
	name, err := cryptox.DecryptString(nameEnc)
	if err != nil {
		return r, err
	}
	if name != nil {
		r.Name = *name
	}
	if r.Note, err = cryptox.DecryptString(noteEnc); err != nil {
		return r, err
	}

	// If whoever claimed it has since left, it goes back to the board.
	if r.Status == "claimed" && !claimedBy.Valid {
		r.Status = "open"
	}
	// Who helped stays known once it's done, so the person can rate it.
	if r.Status == "done" && claimedBy.Valid {
		if helper, err := cryptox.DecryptString(helperEnc); err != nil {
			return r, err
		} else if helper != nil {
			first := firstName(*helper)
			r.HelperName = &first
		}
	}
	if r.Status == "claimed" {
		r.ClaimedAt = toPtr(claimedAt)
		r.ClaimedByMe = claimedBy.String == viewerID
		r.Progress = toPtr(progress)
		r.ProgressAt = toPtr(progressAt)
		if progressMinutes.Valid {
			m := int(progressMinutes.Int64)
			r.ProgressMinutes = &m
		}
		if helper, err := cryptox.DecryptString(helperEnc); err != nil {
			return r, err
		} else if helper != nil {
			first := firstName(*helper)
			r.HelperName = &first
		}
	}

	if apptID.Valid {
		title, err := cryptox.DecryptString(apptTitleEnc)
		if err != nil {
			return r, err
		}
		loc, err := cryptox.DecryptString(apptLocEnc)
		if err != nil {
			return r, err
		}
		a := &helpAppointmentJSON{ID: apptID.String, Location: loc, StartsAt: apptStarts.String}
		if title != nil {
			a.Title = *title
		}
		r.Appointment = a
	}
	return r, nil
}

func (s *Server) loadHelpRequests(viewerID, where string, args ...interface{}) ([]staffHelpRequestJSON, error) {
	rows, err := s.db.Query(helpRequestSelect+" "+where, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []staffHelpRequestJSON{}
	for rows.Next() {
		r, err := scanHelpRequest(rows, viewerID)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Server) loadHelpRequest(viewerID, id string) (*staffHelpRequestJSON, error) {
	rs, err := s.loadHelpRequests(viewerID, "WHERE hr.id = ?", id)
	if err != nil || len(rs) == 0 {
		return nil, err
	}
	return &rs[0], nil
}

type createHelpRequest struct {
	Category      string   `json:"category"`
	Note          *string  `json:"note"`
	AppointmentID *string  `json:"appointmentId"`
	Items         []string `json:"items"`
}

func (s *Server) handleCreateHelpRequest(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	var body createHelpRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	if !contains(helpCategories, body.Category) {
		writeError(w, http.StatusBadRequest, "category must be one of: "+strings.Join(helpCategories, ", "))
		return
	}
	note := trimmedOrNil(body.Note)
	if note != nil && utf8.RuneCountInString(*note) > maxHelpNoteRunes {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("Keep the note short: up to %d characters.", maxHelpNoteRunes))
		return
	}
	// Basic items are picked from a list, never typed.
	var itemsArg interface{}
	if body.Category == "supplies" {
		items, problem := cleanSupplyItems(body.Items)
		if problem != "" {
			writeError(w, http.StatusBadRequest, problem)
			return
		}
		raw, _ := json.Marshal(items)
		itemsArg = string(raw)
	} else if len(body.Items) > 0 {
		writeError(w, http.StatusBadRequest, "Items can only be asked for in a supplies request.")
		return
	}
	// A ride is always to something on the calendar, so nobody has to type
	// an address or time.
	if body.Category == "ride" && (body.AppointmentID == nil || *body.AppointmentID == "") {
		writeError(w, http.StatusBadRequest, "Pick the appointment you need a ride to.")
		return
	}

	var apptArg interface{}
	if body.AppointmentID != nil && *body.AppointmentID != "" {
		var owned int
		err := s.db.QueryRow(`SELECT COUNT(*) FROM appointments WHERE id = ? AND user_id = ?`, *body.AppointmentID, u.ID).Scan(&owned)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if owned == 0 {
			writeError(w, http.StatusBadRequest, "That appointment wasn't found")
			return
		}
		apptArg = *body.AppointmentID
	}

	noteEnc, err := cryptox.EncryptString(note)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	id, err := s.insertHelpRequest(u.ID, body.Category, noteEnc, apptArg, itemsArg)
	if err == errTooManyRequests {
		writeError(w, http.StatusConflict, "You already have several open requests. Mark some as done first.")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	req, err := s.loadHelpRequest(u.ID, id)
	if err != nil || req == nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"request": req.helpRequestJSON})
}

var errTooManyRequests = errors.New("too many open requests")

// insertHelpRequest saves a request and tells the staff who can act on it.
// Volunteers this person blocked aren't told.
func (s *Server) insertHelpRequest(ownerID, category string, noteEnc []byte, apptArg, itemsArg interface{}) (string, error) {
	var active int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM help_requests WHERE user_id = ? AND status != 'done'`, ownerID).Scan(&active); err != nil {
		return "", err
	}
	if active >= maxActiveHelpPerUser {
		return "", errTooManyRequests
	}
	var id string
	if err := s.db.QueryRow(
		`INSERT INTO help_requests (user_id, category, note_encrypted, appointment_id, items) VALUES (?, ?, ?, ?, ?) RETURNING id`,
		ownerID, storedCategory(category), noteEnc, apptArg, itemsArg,
	).Scan(&id); err != nil {
		return "", err
	}
	var targets []string
	for _, staffID := range s.staffToNotify() {
		if blocked, _ := s.isBlocked(ownerID, staffID); !blocked && staffID != ownerID {
			targets = append(targets, staffID)
		}
	}
	body := "Someone asked for help. Open the Help tab to see."
	switch category {
	case "ride":
		body = "Someone needs a ride. Open the Help tab to see."
	case "supplies":
		body = "Someone asked for basic items. Open the Help tab to see."
	}
	s.notifyUsers(targets, push.Notification{
		Title: "New request for help",
		Body:  body,
		Data:  map[string]string{"kind": "help"},
	})
	return id, nil
}

func (s *Server) handleMyHelpRequests(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rs, err := s.loadHelpRequests(u.ID, "WHERE hr.user_id = ? ORDER BY hr.created_at DESC LIMIT 50", u.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	mine := make([]helpRequestJSON, 0, len(rs))
	for _, x := range rs {
		mine = append(mine, x.helpRequestJSON)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"requests": mine})
}

// handleHelpBoard is the volunteer/admin list: everything still open or being
// handled. What I'm already helping with comes first, then what has waited
// longest.
func (s *Server) handleHelpBoard(w http.ResponseWriter, r *http.Request) {
	viewer := userFromCtx(r)
	rs, err := s.loadHelpRequests(viewer.ID,
		`WHERE hr.status != 'done'
		   AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = hr.user_id AND b.blocked_id = ?)
		 ORDER BY hr.created_at ASC`, viewer.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	rank := func(x staffHelpRequestJSON) int {
		switch {
		case x.ClaimedByMe:
			return 0
		case x.Status == "open":
			return 1
		default:
			return 2
		}
	}
	// Mine first, then what's still open, and within each: rides, soonest
	// appointment first, then everything else by how long it has waited.
	soonest := func(x staffHelpRequestJSON) string {
		if x.Category == "ride" && x.Appointment != nil {
			return x.Appointment.StartsAt
		}
		return ""
	}
	sort.SliceStable(rs, func(i, j int) bool {
		if ri, rj := rank(rs[i]), rank(rs[j]); ri != rj {
			return ri < rj
		}
		ai, aj := soonest(rs[i]), soonest(rs[j])
		if (ai != "") != (aj != "") {
			return ai != ""
		}
		return ai != "" && ai < aj
	})
	hideRatingsFromVolunteers(rs, viewer)
	writeJSON(w, http.StatusOK, map[string]interface{}{"requests": rs})
}

func (s *Server) respondStaffHelpRequest(w http.ResponseWriter, viewerID, id string) {
	req, err := s.loadHelpRequest(viewerID, id)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if req == nil {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	one := []staffHelpRequestJSON{*req}
	if viewer, err := s.loadPerson(viewerID); err == nil && viewer != nil {
		hideRatingsFromVolunteers(one, &authUser{ID: viewerID, PersonType: viewer.Type})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"request": one[0]})
}

func nowStamp() string { return time.Now().UTC().Format("2006-01-02T15:04:05.000Z") }

// handleClaimHelpRequest is "I can help": an approved volunteer or an admin
// accepts the request, and the person is told someone is coming.
func (s *Server) handleClaimHelpRequest(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	if u.MessagingDisabled {
		writeError(w, http.StatusForbidden, "Your volunteer account is paused. Please contact Ground to Growth.")
		return
	}
	res, err := s.db.Exec(
		`UPDATE help_requests SET status = 'claimed', claimed_by = ?, claimed_at = ?, progress = NULL, progress_at = NULL, progress_minutes = NULL
		 WHERE id = ? AND (status = 'open' OR (status = 'claimed' AND claimed_by IS NULL))
		   AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = help_requests.user_id AND b.blocked_id = ?)`,
		u.ID, nowStamp(), id, u.ID,
	)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		existing, err := s.loadHelpRequest(u.ID, id)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if existing == nil {
			writeError(w, http.StatusNotFound, "Not found")
			return
		}
		if existing.ClaimedByMe {
			s.respondStaffHelpRequest(w, u.ID, id) // already yours: nothing to do
			return
		}
		if blocked, err := s.isBlocked(existing.UserID, u.ID); err != nil {
			writeInternalError(w, err)
			return
		} else if blocked {
			writeError(w, http.StatusNotFound, "Not found")
			return
		}
		writeError(w, http.StatusConflict, "Someone else is already helping with this.")
		return
	}
	var ownerID string
	if err := s.db.QueryRow(`SELECT user_id FROM help_requests WHERE id = ?`, id).Scan(&ownerID); err == nil {
		s.notifyUser(ownerID, push.Notification{
			Title: "Help is on the way",
			Body:  "A volunteer is helping with your request.",
			Data:  map[string]string{"kind": "help-claimed"},
		})
	}
	s.respondStaffHelpRequest(w, u.ID, id)
}

func (s *Server) handleReleaseHelpRequest(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	// Admins can free up a request someone else claimed and went quiet on.
	query := `UPDATE help_requests SET status = 'open', claimed_by = NULL, claimed_at = NULL, progress = NULL, progress_at = NULL, progress_minutes = NULL
	          WHERE id = ? AND status = 'claimed' AND claimed_by = ?`
	args := []interface{}{id, u.ID}
	if u.PersonType == "admin" {
		query = `UPDATE help_requests SET status = 'open', claimed_by = NULL, claimed_at = NULL, progress = NULL, progress_at = NULL, progress_minutes = NULL
		         WHERE id = ? AND status = 'claimed'`
		args = []interface{}{id}
	}
	res, err := s.db.Exec(query, args...)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	s.respondStaffHelpRequest(w, u.ID, id)
}

// handleCompleteHelpRequest closes a request. The person who asked can always
// close their own ("I'm all set"); staff can close one they claimed, and an
// admin can close any.
func (s *Server) handleCompleteHelpRequest(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")

	var ownerID string
	var claimedBy sql.NullString
	err := s.db.QueryRow(`SELECT user_id, claimed_by FROM help_requests WHERE id = ?`, id).Scan(&ownerID, &claimedBy)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	allowed := ownerID == u.ID ||
		(u.canActAsStaff() && (claimedBy.String == u.ID || u.PersonType == "admin"))
	if !allowed {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if _, err := s.db.Exec(`UPDATE help_requests SET status = 'done', completed_at = ? WHERE id = ?`, nowStamp(), id); err != nil {
		writeInternalError(w, err)
		return
	}
	if ownerID == u.ID {
		req, err := s.loadHelpRequest(u.ID, id)
		if err != nil || req == nil {
			writeInternalError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]interface{}{"request": req.helpRequestJSON})
		return
	}
	s.respondStaffHelpRequest(w, u.ID, id)
}

func (s *Server) handleDeleteHelpRequest(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	res, err := s.db.Exec(`DELETE FROM help_requests WHERE id = ? AND user_id = ?`, r.PathValue("id"), u.ID)
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
