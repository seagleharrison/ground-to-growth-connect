package api

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
	_ "time/tzdata" // so Savannah time works on a server image without zone files

	"ground-to-growth-connect-backend/internal/cryptox"
	"ground-to-growth-connect-backend/internal/push"
)

// Admins are the go-between: people ask the admins for help, and an admin
// picks a volunteer, pings them in chat, and assigns the request. The
// volunteer never talks to the person.

type volunteerPick struct {
	Request *staffHelpRequestJSON
	Vol     *personRef
	VolName string
}

type pickBody struct {
	VolunteerID string `json:"volunteerId"`
}

var helpWhat = map[string]string{
	"food":      "food",
	"shelter":   "a place to stay",
	"ride":      "a ride",
	"documents": "help with ID or papers",
	"clothing":  "clothing or hygiene items",
	"health":    "help with health",
	"work":      "help with work",
	"other":     "some help",
}

// describeHelp says what a request is for, in a sentence the admin's chat
// message can use. It carries no more than the board already shows staff.
func describeHelp(r *staffHelpRequestJSON) string {
	if r.Category == "supplies" && len(r.Items) > 0 {
		labels := []string{}
		for _, code := range r.Items {
			label := code
			for _, it := range supplyItems {
				if it.Code == code {
					label = strings.ToLower(it.Label)
				}
			}
			labels = append(labels, label)
		}
		if len(labels) == 1 {
			return labels[0]
		}
		return strings.Join(labels[:len(labels)-1], ", ") + " and " + labels[len(labels)-1]
	}
	what := helpWhat[r.Category]
	if what == "" {
		what = "some help"
	}
	if r.Category == "ride" && r.Appointment != nil {
		what += " to " + r.Appointment.Title
		if t, err := time.Parse(time.RFC3339, r.Appointment.StartsAt); err == nil {
			loc, lerr := time.LoadLocation("America/New_York")
			if lerr != nil {
				loc = time.UTC
			}
			what += " on " + t.In(loc).Format("Mon Jan 2 at 3:04 PM")
		}
	}
	return what
}

// loadPick checks the request and the volunteer an admin chose: the request
// is still being handled, the volunteer is approved and active, and the
// person hasn't blocked them. It writes the error itself when something is off.
func (s *Server) loadPick(w http.ResponseWriter, r *http.Request) (*volunteerPick, bool) {
	var body pickBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.VolunteerID == "" {
		writeError(w, http.StatusBadRequest, "Choose a volunteer first.")
		return nil, false
	}
	req, err := s.loadHelpRequest(userFromCtx(r).ID, r.PathValue("id"))
	if err != nil {
		writeInternalError(w, err)
		return nil, false
	}
	if req == nil || req.Status == "done" {
		writeError(w, http.StatusNotFound, "Not found")
		return nil, false
	}
	vol, err := s.loadPerson(body.VolunteerID)
	if err != nil {
		writeInternalError(w, err)
		return nil, false
	}
	if vol == nil || vol.Type != "volunteer" {
		writeError(w, http.StatusNotFound, "Not found")
		return nil, false
	}
	if !vol.Approved {
		writeError(w, http.StatusConflict, "That volunteer hasn't been approved yet.")
		return nil, false
	}
	if vol.Disabled {
		writeError(w, http.StatusConflict, "That volunteer's account is paused.")
		return nil, false
	}
	if blocked, err := s.isBlocked(req.UserID, vol.ID); err != nil {
		writeInternalError(w, err)
		return nil, false
	} else if blocked {
		writeError(w, http.StatusConflict, "That volunteer can't be matched with this person.")
		return nil, false
	}
	name := "there"
	if vol.Name != "" {
		name = firstName(vol.Name)
	}
	return &volunteerPick{Request: req, Vol: vol, VolName: name}, true
}

// handleAskVolunteer is the "ping": a chat message from the admin to the
// volunteer asking if they can help, plus the usual generic alert.
func (s *Server) handleAskVolunteer(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	pick, ok := s.loadPick(w, r)
	if !ok {
		return
	}
	text := fmt.Sprintf("Hi %s, can you help %s with %s? Reply here and I'll set it up.",
		pick.VolName, firstName(pick.Request.Name), describeHelp(pick.Request))
	enc, err := cryptox.EncryptString(&text)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if _, err := s.db.Exec(
		`INSERT INTO messages (sender_id, recipient_id, body_encrypted) VALUES (?, ?, ?)`,
		admin.ID, pick.Vol.ID, enc,
	); err != nil {
		writeInternalError(w, err)
		return
	}
	s.logHelpEvent(pick.Request.ID, admin.ID, "asked")
	badge := s.unreadCount(pick.Vol.ID)
	s.notifyUser(pick.Vol.ID, push.Notification{
		Title: "New message",
		Body:  "You have a new message.",
		Badge: &badge,
		Data:  map[string]string{"kind": "message", "userId": admin.ID},
	})
	writeJSON(w, http.StatusOK, map[string]interface{}{"asked": true, "volunteerId": pick.Vol.ID})
}

// handleAssignHelpRequest gives the request to a volunteer. The person is
// told help is on the way; the volunteer is told it's theirs.
func (s *Server) handleAssignHelpRequest(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	pick, ok := s.loadPick(w, r)
	if !ok {
		return
	}
	// Giving it to the volunteer who already has it changes nothing and alerts no one.
	var current sql.NullString
	_ = s.db.QueryRow(`SELECT claimed_by FROM help_requests WHERE id = ? AND status = 'claimed'`, pick.Request.ID).Scan(&current)
	if current.Valid && current.String == pick.Vol.ID {
		s.respondStaffHelpRequest(w, admin.ID, pick.Request.ID)
		return
	}
	if _, err := s.db.Exec(
		`UPDATE help_requests SET status = 'claimed', claimed_by = ?, claimed_at = ?, progress = NULL, progress_at = NULL, progress_minutes = NULL
		 WHERE id = ? AND status != 'done'`,
		pick.Vol.ID, nowStamp(), pick.Request.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}
	s.logHelpEvent(pick.Request.ID, admin.ID, "assigned")
	s.notifyUser(pick.Request.UserID, push.Notification{
		Title: "Help is on the way",
		Body:  "A volunteer is helping with your request.",
		Data:  map[string]string{"kind": "help-claimed"},
	})
	s.notifyUser(pick.Vol.ID, push.Notification{
		Title: "You've been given a request",
		Body:  "Open the app to see it.",
		Data:  map[string]string{"kind": "help-assigned"},
	})
	s.respondStaffHelpRequest(w, admin.ID, pick.Request.ID)
}
