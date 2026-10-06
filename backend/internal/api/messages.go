package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"sort"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

const maxMessageRunes = 2000

type personRef struct {
	ID       string
	Type     string
	Name     string
	Approved bool
	Disabled bool
}

func refFromAuth(u *authUser) *personRef {
	return &personRef{ID: u.ID, Type: u.PersonType, Approved: u.canActAsStaff(), Disabled: u.MessagingDisabled}
}

func (s *Server) loadPerson(id string) (*personRef, error) {
	var p personRef
	var nameEnc []byte
	var approved, disabled bool
	err := s.db.QueryRow(`SELECT id, person_type, name_encrypted, volunteer_approved, messaging_disabled FROM users WHERE id = ?`, id).Scan(&p.ID, &p.Type, &nameEnc, &approved, &disabled)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	p.Approved = p.Type == "admin" || (p.Type == "volunteer" && approved)
	p.Disabled = disabled
	if name, err := cryptox.DecryptString(nameEnc); err != nil {
		return nil, err
	} else if name != nil {
		p.Name = *name
	}
	return &p, nil
}

// isBlocked is true if either person has blocked the other.
func (s *Server) isBlocked(a, b string) (bool, error) {
	var n int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM blocks WHERE (blocker_id = ?1 AND blocked_id = ?2) OR (blocker_id = ?2 AND blocked_id = ?1)`, a, b,
	).Scan(&n)
	return n > 0, err
}

// hasThread is true if the two have ever exchanged a message.
func (s *Server) hasThread(a, b string) (bool, error) {
	var n int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM messages WHERE (sender_id = ?1 AND recipient_id = ?2) OR (sender_id = ?2 AND recipient_id = ?1)`, a, b,
	).Scan(&n)
	return n > 0, err
}

// canMessage says whether two people may chat right now. A participant can
// reach the Ground to Growth team (admins), and an approved volunteer only
// while that volunteer is actively helping them. When the help ends the chat
// closes: nobody keeps a private line to someone they're no longer helping.
// Blocks and an admin switching someone's messaging off always win.
func (s *Server) canMessage(a, b *personRef) (bool, error) {
	if a.ID == b.ID || a.Disabled || b.Disabled || isStaff(a.Type) == isStaff(b.Type) {
		return false, nil
	}
	staff, participant := a, b
	if isStaff(b.Type) {
		staff, participant = b, a
	}
	if !staff.Approved {
		return false, nil
	}
	if blocked, err := s.isBlocked(a.ID, b.ID); err != nil || blocked {
		return false, err
	}
	if staff.Type == "admin" {
		return true, nil
	}
	var active int
	if err := s.db.QueryRow(
		`SELECT COUNT(*) FROM help_requests WHERE user_id = ? AND claimed_by = ? AND status = 'claimed'`, participant.ID, staff.ID,
	).Scan(&active); err != nil {
		return false, err
	}
	return active > 0, nil
}

type conversationJSON struct {
	UserID      string  `json:"userId"`
	Name        string  `json:"name"`
	Role        string  `json:"role"` // team | volunteer | participant
	LastMessage *string `json:"lastMessage"`
	LastAt      *string `json:"lastAt"`
	Unread      int     `json:"unread"`
	CanSend     bool    `json:"canSend"`
}

func roleFor(viewerIsStaff bool, other *personRef) string {
	switch {
	case !isStaff(other.Type):
		return "participant"
	case other.Type == "admin":
		return "team"
	default:
		return "volunteer"
	}
}

// displayName: a participant sees staff by first name; staff see full names.
func displayName(viewerIsStaff bool, other *personRef) string {
	if viewerIsStaff || !isStaff(other.Type) {
		return other.Name
	}
	return firstName(other.Name)
}

// handleConversations lists everyone the viewer can message or has messaged,
// with the latest message and how many are unread.
func (s *Server) handleConversations(w http.ResponseWriter, r *http.Request) {
	v := userFromCtx(r)
	viewerStaff := isStaff(v.PersonType)
	if viewerStaff && !v.canActAsStaff() {
		writeJSON(w, http.StatusOK, map[string]interface{}{"conversations": []conversationJSON{}})
		return
	}
	viewerRef := refFromAuth(v)

	candidates := map[string]bool{}
	collect := func(query string, args ...interface{}) error {
		rows, err := s.db.Query(query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				return err
			}
			candidates[id] = true
		}
		return rows.Err()
	}

	var err error
	switch {
	case !viewerStaff:
		err = collect(`SELECT id FROM users WHERE person_type = 'admin'`)
		if err == nil {
			err = collect(`SELECT DISTINCT claimed_by FROM help_requests WHERE user_id = ? AND status = 'claimed' AND claimed_by IS NOT NULL`, v.ID)
		}
	case v.PersonType == "admin":
		err = collect(`SELECT DISTINCT user_id FROM help_requests WHERE status != 'done'`)
	default:
		err = collect(`SELECT DISTINCT user_id FROM help_requests WHERE claimed_by = ? AND status = 'claimed'`, v.ID)
	}
	if err == nil {
		err = collect(`SELECT DISTINCT CASE WHEN sender_id = ?1 THEN recipient_id ELSE sender_id END FROM messages WHERE sender_id = ?1 OR recipient_id = ?1`, v.ID)
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	delete(candidates, v.ID)

	out := []conversationJSON{}
	for id := range candidates {
		other, err := s.loadPerson(id)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if other == nil || isStaff(other.Type) == viewerStaff {
			continue
		}
		c := conversationJSON{UserID: id, Name: displayName(viewerStaff, other), Role: roleFor(viewerStaff, other)}
		if c.CanSend, err = s.canMessage(viewerRef, other); err != nil {
			writeInternalError(w, err)
			return
		}
		// A closed chat with nothing in it isn't worth listing.
		hasThread, err := s.hasThread(v.ID, id)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if !c.CanSend && !hasThread {
			continue
		}

		var bodyEnc []byte
		var at string
		err = s.db.QueryRow(
			`SELECT body_encrypted, created_at FROM messages
			 WHERE (sender_id = ?1 AND recipient_id = ?2) OR (sender_id = ?2 AND recipient_id = ?1)
			 ORDER BY created_at DESC, rowid DESC LIMIT 1`, v.ID, id,
		).Scan(&bodyEnc, &at)
		if err == nil {
			body, derr := cryptox.DecryptString(bodyEnc)
			if derr != nil {
				writeInternalError(w, derr)
				return
			}
			c.LastMessage, c.LastAt = body, &at
		} else if err != sql.ErrNoRows {
			writeInternalError(w, err)
			return
		}
		if err := s.db.QueryRow(
			`SELECT COUNT(*) FROM messages WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL`, id, v.ID,
		).Scan(&c.Unread); err != nil {
			writeInternalError(w, err)
			return
		}
		out = append(out, c)
	}

	sort.Slice(out, func(i, j int) bool {
		if (out[i].Unread > 0) != (out[j].Unread > 0) {
			return out[i].Unread > 0
		}
		li, lj := "", ""
		if out[i].LastAt != nil {
			li = *out[i].LastAt
		}
		if out[j].LastAt != nil {
			lj = *out[j].LastAt
		}
		if li != lj {
			return li > lj
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	writeJSON(w, http.StatusOK, map[string]interface{}{"conversations": out})
}

type messageJSON struct {
	ID        string `json:"id"`
	FromMe    bool   `json:"fromMe"`
	Body      string `json:"body"`
	CreatedAt string `json:"createdAt"`
}

// allowedWith checks the viewer may chat with otherID. With forSend false it
// also lets people read a thread that has since closed.
func (s *Server) allowedWith(w http.ResponseWriter, v *authUser, otherID string, forSend bool) (*personRef, bool, bool) {
	other, err := s.loadPerson(otherID)
	if err != nil {
		writeInternalError(w, err)
		return nil, false, false
	}
	if other == nil {
		writeError(w, http.StatusNotFound, "Not found")
		return nil, false, false
	}
	if isStaff(v.PersonType) && !v.canActAsStaff() {
		writeError(w, http.StatusForbidden, "An admin needs to approve your volunteer account before you can do this.")
		return nil, false, false
	}
	canSend, err := s.canMessage(refFromAuth(v), other)
	if err != nil {
		writeInternalError(w, err)
		return nil, false, false
	}
	if canSend {
		return other, true, true
	}
	if !forSend {
		if has, err := s.hasThread(v.ID, otherID); err != nil {
			writeInternalError(w, err)
			return nil, false, false
		} else if has {
			return other, true, false
		}
		writeError(w, http.StatusNotFound, "Not found")
		return nil, false, false
	}
	if v.MessagingDisabled {
		writeError(w, http.StatusForbidden, "Messaging is switched off for your account. Please contact Ground to Growth.")
		return nil, false, false
	}
	writeError(w, http.StatusForbidden, "This chat is closed. Chats are only open while someone is helping you.")
	return nil, false, false
}

func (s *Server) handleGetMessages(w http.ResponseWriter, r *http.Request) {
	v := userFromCtx(r)
	otherID := r.PathValue("userId")
	_, ok, canSend := s.allowedWith(w, v, otherID, false)
	if !ok {
		return
	}
	rows, err := s.db.Query(
		`SELECT id, sender_id, body_encrypted, created_at FROM (
		   SELECT id, sender_id, body_encrypted, created_at, rowid AS rid FROM messages
		   WHERE (sender_id = ?1 AND recipient_id = ?2) OR (sender_id = ?2 AND recipient_id = ?1)
		   ORDER BY created_at DESC, rowid DESC LIMIT 200
		 ) ORDER BY created_at ASC, rid ASC`, v.ID, otherID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	msgs := []messageJSON{}
	for rows.Next() {
		var m messageJSON
		var sender string
		var bodyEnc []byte
		if err := rows.Scan(&m.ID, &sender, &bodyEnc, &m.CreatedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		body, err := cryptox.DecryptString(bodyEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if body != nil {
			m.Body = *body
		}
		m.FromMe = sender == v.ID
		msgs = append(msgs, m)
	}
	rows.Close()
	if _, err := s.db.Exec(
		`UPDATE messages SET read_at = ? WHERE sender_id = ? AND recipient_id = ? AND read_at IS NULL`, nowStamp(), otherID, v.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"messages": msgs, "canSend": canSend})
}

type sendMessageRequest struct {
	Body string `json:"body"`
}

func (s *Server) handleSendMessage(w http.ResponseWriter, r *http.Request) {
	v := userFromCtx(r)
	otherID := r.PathValue("userId")

	var body sendMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	text := strings.TrimSpace(body.Body)
	if text == "" {
		writeError(w, http.StatusBadRequest, "Write a message first.")
		return
	}
	text = truncateRunes(text, maxMessageRunes)
	if _, ok, _ := s.allowedWith(w, v, otherID, true); !ok {
		return
	}
	enc, err := cryptox.EncryptString(&text)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	var m messageJSON
	if err := s.db.QueryRow(
		`INSERT INTO messages (sender_id, recipient_id, body_encrypted) VALUES (?, ?, ?) RETURNING id, created_at`,
		v.ID, otherID, enc,
	).Scan(&m.ID, &m.CreatedAt); err != nil {
		writeInternalError(w, err)
		return
	}
	m.FromMe, m.Body = true, text
	// The alert says only that there is a message: no text, no names.
	badge := s.unreadCount(otherID)
	s.notifyUser(otherID, push.Notification{
		Title: "New message",
		Body:  "You have a new message.",
		Badge: &badge,
		Data:  map[string]string{"kind": "message", "userId": v.ID},
	})
	writeJSON(w, http.StatusCreated, map[string]interface{}{"message": m})
}
