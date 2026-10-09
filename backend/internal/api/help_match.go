package api

import (
	"database/sql"
	"encoding/json"
	"net/http"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

// What happens after a volunteer (or admin) accepts a request, without any
// typing between the two of them:
//
//	taps                    -> on my way, arrived, running late, can't make it,
//	                           "I don't feel safe", done
//	person rates it         -> thumbs up or down, seen by admins only

// volunteerRatings counts the thumbs a volunteer has earned.
func (s *Server) volunteerRatings(volunteerID string) (up, down int) {
	_ = s.db.QueryRow(
		`SELECT COALESCE(SUM(rating = 1), 0), COALESCE(SUM(rating = -1), 0) FROM help_requests WHERE claimed_by = ? AND rating IS NOT NULL`,
		volunteerID,
	).Scan(&up, &down)
	return up, down
}

// hideRatingsFromVolunteers keeps how a match was rated between the person
// and the admins: a volunteer never sees ratings, their own or anyone's.
func hideRatingsFromVolunteers(rs []staffHelpRequestJSON, viewer *authUser) {
	if viewer.PersonType == "admin" {
		return
	}
	for i := range rs {
		rs[i].Rating = nil
	}
}

func (s *Server) logHelpEvent(requestID, actorID, kind string) {
	_, _ = s.db.Exec(`INSERT INTO help_events (request_id, actor_id, kind) VALUES (?, ?, ?)`, requestID, actorID, kind)
}

type progressRequest struct {
	Kind    string `json:"kind"`
	Minutes *int   `json:"minutes"`
}

var lateMinutes = map[int]bool{10: true, 20: true, 30: true, 45: true, 60: true}

// handleHelpProgress takes the one-tap updates during a match. Only the
// volunteer on the request can say on_my_way / arrived / running_late /
// cant_make_it; either side can press "I don't feel safe" (unsafe).
func (s *Server) handleHelpProgress(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	var body progressRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}

	var ownerID, status string
	var claimedBy, itemsJSON sql.NullString
	err := s.db.QueryRow(`SELECT user_id, status, claimed_by, items FROM help_requests WHERE id = ?`, id).Scan(&ownerID, &status, &claimedBy, &itemsJSON)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	isOwner := ownerID == u.ID
	isHelper := claimedBy.Valid && claimedBy.String == u.ID && u.canActAsStaff()
	if !isOwner && !isHelper {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if status != "claimed" || !claimedBy.Valid {
		writeError(w, http.StatusConflict, "This isn't matched with a volunteer right now.")
		return
	}

	switch body.Kind {
	case "on_my_way", "arrived", "running_late":
		if !isHelper {
			writeError(w, http.StatusForbidden, "Only the volunteer can send that.")
			return
		}
		progress := body.Kind
		var minutes interface{}
		if body.Kind == "running_late" {
			progress = "late"
			if body.Minutes != nil {
				if !lateMinutes[*body.Minutes] {
					writeError(w, http.StatusBadRequest, "minutes must be 10, 20, 30, 45 or 60")
					return
				}
				minutes = *body.Minutes
			}
		}
		if _, err := s.db.Exec(`UPDATE help_requests SET progress = ?, progress_at = ?, progress_minutes = ? WHERE id = ?`, progress, nowStamp(), minutes, id); err != nil {
			writeInternalError(w, err)
			return
		}
		s.logHelpEvent(id, u.ID, body.Kind)
		text := map[string]string{
			"on_my_way":    "Your volunteer is on the way.",
			"arrived":      "Your volunteer has arrived.",
			"running_late": "Your volunteer is running a little late.",
		}[body.Kind]
		s.notifyUser(ownerID, push.Notification{Title: "Update on your request", Body: text, Data: map[string]string{"kind": "help-progress"}})

	case "ready":
		// For basic items: "your things are ready".
		if !isHelper {
			writeError(w, http.StatusForbidden, "Only the volunteer can send that.")
			return
		}
		if !itemsJSON.Valid || itemsJSON.String == "" {
			writeError(w, http.StatusBadRequest, "Only a request for items can be marked ready.")
			return
		}
		if _, err := s.db.Exec(`UPDATE help_requests SET progress = 'ready', progress_at = ?, progress_minutes = NULL WHERE id = ?`, nowStamp(), id); err != nil {
			writeInternalError(w, err)
			return
		}
		s.logHelpEvent(id, u.ID, "ready")
		s.notifyUser(ownerID, push.Notification{Title: "Update on your request", Body: "Your items are ready.", Data: map[string]string{"kind": "help-progress"}})

	case "cant_make_it":
		if !isHelper {
			writeError(w, http.StatusForbidden, "Only the volunteer can send that.")
			return
		}
		if err := s.releaseClaims(u.ID, ownerID); err != nil {
			writeInternalError(w, err)
			return
		}
		s.logHelpEvent(id, u.ID, "cant_make_it")
		s.notifyUser(ownerID, push.Notification{
			Title: "Your volunteer can't make it",
			Body:  "Your request is back on the board and we're finding someone else.",
			Data:  map[string]string{"kind": "help"},
		})
		s.notifyUsers(s.adminIDsExcept(u.ID), push.Notification{
			Title: "A volunteer can't make it",
			Body:  "A request is open again. Open the Help tab.",
			Data:  map[string]string{"kind": "help"},
		})

	case "unsafe":
		if err := s.raiseSafetyAlert(u, ownerID, claimedBy.String, isOwner); err != nil {
			writeInternalError(w, err)
			return
		}
		s.logHelpEvent(id, u.ID, "unsafe")

	default:
		writeError(w, http.StatusBadRequest, "kind must be on_my_way, arrived, running_late, ready, cant_make_it or unsafe")
		return
	}

	if isOwner {
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

// raiseSafetyAlert is the "I don't feel safe" button: it files a report for
// admins, tells every admin right away, and ends the match. A person pressing
// it also blocks that volunteer, the same as reporting them.
func (s *Server) raiseSafetyAlert(actor *authUser, ownerID, helperID string, actorIsOwner bool) error {
	subject := ownerID
	if actorIsOwner {
		subject = helperID
	}
	reason := "Safety alert: pressed “I don't feel safe” during a match."
	reasonEnc, err := cryptox.EncryptString(&reason)
	if err != nil {
		return err
	}
	if _, err := s.db.Exec(`INSERT INTO reports (reporter_id, subject_id, reason_encrypted) VALUES (?, ?, ?)`, actor.ID, subject, reasonEnc); err != nil {
		return err
	}
	if actorIsOwner {
		if err := s.applyBlock(actor.ID, helperID); err != nil {
			return err
		}
	} else if err := s.releaseClaims(actor.ID, ownerID); err != nil {
		return err
	}
	s.notifyUsers(s.adminIDsExcept(actor.ID), push.Notification{
		Title: "Safety alert",
		Body:  "Someone pressed “I don't feel safe”. Open Safety now.",
		Data:  map[string]string{"kind": "safety"},
	})
	return nil
}

type ratingRequest struct {
	Value int `json:"value"`
}

// handleRateHelp lets the person helped say how it went, once it's done.
func (s *Server) handleRateHelp(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	var body ratingRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || (body.Value != 1 && body.Value != -1) {
		writeError(w, http.StatusBadRequest, "value must be 1 or -1")
		return
	}
	var status string
	var claimedBy sql.NullString
	err := s.db.QueryRow(`SELECT status, claimed_by FROM help_requests WHERE id = ? AND user_id = ?`, id, u.ID).Scan(&status, &claimedBy)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if status != "done" || !claimedBy.Valid {
		writeError(w, http.StatusConflict, "You can rate it once a volunteer has helped and it's done.")
		return
	}
	if _, err := s.db.Exec(`UPDATE help_requests SET rating = ? WHERE id = ?`, body.Value, id); err != nil {
		writeInternalError(w, err)
		return
	}
	req, err := s.loadHelpRequest(u.ID, id)
	if err != nil || req == nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"request": req.helpRequestJSON})
}

type helpHistoryJSON struct {
	ID          string  `json:"id"`
	Category    string  `json:"category"`
	Requester   string  `json:"requester"`
	Helper      *string `json:"helper"`
	Rating      *int    `json:"rating"`
	CompletedAt *string `json:"completedAt"`
}

// handleHelpHistory is the admins' look back at finished requests: who helped
// whom, and how it went.
func (s *Server) handleHelpHistory(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(
		`SELECT hr.id, CASE WHEN hr.items IS NOT NULL AND hr.items != '' THEN 'supplies' ELSE hr.category END, u.name_encrypted, h.name_encrypted, hr.rating, hr.completed_at
		 FROM help_requests hr
		 JOIN users u ON u.id = hr.user_id
		 LEFT JOIN users h ON h.id = hr.claimed_by
		 WHERE hr.status = 'done'
		 ORDER BY hr.completed_at DESC LIMIT 50`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	out := []helpHistoryJSON{}
	for rows.Next() {
		var h helpHistoryJSON
		var reqEnc, helperEnc []byte
		var rating sql.NullInt64
		var completed sql.NullString
		if err := rows.Scan(&h.ID, &h.Category, &reqEnc, &helperEnc, &rating, &completed); err != nil {
			writeInternalError(w, err)
			return
		}
		if name, err := cryptox.DecryptString(reqEnc); err != nil {
			writeInternalError(w, err)
			return
		} else if name != nil {
			h.Requester = *name
		}
		if name, err := cryptox.DecryptString(helperEnc); err != nil {
			writeInternalError(w, err)
			return
		} else if name != nil {
			h.Helper = name
		}
		if rating.Valid {
			v := int(rating.Int64)
			h.Rating = &v
		}
		h.CompletedAt = toPtr(completed)
		out = append(out, h)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"history": out})
}
