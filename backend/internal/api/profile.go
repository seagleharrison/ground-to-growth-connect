package api

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/blobstore"
	"ground-to-growth-connect-backend/internal/consent"
	"ground-to-growth-connect-backend/internal/cryptox"
)

var profilePictureMimeTypes = []string{"image/jpeg", "image/png"}

// The JSON body carries the picture base64-encoded (~33% larger than the raw
// file), so the request cap sits a bit above the raw-size limit.
const (
	maxProfilePictureBytes        = 5 * 1024 * 1024
	maxProfilePictureRequestBytes = 8 * 1024 * 1024
)

func profilePictureKey(userID string) string {
	return "profile-pictures/" + userID + ".enc"
}

// updateProfileRequest uses pointers so that an omitted field means "leave
// this alone" while an empty string means "clear it" (email and gender are
// optional; name and phone can't be emptied, same as at sign-up).
//
// PersonType changes the account type. Account type decides who can see other
// people's locations, so moving *into* a staff role needs the same staff invite
// code as signing up as staff; moving back to a participant account is free.
type updateProfileRequest struct {
	Name       *string `json:"name"`
	Email      *string `json:"email"`
	Phone      *string `json:"phone"`
	Gender     *string `json:"gender"`
	PersonType *string `json:"personType"`
	StaffCode  *string `json:"staffCode"`
}

func (s *Server) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	var body updateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}

	personType := u.PersonType
	if body.PersonType != nil && *body.PersonType != u.PersonType {
		requested := *body.PersonType
		if !contains(personTypes, requested) {
			writeError(w, http.StatusBadRequest, fmt.Sprintf("personType must be one of: %s", strings.Join(personTypes, ", ")))
			return
		}
		if isStaff(requested) {
			code := ""
			if body.StaffCode != nil {
				code = *body.StaffCode
			}
			if !validStaffCode(code) {
				writeError(w, http.StatusForbidden, "A valid staff invite code is required for staff accounts.")
				return
			}
		}
		personType = requested
	}

	nameEnc, emailEnc, genderEnc, phoneEnc := u.NameEncrypted, u.EmailEncrypted, u.GenderEncrypted, u.PhoneEncrypted
	var err error

	if body.Name != nil {
		name := strings.TrimSpace(*body.Name)
		if name == "" {
			writeError(w, http.StatusBadRequest, "name cannot be empty")
			return
		}
		name = truncateRunes(name, 200)
		if nameEnc, err = cryptox.EncryptString(&name); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	if body.Email != nil {
		emailEnc = nil
		if e := strings.TrimSpace(*body.Email); e != "" {
			e = truncateRunes(e, 200)
			if emailEnc, err = cryptox.EncryptString(&e); err != nil {
				writeInternalError(w, err)
				return
			}
		}
	}

	if body.Phone != nil {
		p := strings.TrimSpace(*body.Phone)
		if p == "" {
			writeError(w, http.StatusBadRequest, "phone cannot be empty")
			return
		}
		p = truncateRunes(p, 40)
		if phoneEnc, err = cryptox.EncryptString(&p); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	if body.Gender != nil {
		genderEnc = nil
		if g := *body.Gender; g != "" {
			if !contains(genders, g) {
				writeError(w, http.StatusBadRequest, fmt.Sprintf("gender must be one of: %s", strings.Join(genders, ", ")))
				return
			}
			if genderEnc, err = cryptox.EncryptString(&g); err != nil {
				writeInternalError(w, err)
				return
			}
		}
	}

	if _, err := s.db.Exec(
		`UPDATE users SET person_type = ?, name_encrypted = ?, email_encrypted = ?, gender_encrypted = ?, phone_encrypted = ? WHERE id = ?`,
		personType, nameEnc, emailEnc, genderEnc, phoneEnc, u.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}

	// A participant who becomes staff stops sharing their location. Without
	// this, switching back later would silently start sharing again.
	if !isStaff(u.PersonType) && isStaff(personType) {
		s.revokeLocationConsentIfGranted(u.ID)
	}
	u.PersonType = personType

	u.NameEncrypted, u.EmailEncrypted, u.GenderEncrypted, u.PhoneEncrypted = nameEnc, emailEnc, genderEnc, phoneEnc
	s.writeProfile(w, http.StatusOK, u)
}

func (s *Server) revokeLocationConsentIfGranted(userID string) {
	var granted int
	err := s.db.QueryRow(
		`SELECT granted FROM user_consent_status WHERE user_id = ? AND consent_type = ?`,
		userID, consentTypeLocation,
	).Scan(&granted)
	if err != nil || granted != 1 {
		return
	}
	if _, err := s.db.Exec(
		`INSERT INTO consent_records (user_id, consent_type, consent_version, disclosure_text, granted, revoked_at)
		 VALUES (?, ?, ?, ?, 0, ?)`,
		userID, consentTypeLocation, consent.Version(), consent.LocationDisclosureText(), nowISO(),
	); err != nil {
		log.Printf("revoking location consent for %s after role change: %v", userID, err)
	}
}

func (s *Server) writeProfile(w http.ResponseWriter, status int, u *authUser) {
	profile, err := profileFromUser(u)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, status, map[string]interface{}{"user": profile})
}

type putProfilePictureRequest struct {
	MimeType   string `json:"mimeType"`
	FileBase64 string `json:"fileBase64"`
}

func (s *Server) handlePutProfilePicture(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	ctx := r.Context()

	// This route is exempt from the global 16kb cap (see hasLargeBody), so
	// this is the only limit that applies to it.
	r.Body = http.MaxBytesReader(w, r.Body, maxProfilePictureRequestBytes)

	var body putProfilePictureRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body, or picture too large")
		return
	}
	if !contains(profilePictureMimeTypes, body.MimeType) {
		writeError(w, http.StatusBadRequest, "mimeType must be one of: "+strings.Join(profilePictureMimeTypes, ", "))
		return
	}

	pic, err := base64.StdEncoding.DecodeString(body.FileBase64)
	if err != nil || len(pic) == 0 {
		writeError(w, http.StatusBadRequest, "fileBase64 must be a non-empty, valid base64 image")
		return
	}
	if len(pic) > maxProfilePictureBytes {
		writeError(w, http.StatusBadRequest, "Picture is too large (5 MB maximum)")
		return
	}

	picEnc, err := cryptox.EncryptBytes(pic)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	// One picture per user: the key is per-user, so a new upload simply
	// replaces the old blob in place.
	key := profilePictureKey(u.ID)
	if err := s.docs.Put(ctx, key, picEnc); err != nil {
		writeInternalError(w, err)
		return
	}
	if _, err := s.db.Exec(
		`UPDATE users SET profile_picture_key = ?, profile_picture_mime = ? WHERE id = ?`,
		key, body.MimeType, u.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}

	u.ProfilePictureKey = sql.NullString{String: key, Valid: true}
	u.ProfilePictureMime = sql.NullString{String: body.MimeType, Valid: true}
	s.writeProfile(w, http.StatusOK, u)
}

func (s *Server) handleGetProfilePicture(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	if !u.ProfilePictureKey.Valid {
		writeError(w, http.StatusNotFound, "No profile picture")
		return
	}

	picEnc, err := s.docs.Get(r.Context(), u.ProfilePictureKey.String)
	if errors.Is(err, blobstore.ErrNotFound) {
		writeError(w, http.StatusNotFound, "No profile picture")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	pic, err := cryptox.DecryptBytes(picEnc)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"mimeType":   u.ProfilePictureMime.String,
		"fileBase64": base64.StdEncoding.EncodeToString(pic),
	})
}

func (s *Server) handleDeleteProfilePicture(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	if u.ProfilePictureKey.Valid {
		if _, err := s.db.Exec(
			`UPDATE users SET profile_picture_key = NULL, profile_picture_mime = NULL WHERE id = ?`, u.ID,
		); err != nil {
			writeInternalError(w, err)
			return
		}
		// The row no longer points at the blob; a failed delete only leaves
		// an orphaned (still encrypted) file behind, so log it and carry on.
		if err := s.docs.Delete(r.Context(), u.ProfilePictureKey.String); err != nil {
			log.Printf("orphaned profile picture blob %s: %v", u.ProfilePictureKey.String, err)
		}
		u.ProfilePictureKey = sql.NullString{}
		u.ProfilePictureMime = sql.NullString{}
	}

	s.writeProfile(w, http.StatusOK, u)
}
