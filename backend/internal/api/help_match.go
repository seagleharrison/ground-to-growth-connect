package api

import (
	"database/sql"
	"encoding/json"
	"net/http"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

// Matching a volunteer to a request, and the taps that follow, without any
// typing between the two of them:
//
//	volunteer "I can help"  -> an offer
//	admin approves          -> the match (the person is told someone is coming)
//	taps                    -> on my way, arrived, running late, can't make it,
//	                           "I don't feel safe", done
//	person rates it         -> thumbs up or down, seen by admins only

// offerJSON is what an admin sees about a volunteer waiting to be confirmed.
type offerJSON struct {
	ID            string `json:"id"`
	VolunteerID   string `json:"volunteerId"`
	VolunteerName string `json:"volunteerName"`
	CreatedAt     string `json:"createdAt"`
	ThumbsUp      int    `json:"thumbsUp"`
	ThumbsDown    int    `json:"thumbsDown"`
}

// volunteerRatings counts the thumbs a volunteer has earned.
func (s *Server) volunteerRatings(volunteerID string) (up, down int) {
	_ = s.db.QueryRow(
		`SELECT COALESCE(SUM(rating = 1), 0), COALESCE(SUM(rating = -1), 0) FROM help_requests WHERE claimed_by = ? AND rating IS NOT NULL`,
		volunteerID,
	).Scan(&up, &down)
	return up, down
}

// attachOffers fills in each request's offers for the viewer: an admin sees
// who is waiting to be confirmed, a volunteer sees whether their own offer is
// still waiting. Ratings are for admins only.
func (s *Server) attachOffers(rs []staffHelpRequestJSON, viewer *authUser) error {
	rows, err := s.db.Query(
		`SELECT o.id, o.request_id, o.volunteer_id, u.name_encrypted, o.created_at
		 FROM help_offers o JOIN users u ON u.id = o.volunteer_id
		 WHERE o.status = 'pending' ORDER BY o.created_at ASC`)
	if err != nil {
		return err
	}
	defer rows.Close()
	byRequest := map[string][]offerJSON{}
	mine := map[string]string{}
	for rows.Next() {
		var o offerJSON
		var requestID string
		var nameEnc []byte
		if err := rows.Scan(&o.ID, &requestID, &o.VolunteerID, &nameEnc, &o.CreatedAt); err != nil {
			return err
		}
		name, err := cryptox.DecryptString(nameEnc)
		if err != nil {
			return err
		}
		if name != nil {
			o.VolunteerName = *name
		}
		byRequest[requestID] = append(byRequest[requestID], o)
		if o.VolunteerID == viewer.ID {
			mine[requestID] = o.ID
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for i := range rs {
		r := &rs[i]
		if viewer.PersonType == "admin" {
			offers := byRequest[r.ID]
			for j := range offers {
				offers[j].ThumbsUp, offers[j].ThumbsDown = s.volunteerRatings(offers[j].VolunteerID)
			}
			r.Offers = offers
		} else {
			r.Rating = nil
		}
		if offerID, ok := mine[r.ID]; ok {
			pending := "pending"
			r.MyOffer = &pending
			id := offerID
			r.MyOfferID = &id
		}
	}
	return nil
}

func (s *Server) logHelpEvent(requestID, actorID, kind string) {
	_, _ = s.db.Exec(`INSERT INTO help_events (request_id, actor_id, kind) VALUES (?, ?, ?)`, requestID, actorID, kind)
}

// offerHelp records a volunteer's "I can help" and tells the admins.
func (s *Server) offerHelp(w http.ResponseWriter, u *authUser, id string) {
	req, err := s.loadHelpRequest(u.ID, id)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if req == nil {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if blocked, err := s.isBlocked(req.UserID, u.ID); err != nil {
		writeInternalError(w, err)
		return
	} else if blocked {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if req.ClaimedByMe {
		s.respondStaffHelpRequest(w, u.ID, id) // already matched: nothing to do
		return
	}
	if req.Status != "open" {
		writeError(w, http.StatusConflict, "Someone else is already helping with this.")
		return
	}
	var pending int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM help_offers WHERE request_id = ? AND volunteer_id = ? AND status = 'pending'`, id, u.ID).Scan(&pending); err != nil {
		writeInternalError(w, err)
		return
	}
	if pending == 0 {
		if _, err := s.db.Exec(`INSERT INTO help_offers (request_id, volunteer_id) VALUES (?, ?)`, id, u.ID); err != nil {
			writeInternalError(w, err)
			return
		}
		s.notifyUsers(s.adminIDsExcept(u.ID), push.Notification{
			Title: "A volunteer offered to help",
			Body:  "Open the Help tab to confirm the match.",
			Data:  map[string]string{"kind": "help-offer"},
		})
	}
	s.respondStaffHelpRequest(w, u.ID, id)
}

func (s *Server) handleWithdrawOffer(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	res, err := s.db.Exec(
		`UPDATE help_offers SET status = 'withdrawn', decided_at = ? WHERE id = ? AND volunteer_id = ? AND status = 'pending'`,
		nowStamp(), r.PathValue("id"), u.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleApproveOffer(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	offerID := r.PathValue("id")
	var requestID, volunteerID, status string
	err := s.db.QueryRow(`SELECT request_id, volunteer_id, status FROM help_offers WHERE id = ?`, offerID).Scan(&requestID, &volunteerID, &status)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if status != "pending" {
		writeError(w, http.StatusConflict, "That offer was already handled.")
		return
	}
	vol, err := s.loadPerson(volunteerID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if vol == nil || vol.Type != "volunteer" || !vol.Approved || vol.Disabled {
		writeError(w, http.StatusConflict, "That volunteer can't take this right now.")
		return
	}
	res, err := s.db.Exec(
		`UPDATE help_requests SET status = 'claimed', claimed_by = ?, claimed_at = ?, progress = NULL, progress_at = NULL, progress_minutes = NULL
		 WHERE id = ? AND (status = 'open' OR (status = 'claimed' AND claimed_by IS NULL))
		   AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id = help_requests.user_id AND b.blocked_id = ?)`,
		volunteerID, nowStamp(), requestID, volunteerID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusConflict, "This request isn't open any more.")
		return
	}
	stamp := nowStamp()
	if _, err := s.db.Exec(`UPDATE help_offers SET status = 'approved', decided_at = ?, decided_by = ? WHERE id = ?`, stamp, admin.ID, offerID); err != nil {
		writeInternalError(w, err)
		return
	}
	if _, err := s.db.Exec(`UPDATE help_offers SET status = 'declined', decided_at = ?, decided_by = ? WHERE request_id = ? AND status = 'pending'`, stamp, admin.ID, requestID); err != nil {
		writeInternalError(w, err)
		return
	}
	s.logHelpEvent(requestID, admin.ID, "matched")
	var ownerID string
	if err := s.db.QueryRow(`SELECT user_id FROM help_requests WHERE id = ?`, requestID).Scan(&ownerID); err == nil {
		s.notifyUser(ownerID, push.Notification{
			Title: "Help is on the way",
			Body:  "A volunteer is helping with your request.",
			Data:  map[string]string{"kind": "help-claimed"},
		})
	}
	s.notifyUser(volunteerID, push.Notification{
		Title: "You're matched",
		Body:  "The team confirmed your offer. Open the Help tab for the details.",
		Data:  map[string]string{"kind": "help-approved"},
	})
	s.respondStaffHelpRequest(w, admin.ID, requestID)
}

func (s *Server) handleDeclineOffer(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	var requestID, volunteerID string
	err := s.db.QueryRow(`SELECT request_id, volunteer_id FROM help_offers WHERE id = ? AND status = 'pending'`, r.PathValue("id")).Scan(&requestID, &volunteerID)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if _, err := s.db.Exec(`UPDATE help_offers SET status = 'declined', decided_at = ?, decided_by = ? WHERE id = ?`, nowStamp(), admin.ID, r.PathValue("id")); err != nil {
		writeInternalError(w, err)
		return
	}
	s.notifyUser(volunteerID, push.Notification{
		Title: "Offer not used",
		Body:  "The team couldn't use that offer. Other requests are waiting on the Help tab.",
		Data:  map[string]string{"kind": "help"},
	})
	s.respondStaffHelpRequest(w, admin.ID, requestID)
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
	var claimedBy sql.NullString
	err := s.db.QueryRow(`SELECT user_id, status, claimed_by FROM help_requests WHERE id = ?`, id).Scan(&ownerID, &status, &claimedBy)
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
		writeError(w, http.StatusBadRequest, "kind must be on_my_way, arrived, running_late, cant_make_it or unsafe")
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
		`SELECT hr.id, hr.category, u.name_encrypted, h.name_encrypted, hr.rating, hr.completed_at
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
