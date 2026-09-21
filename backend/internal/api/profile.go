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
// this alone" while an empty string means "clear it" (for the optional
// fields). Account type is deliberately not editable here: it decides who can
// see other people's locations, so it can't be self-service.
type updateProfileRequest struct {
	Name   *string `json:"name"`
	Email  *string `json:"email"`
	Phone  *string `json:"phone"`
	Gender *string `json:"gender"`
}

func (s *Server) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	var body updateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
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
		phoneEnc = nil
		if p := strings.TrimSpace(*body.Phone); p != "" {
			p = truncateRunes(p, 40)
			if phoneEnc, err = cryptox.EncryptString(&p); err != nil {
				writeInternalError(w, err)
				return
			}
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
		`UPDATE users SET name_encrypted = ?, email_encrypted = ?, gender_encrypted = ?, phone_encrypted = ? WHERE id = ?`,
		nameEnc, emailEnc, genderEnc, phoneEnc, u.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}

	u.NameEncrypted, u.EmailEncrypted, u.GenderEncrypted, u.PhoneEncrypted = nameEnc, emailEnc, genderEnc, phoneEnc
	s.writeProfile(w, http.StatusOK, u)
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
