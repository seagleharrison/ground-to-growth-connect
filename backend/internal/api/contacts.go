package api

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"sort"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
)

// The admins' shared contact book: a name, phone, email and a free-text note
// for each person or place the team may need to reach. Only admins can read or
// change it, and every field is encrypted at rest.

const (
	maxContactNameRunes  = 200
	maxContactPhoneRunes = 50
	maxContactEmailRunes = 200
	maxContactNotesRunes = 4000
)

type contactJSON struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Phone     *string `json:"phone"`
	Email     *string `json:"email"`
	Notes     *string `json:"notes"`
	UpdatedAt string  `json:"updatedAt"`
}

type contactBody struct {
	Name  *string `json:"name"`
	Phone *string `json:"phone"`
	Email *string `json:"email"`
	Notes *string `json:"notes"`
}

// encryptOptional trims and caps a field; blank means "nothing stored".
func encryptOptional(v *string, max int) ([]byte, error) {
	if v == nil {
		return nil, nil
	}
	t := strings.TrimSpace(*v)
	if t == "" {
		return nil, nil
	}
	t = truncateRunes(t, max)
	return cryptox.EncryptString(&t)
}

func scanContact(row interface{ Scan(dest ...interface{}) error }) (contactJSON, error) {
	var c contactJSON
	var nameEnc, phoneEnc, emailEnc, notesEnc []byte
	if err := row.Scan(&c.ID, &nameEnc, &phoneEnc, &emailEnc, &notesEnc, &c.UpdatedAt); err != nil {
		return c, err
	}
	name, err := cryptox.DecryptString(nameEnc)
	if err != nil {
		return c, err
	}
	if name != nil {
		c.Name = *name
	}
	if c.Phone, err = cryptox.DecryptString(phoneEnc); err != nil {
		return c, err
	}
	if c.Email, err = cryptox.DecryptString(emailEnc); err != nil {
		return c, err
	}
	if c.Notes, err = cryptox.DecryptString(notesEnc); err != nil {
		return c, err
	}
	return c, nil
}

const contactSelect = `SELECT id, name_encrypted, phone_encrypted, email_encrypted, notes_encrypted, updated_at FROM contacts`

func (s *Server) handleListContacts(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(contactSelect)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()
	out := []contactJSON{}
	for rows.Next() {
		c, err := scanContact(rows)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		writeInternalError(w, err)
		return
	}
	// Names are encrypted, so the alphabet is applied here, not in SQL.
	sort.SliceStable(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	writeJSON(w, http.StatusOK, map[string]interface{}{"contacts": out})
}

func (s *Server) handleCreateContact(w http.ResponseWriter, r *http.Request) {
	var body contactBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	if body.Name == nil || strings.TrimSpace(*body.Name) == "" {
		writeError(w, http.StatusBadRequest, "A contact needs a name.")
		return
	}
	nameEnc, err := encryptOptional(body.Name, maxContactNameRunes)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	phoneEnc, err := encryptOptional(body.Phone, maxContactPhoneRunes)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	emailEnc, err := encryptOptional(body.Email, maxContactEmailRunes)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	notesEnc, err := encryptOptional(body.Notes, maxContactNotesRunes)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	var id string
	if err := s.db.QueryRow(
		`INSERT INTO contacts (created_by, name_encrypted, phone_encrypted, email_encrypted, notes_encrypted) VALUES (?, ?, ?, ?, ?) RETURNING id`,
		userFromCtx(r).ID, nameEnc, phoneEnc, emailEnc, notesEnc,
	).Scan(&id); err != nil {
		writeInternalError(w, err)
		return
	}
	s.respondContact(w, http.StatusCreated, id)
}

func (s *Server) respondContact(w http.ResponseWriter, status int, id string) {
	c, err := scanContact(s.db.QueryRow(contactSelect+` WHERE id = ?`, id))
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, status, map[string]interface{}{"contact": c})
}

// handleUpdateContact changes only the fields that were sent; sending a blank
// phone, email or notes clears it. The name can't be emptied.
func (s *Server) handleUpdateContact(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var body contactBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	var exists int
	if err := s.db.QueryRow(`SELECT 1 FROM contacts WHERE id = ?`, id).Scan(&exists); err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	} else if err != nil {
		writeInternalError(w, err)
		return
	}
	sets := []string{}
	args := []interface{}{}
	add := func(column string, v *string, max int, required bool) bool {
		if v == nil {
			return true
		}
		if required && strings.TrimSpace(*v) == "" {
			writeError(w, http.StatusBadRequest, "A contact needs a name.")
			return false
		}
		enc, err := encryptOptional(v, max)
		if err != nil {
			writeInternalError(w, err)
			return false
		}
		sets = append(sets, column+" = ?")
		args = append(args, enc)
		return true
	}
	if !add("name_encrypted", body.Name, maxContactNameRunes, true) ||
		!add("phone_encrypted", body.Phone, maxContactPhoneRunes, false) ||
		!add("email_encrypted", body.Email, maxContactEmailRunes, false) ||
		!add("notes_encrypted", body.Notes, maxContactNotesRunes, false) {
		return
	}
	if len(sets) > 0 {
		sets = append(sets, `updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`)
		args = append(args, id)
		if _, err := s.db.Exec(`UPDATE contacts SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...); err != nil {
			writeInternalError(w, err)
			return
		}
	}
	s.respondContact(w, http.StatusOK, id)
}

func (s *Server) handleDeleteContact(w http.ResponseWriter, r *http.Request) {
	res, err := s.db.Exec(`DELETE FROM contacts WHERE id = ?`, r.PathValue("id"))
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
