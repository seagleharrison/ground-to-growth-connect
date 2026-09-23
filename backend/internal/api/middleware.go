package api

import (
	"context"
	"database/sql"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
)

var staffTypes = map[string]bool{"volunteer": true, "admin": true}

const (
	consentTypeLocation  = "location_sharing"
	consentTypeDocuments = "document_storage"
)

func isStaff(personType string) bool {
	return staffTypes[personType]
}

type authUser struct {
	ID              string
	PersonType      string
	NameEncrypted   []byte
	EmailEncrypted  []byte
	GenderEncrypted []byte
	PhoneEncrypted  []byte

	// Set once the user has uploaded a profile picture.
	ProfilePictureKey  sql.NullString
	ProfilePictureMime sql.NullString
}

type ctxKey int

const userCtxKey ctxKey = 0

func userFromCtx(r *http.Request) *authUser {
	u, _ := r.Context().Value(userCtxKey).(*authUser)
	return u
}

// withAuth mirrors the Express `authenticate` middleware: look up the user by
// the SHA-256 hash of the bearer token.
func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "Missing bearer token")
			return
		}
		tokenHash := cryptox.HashToken(strings.TrimPrefix(auth, "Bearer "))

		var u authUser
		err := s.db.QueryRow(
			`SELECT id, person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted,
			        profile_picture_key, profile_picture_mime
			 FROM users WHERE token_hash = ?`,
			tokenHash,
		).Scan(&u.ID, &u.PersonType, &u.NameEncrypted, &u.EmailEncrypted, &u.GenderEncrypted, &u.PhoneEncrypted,
			&u.ProfilePictureKey, &u.ProfilePictureMime)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusUnauthorized, "Invalid token")
			return
		}
		if err != nil {
			writeInternalError(w, err)
			return
		}

		ctx := context.WithValue(r.Context(), userCtxKey, &u)
		next(w, r.WithContext(ctx))
	}
}

func (s *Server) withStaff(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userFromCtx(r)
		if !isStaff(u.PersonType) {
			writeError(w, http.StatusForbidden, "Staff access required")
			return
		}
		next(w, r)
	}
}

// withConsentType gates a handler on a specific, independent consent type
// (location sharing vs. document storage are tracked separately — see the
// consent_type column and the repartitioned user_consent_status view).
func (s *Server) withConsentType(consentType, deniedMessage string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userFromCtx(r)
		var granted int64
		err := s.db.QueryRow(
			`SELECT granted FROM user_consent_status WHERE user_id = ? AND consent_type = ?`,
			u.ID, consentType,
		).Scan(&granted)
		if err != nil && err != sql.ErrNoRows {
			writeInternalError(w, err)
			return
		}
		if err == sql.ErrNoRows || granted == 0 {
			writeError(w, http.StatusForbidden, deniedMessage)
			return
		}
		next(w, r)
	}
}

func (s *Server) withConsent(next http.HandlerFunc) http.HandlerFunc {
	return s.withConsentType(consentTypeLocation, "Location tracking consent not granted", next)
}

func (s *Server) withDocumentConsent(next http.HandlerFunc) http.HandlerFunc {
	return s.withConsentType(consentTypeDocuments, "Document storage consent not granted", next)
}
