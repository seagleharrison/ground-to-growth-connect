package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"

	"ground-to-growth-connect-backend/internal/push"
)

// Option adjusts how the server is built.
type Option func(*Server)

// WithPush turns on notifications. Without it (no Apple key configured yet)
// everything else works exactly the same.
func WithPush(sender push.Sender) Option { return func(s *Server) { s.push = sender } }

// withPushSync makes notifications send before the request returns, so tests
// can check what went out. Real servers send in the background.
func withPushSync() Option { return func(s *Server) { s.pushSync = true } }

const maxTokensPerUser = 10

var pushTokenPattern = regexp.MustCompile(`^[0-9a-fA-F]{32,200}$`)

type pushTokenRequest struct {
	Token       string `json:"token"`
	Environment string `json:"environment"`
}

// handleRegisterPushToken saves this phone's token for the signed-in person.
// If the phone was last used by someone else, the token moves to this person.
func (s *Server) handleRegisterPushToken(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	var body pushTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	token := strings.ToLower(strings.TrimSpace(body.Token))
	if !pushTokenPattern.MatchString(token) {
		writeError(w, http.StatusBadRequest, "token is not a valid push token")
		return
	}
	env := body.Environment
	if env == "" {
		env = "production"
	}
	if env != "production" && env != "sandbox" {
		writeError(w, http.StatusBadRequest, "environment must be production or sandbox")
		return
	}
	if _, err := s.db.Exec(
		`INSERT INTO push_tokens (token, user_id, environment) VALUES (?, ?, ?)
		 ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, environment = excluded.environment, updated_at = ?`,
		token, u.ID, env, nowStamp(),
	); err != nil {
		writeInternalError(w, err)
		return
	}
	// Keep a person's list short: drop the oldest beyond the limit.
	if _, err := s.db.Exec(
		`DELETE FROM push_tokens WHERE user_id = ? AND token NOT IN (
		   SELECT token FROM push_tokens WHERE user_id = ? ORDER BY updated_at DESC LIMIT ?)`,
		u.ID, u.ID, maxTokensPerUser,
	); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"registered": true})
}

// handleUnregisterPushToken stops notifications to this phone, called when
// someone signs out so the next person isn't sent the last person's alerts.
func (s *Server) handleUnregisterPushToken(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	var body pushTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	if _, err := s.db.Exec(`DELETE FROM push_tokens WHERE token = ? AND user_id = ?`, strings.ToLower(strings.TrimSpace(body.Token)), u.ID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"unregistered": true})
}

// unreadCount is what the app icon's badge should show for someone.
func (s *Server) unreadCount(userID string) int {
	var n int
	_ = s.db.QueryRow(`SELECT COUNT(*) FROM messages WHERE recipient_id = ? AND read_at IS NULL`, userID).Scan(&n)
	return n
}

// notifyUser sends a notification to every phone this person is signed in on.
// It never fails the request that caused it, and never includes message text
// or names: a lock screen can be read by anyone nearby.
func (s *Server) notifyUser(userID string, n push.Notification) {
	if s.push == nil {
		return
	}
	send := func() { s.sendToUser(userID, n) }
	if s.pushSync {
		send()
		return
	}
	go send()
}

// notifyUsers is notifyUser for several people at once.
func (s *Server) notifyUsers(userIDs []string, n push.Notification) {
	for _, id := range userIDs {
		s.notifyUser(id, n)
	}
}

func (s *Server) sendToUser(userID string, n push.Notification) {
	rows, err := s.db.Query(`SELECT token, environment FROM push_tokens WHERE user_id = ?`, userID)
	if err != nil {
		log.Printf("push: loading tokens: %v", err)
		return
	}
	type target struct{ token, env string }
	var targets []target
	for rows.Next() {
		var t target
		if err := rows.Scan(&t.token, &t.env); err == nil {
			targets = append(targets, t)
		}
	}
	rows.Close()

	for _, t := range targets {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		err := s.push.Send(ctx, t.token, t.env, n)
		cancel()
		switch {
		case err == push.ErrUnregistered:
			// The app was deleted or the token went stale: stop trying.
			_, _ = s.db.Exec(`DELETE FROM push_tokens WHERE token = ?`, t.token)
		case err != nil:
			log.Printf("push: sending: %v", err)
		}
	}
}

// staffToNotify lists approved volunteers and admins who aren't paused, for
// "a new request needs someone" style alerts.
func (s *Server) staffToNotify() []string {
	rows, err := s.db.Query(
		`SELECT id FROM users WHERE messaging_disabled = 0 AND (person_type = 'admin' OR (person_type = 'volunteer' AND volunteer_approved = 1))`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	return ids
}

func (s *Server) adminIDs() []string {
	rows, err := s.db.Query(`SELECT id FROM users WHERE person_type = 'admin'`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	return ids
}

func (s *Server) adminIDsExcept(except string) []string {
	var ids []string
	for _, id := range s.adminIDs() {
		if id != except {
			ids = append(ids, id)
		}
	}
	return ids
}

// notifyAdminsOfPendingVolunteer tells admins someone new is waiting.
func (s *Server) notifyAdminsOfPendingVolunteer(exceptID string) {
	s.notifyUsers(s.adminIDsExcept(exceptID), push.Notification{
		Title: "A volunteer needs approval",
		Body:  "Someone signed up to volunteer. Open Safety to review.",
		Data:  map[string]string{"kind": "safety"},
	})
}
