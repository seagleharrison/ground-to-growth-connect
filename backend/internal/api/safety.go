package api

import (
	"database/sql"
	"encoding/json"
	"net/http"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

const (
	maxReportReasonRunes  = 1000
	maxOpenReportsPerUser = 20
)

// releaseClaims hands back every request a staff member had taken on for one
// participant (or all of them when participantID is empty), so it goes back
// to the board for someone else.
func (s *Server) releaseClaims(staffID, participantID string) error {
	if participantID == "" {
		_, err := s.db.Exec(`UPDATE help_requests SET status = 'open', claimed_by = NULL, claimed_at = NULL, progress = NULL, progress_at = NULL, progress_minutes = NULL WHERE claimed_by = ? AND status = 'claimed'`, staffID)
		return err
	}
	_, err := s.db.Exec(
		`UPDATE help_requests SET status = 'open', claimed_by = NULL, claimed_at = NULL, progress = NULL, progress_at = NULL, progress_minutes = NULL WHERE claimed_by = ? AND user_id = ? AND status = 'claimed'`,
		staffID, participantID)
	return err
}

type personJSON struct {
	UserID string `json:"userId"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

func (s *Server) personJSONFor(id string, viewerIsStaff bool) (personJSON, error) {
	p, err := s.loadPerson(id)
	if err != nil || p == nil {
		return personJSON{UserID: id, Name: "Deleted account", Role: "participant"}, err
	}
	return personJSON{UserID: id, Name: displayName(viewerIsStaff, p), Role: roleFor(viewerIsStaff, p)}, nil
}

// --- blocking ---

type userIDRequest struct {
	UserID string `json:"userId"`
}

// applyBlock records the block and takes the blocked volunteer off any request
// of the blocker's they were helping.
func (s *Server) applyBlock(blockerID, blockedID string) error {
	if _, err := s.db.Exec(`INSERT OR IGNORE INTO blocks (blocker_id, blocked_id) VALUES (?, ?)`, blockerID, blockedID); err != nil {
		return err
	}
	return s.releaseClaims(blockedID, blockerID)
}

func (s *Server) handleBlock(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	var body userIDRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.UserID == "" {
		writeError(w, http.StatusBadRequest, "userId is required")
		return
	}
	if isStaff(u.PersonType) {
		writeError(w, http.StatusForbidden, "Only people getting support can block someone.")
		return
	}
	other, err := s.loadPerson(body.UserID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if other == nil || other.ID == u.ID {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if other.Type == "admin" {
		writeError(w, http.StatusBadRequest, "You can't block the Ground to Growth team. If something is wrong, use Report a problem.")
		return
	}
	if err := s.applyBlock(u.ID, other.ID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"blocked": true})
}

func (s *Server) handleListBlocks(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(`SELECT blocked_id FROM blocks WHERE blocker_id = ? ORDER BY created_at DESC`, u.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			writeInternalError(w, err)
			return
		}
		ids = append(ids, id)
	}
	rows.Close()
	out := []personJSON{}
	for _, id := range ids {
		p, err := s.personJSONFor(id, isStaff(u.PersonType))
		if err != nil {
			writeInternalError(w, err)
			return
		}
		out = append(out, p)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"blocked": out})
}

func (s *Server) handleUnblock(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	if _, err := s.db.Exec(`DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?`, u.ID, r.PathValue("userId")); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"unblocked": true})
}

// --- reports ---

type createReportRequest struct {
	UserID string  `json:"userId"`
	Reason *string `json:"reason"`
}

// handleCreateReport lets anyone flag a person. When a participant reports a
// volunteer it also blocks them straight away: nobody has to wait for an admin
// to be protected from someone who made them uncomfortable.
func (s *Server) handleCreateReport(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	var body createReportRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.UserID == "" {
		writeError(w, http.StatusBadRequest, "userId is required")
		return
	}
	subject, err := s.loadPerson(body.UserID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if subject == nil || subject.ID == u.ID {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	var open int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM reports WHERE reporter_id = ? AND status = 'open'`, u.ID).Scan(&open); err != nil {
		writeInternalError(w, err)
		return
	}
	if open >= maxOpenReportsPerUser {
		writeError(w, http.StatusConflict, "You already have several open reports. An admin will look at them soon.")
		return
	}
	reason := trimmedOrNil(body.Reason)
	if reason != nil {
		t := truncateRunes(*reason, maxReportReasonRunes)
		reason = &t
	}
	reasonEnc, err := cryptox.EncryptString(reason)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	var id string
	if err := s.db.QueryRow(
		`INSERT INTO reports (reporter_id, subject_id, reason_encrypted) VALUES (?, ?, ?) RETURNING id`, u.ID, subject.ID, reasonEnc,
	).Scan(&id); err != nil {
		writeInternalError(w, err)
		return
	}
	s.notifyUsers(s.adminIDsExcept(u.ID), push.Notification{
		Title: "New report",
		Body:  "Someone reported a problem. Open Safety to review.",
		Data:  map[string]string{"kind": "safety"},
	})
	blocked := false
	if !isStaff(u.PersonType) && subject.Type == "volunteer" {
		if err := s.applyBlock(u.ID, subject.ID); err != nil {
			writeInternalError(w, err)
			return
		}
		blocked = true
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"reported": true, "blocked": blocked})
}

type reportJSON struct {
	ID         string     `json:"id"`
	Status     string     `json:"status"`
	CreatedAt  string     `json:"createdAt"`
	Reason     *string    `json:"reason"`
	Reporter   personJSON `json:"reporter"`
	Subject    personJSON `json:"subject"`
	ResolvedAt *string    `json:"resolvedAt"`
}

func (s *Server) handleListReports(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(
		`SELECT id, reporter_id, subject_id, reason_encrypted, status, created_at, resolved_at FROM reports
		 ORDER BY CASE status WHEN 'open' THEN 0 ELSE 1 END, created_at DESC LIMIT 100`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	type raw struct {
		id, reporter, subject, status, createdAt string
		reasonEnc                                []byte
		resolvedAt                               sql.NullString
	}
	var raws []raw
	for rows.Next() {
		var x raw
		if err := rows.Scan(&x.id, &x.reporter, &x.subject, &x.reasonEnc, &x.status, &x.createdAt, &x.resolvedAt); err != nil {
			rows.Close()
			writeInternalError(w, err)
			return
		}
		raws = append(raws, x)
	}
	rows.Close()
	out := []reportJSON{}
	for _, x := range raws {
		reason, err := cryptox.DecryptString(x.reasonEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		reporter, err := s.personJSONFor(x.reporter, true)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		subject, err := s.personJSONFor(x.subject, true)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		out = append(out, reportJSON{ID: x.id, Status: x.status, CreatedAt: x.createdAt, Reason: reason, Reporter: reporter, Subject: subject, ResolvedAt: toPtr(x.resolvedAt)})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"reports": out})
}

func (s *Server) handleResolveReport(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	res, err := s.db.Exec(`UPDATE reports SET status = 'resolved', resolved_at = ?, resolved_by = ? WHERE id = ? AND status = 'open'`, nowStamp(), u.ID, r.PathValue("id"))
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"resolved": true})
}

// --- admin review ---

type adminConversationJSON struct {
	A       personJSON `json:"a"`
	B       personJSON `json:"b"`
	Count   int        `json:"count"`
	LastAt  string     `json:"lastAt"`
	Flagged bool       `json:"flagged"`
}

// handleAdminConversations lists who has been talking to whom — no message
// text. Reading a conversation is a separate, logged step.
func (s *Server) handleAdminConversations(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`
		SELECT MIN(sender_id, recipient_id), MAX(sender_id, recipient_id), COUNT(*), MAX(created_at)
		FROM messages GROUP BY 1, 2 ORDER BY 4 DESC LIMIT 200`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	type pair struct {
		a, b, last string
		n          int
	}
	var pairs []pair
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.a, &p.b, &p.n, &p.last); err != nil {
			rows.Close()
			writeInternalError(w, err)
			return
		}
		pairs = append(pairs, p)
	}
	rows.Close()
	out := []adminConversationJSON{}
	for _, p := range pairs {
		a, err := s.personJSONFor(p.a, true)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		b, err := s.personJSONFor(p.b, true)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		var flagged int
		if err := s.db.QueryRow(
			`SELECT COUNT(*) FROM reports WHERE status = 'open' AND ((reporter_id = ?1 AND subject_id = ?2) OR (reporter_id = ?2 AND subject_id = ?1))`, p.a, p.b,
		).Scan(&flagged); err != nil {
			writeInternalError(w, err)
			return
		}
		out = append(out, adminConversationJSON{A: a, B: b, Count: p.n, LastAt: p.last, Flagged: flagged > 0})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"conversations": out})
}

type adminMessageJSON struct {
	ID        string `json:"id"`
	SenderID  string `json:"senderId"`
	Body      string `json:"body"`
	CreatedAt string `json:"createdAt"`
}

// handleAdminReadConversation shows a whole conversation to an admin and
// records that they looked.
func (s *Server) handleAdminReadConversation(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	a, b := r.PathValue("a"), r.PathValue("b")
	has, err := s.hasThread(a, b)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if !has {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if _, err := s.db.Exec(`INSERT INTO message_access_log (admin_id, user_a, user_b) VALUES (?, ?, ?)`, admin.ID, a, b); err != nil {
		writeInternalError(w, err)
		return
	}
	rows, err := s.db.Query(
		`SELECT id, sender_id, body_encrypted, created_at FROM messages
		 WHERE (sender_id = ?1 AND recipient_id = ?2) OR (sender_id = ?2 AND recipient_id = ?1)
		 ORDER BY created_at ASC, rowid ASC LIMIT 1000`, a, b)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	msgs := []adminMessageJSON{}
	for rows.Next() {
		var m adminMessageJSON
		var enc []byte
		if err := rows.Scan(&m.ID, &m.SenderID, &enc, &m.CreatedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		body, err := cryptox.DecryptString(enc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if body != nil {
			m.Body = *body
		}
		msgs = append(msgs, m)
	}
	rows.Close()
	pa, err := s.personJSONFor(a, true)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	pb, err := s.personJSONFor(b, true)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"a": pa, "b": pb, "messages": msgs})
}

type accessLogJSON struct {
	Admin     string `json:"admin"`
	A         string `json:"a"`
	B         string `json:"b"`
	CreatedAt string `json:"createdAt"`
}

func (s *Server) handleMessageAccessLog(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`SELECT admin_id, user_a, user_b, created_at FROM message_access_log ORDER BY id DESC LIMIT 100`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	type raw struct {
		admin           sql.NullString
		a, b, createdAt string
	}
	var raws []raw
	for rows.Next() {
		var x raw
		if err := rows.Scan(&x.admin, &x.a, &x.b, &x.createdAt); err != nil {
			rows.Close()
			writeInternalError(w, err)
			return
		}
		raws = append(raws, x)
	}
	rows.Close()
	out := []accessLogJSON{}
	for _, x := range raws {
		l := accessLogJSON{CreatedAt: x.createdAt, Admin: "A removed admin"}
		if x.admin.Valid {
			p, err := s.personJSONFor(x.admin.String, true)
			if err != nil {
				writeInternalError(w, err)
				return
			}
			l.Admin = p.Name
		}
		pa, _ := s.personJSONFor(x.a, true)
		pb, _ := s.personJSONFor(x.b, true)
		l.A, l.B = pa.Name, pb.Name
		out = append(out, l)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"log": out})
}

// --- volunteer approval and pausing ---

type volunteerJSON struct {
	UserID    string `json:"userId"`
	Name      string `json:"name"`
	Approved  bool   `json:"approved"`
	Paused    bool   `json:"paused"`
	CreatedAt string `json:"createdAt"`
	// How the people they helped rated it. Admins only.
	ThumbsUp   int `json:"thumbsUp"`
	ThumbsDown int `json:"thumbsDown"`
}

func (s *Server) handleListVolunteers(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`SELECT id, name_encrypted, volunteer_approved, messaging_disabled, created_at FROM users WHERE person_type = 'volunteer' ORDER BY volunteer_approved ASC, created_at DESC`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	out := []volunteerJSON{}
	for rows.Next() {
		var v volunteerJSON
		var nameEnc []byte
		if err := rows.Scan(&v.UserID, &nameEnc, &v.Approved, &v.Paused, &v.CreatedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		name, err := cryptox.DecryptString(nameEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if name != nil {
			v.Name = *name
		}
		out = append(out, v)
	}
	rows.Close()
	for i := range out {
		out[i].ThumbsUp, out[i].ThumbsDown = s.volunteerRatings(out[i].UserID)
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"volunteers": out})
}

func (s *Server) setVolunteer(w http.ResponseWriter, r *http.Request, query string, release bool) {
	id := r.PathValue("id")
	res, err := s.db.Exec(query, id)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if release {
		if err := s.releaseClaims(id, ""); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleApproveVolunteer(w http.ResponseWriter, r *http.Request) {
	s.setVolunteer(w, r, `UPDATE users SET volunteer_approved = 1 WHERE id = ? AND person_type = 'volunteer'`, false)
	s.notifyUser(r.PathValue("id"), push.Notification{
		Title: "You're approved",
		Body:  "You can now see requests and help people.",
		Data:  map[string]string{"kind": "approved"},
	})
}

// handleRevokeVolunteer takes approval back: they lose access straight away and
// anyone they were helping goes back to the board.
func (s *Server) handleRevokeVolunteer(w http.ResponseWriter, r *http.Request) {
	s.setVolunteer(w, r, `UPDATE users SET volunteer_approved = 0 WHERE id = ? AND person_type = 'volunteer'`, true)
}

func (s *Server) handlePauseVolunteer(w http.ResponseWriter, r *http.Request) {
	s.setVolunteer(w, r, `UPDATE users SET messaging_disabled = 1 WHERE id = ? AND person_type = 'volunteer'`, true)
}

func (s *Server) handleUnpauseVolunteer(w http.ResponseWriter, r *http.Request) {
	s.setVolunteer(w, r, `UPDATE users SET messaging_disabled = 0 WHERE id = ? AND person_type = 'volunteer'`, false)
}
