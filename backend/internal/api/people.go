package api

import (
	"database/sql"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
)

// The admins' people lists, opened from the Analytics screen: everyone
// registered, and a profile for each. These show who someone is and where they
// stand with the program. They never include what is private to the person:
// messages, calendar appointments, documents or where they have been.

type personListItem struct {
	UserID   string `json:"userId"`
	Name     string `json:"name"`
	Role     string `json:"role"` // participant | volunteer | admin
	JoinedAt string `json:"joinedAt"`
	// People we serve: whether they are currently sharing their location.
	Sharing bool `json:"sharing"`
	// Volunteers: where they stand.
	Approved   bool `json:"approved"`
	Paused     bool `json:"paused"`
	ThumbsUp   int  `json:"thumbsUp"`
	ThumbsDown int  `json:"thumbsDown"`
}

type personDetailJSON struct {
	personListItem
	Email  *string `json:"email"`
	Phone  *string `json:"phone"`
	Gender *string `json:"gender"`
	// People we serve.
	LastCheckIn      *string `json:"lastCheckIn"` // only while they are sharing
	DocumentStorage  bool    `json:"documentStorage"`
	DocumentsOnFile  int     `json:"documentsOnFile"`
	HelpRequests     int     `json:"helpRequests"`
	HelpRequestsDone int     `json:"helpRequestsDone"`
	// Volunteers and admins: requests they have helped with.
	Helped int `json:"helped"`
}

func roleName(personType string) string {
	switch personType {
	case "homeless":
		return "participant"
	default:
		return personType
	}
}

func (s *Server) handlePeopleList(w http.ResponseWriter, r *http.Request) {
	group := r.URL.Query().Get("group")
	var where string
	switch group {
	case "serve":
		where = `u.person_type = 'homeless'`
	case "staff":
		where = `u.person_type IN ('volunteer', 'admin')`
	default:
		writeError(w, http.StatusBadRequest, "group must be serve or staff")
		return
	}
	rows, err := s.db.Query(`
		SELECT u.id, u.person_type, u.name_encrypted, u.created_at, u.volunteer_approved, u.messaging_disabled,
		       COALESCE((SELECT cs.granted FROM user_consent_status cs WHERE cs.user_id = u.id AND cs.consent_type = ?), 0)
		FROM users u WHERE `+where+` ORDER BY u.created_at DESC`, consentTypeLocation)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	out := []personListItem{}
	for rows.Next() {
		var p personListItem
		var personType string
		var nameEnc []byte
		var approved, paused, sharing bool
		if err := rows.Scan(&p.UserID, &personType, &nameEnc, &p.JoinedAt, &approved, &paused, &sharing); err != nil {
			writeInternalError(w, err)
			return
		}
		name, err := cryptox.DecryptString(nameEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		if name != nil {
			p.Name = *name
		}
		p.Role = roleName(personType)
		if personType == "homeless" {
			p.Sharing = sharing
		} else {
			p.Approved = personType == "admin" || approved
			p.Paused = paused
		}
		out = append(out, p)
	}
	rows.Close()
	for i := range out {
		if out[i].Role == "volunteer" {
			out[i].ThumbsUp, out[i].ThumbsDown = s.volunteerRatings(out[i].UserID)
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"people": out})
}

func (s *Server) handlePersonDetail(w http.ResponseWriter, r *http.Request) {
	admin := userFromCtx(r)
	id := r.PathValue("id")
	var d personDetailJSON
	var personType string
	var nameEnc, emailEnc, phoneEnc, genderEnc []byte
	var approved, paused bool
	err := s.db.QueryRow(`
		SELECT id, person_type, name_encrypted, email_encrypted, phone_encrypted, gender_encrypted, created_at, volunteer_approved, messaging_disabled
		FROM users WHERE id = ?`, id).Scan(&d.UserID, &personType, &nameEnc, &emailEnc, &phoneEnc, &genderEnc, &d.JoinedAt, &approved, &paused)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	decrypt := func(b []byte) *string {
		v, derr := cryptox.DecryptString(b)
		if derr != nil {
			err = derr
		}
		if v != nil && strings.TrimSpace(*v) == "" {
			return nil
		}
		return v
	}
	if name := decrypt(nameEnc); name != nil {
		d.Name = *name
	}
	d.Email, d.Phone, d.Gender = decrypt(emailEnc), decrypt(phoneEnc), decrypt(genderEnc)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	d.Role = roleName(personType)

	count := func(dest *int, query string, args ...interface{}) bool {
		if qerr := s.db.QueryRow(query, args...).Scan(dest); qerr != nil {
			writeInternalError(w, qerr)
			return false
		}
		return true
	}
	if personType == "homeless" {
		var sharing, docs int
		if !count(&sharing, `SELECT COALESCE((SELECT granted FROM user_consent_status WHERE user_id = ? AND consent_type = ?), 0)`, id, consentTypeLocation) ||
			!count(&docs, `SELECT COALESCE((SELECT granted FROM user_consent_status WHERE user_id = ? AND consent_type = ?), 0)`, id, consentTypeDocuments) ||
			!count(&d.DocumentsOnFile, `SELECT COUNT(*) FROM documents WHERE user_id = ?`, id) ||
			!count(&d.HelpRequests, `SELECT COUNT(*) FROM help_requests WHERE user_id = ?`, id) ||
			!count(&d.HelpRequestsDone, `SELECT COUNT(*) FROM help_requests WHERE user_id = ? AND status = 'done'`, id) {
			return
		}
		d.Sharing, d.DocumentStorage = sharing == 1, docs == 1
		if d.Sharing {
			var last sql.NullString
			if qerr := s.db.QueryRow(`SELECT MAX(reported_at) FROM location_reports WHERE user_id = ?`, id).Scan(&last); qerr != nil {
				writeInternalError(w, qerr)
				return
			}
			d.LastCheckIn = toPtr(last)
		}
	} else {
		d.Approved = personType == "admin" || approved
		d.Paused = paused
		if !count(&d.Helped, `SELECT COUNT(*) FROM help_requests WHERE claimed_by = ? AND status = 'done'`, id) {
			return
		}
		if personType == "volunteer" {
			d.ThumbsUp, d.ThumbsDown = s.volunteerRatings(id)
		}
	}

	// Looking someone up is recorded, like reviewing a conversation.
	if admin.ID != id {
		if _, err := s.db.Exec(`INSERT INTO profile_access_log (admin_id, subject_id) VALUES (?, ?)`, admin.ID, id); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"person": d})
}
