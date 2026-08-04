package api

import (
	"context"
	"database/sql"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
)

var staffTypes = map[string]bool{"volunteer": true, "employee": true, "admin": true}

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
			`SELECT id, person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted
			 FROM users WHERE token_hash = ?`,
			tokenHash,
		).Scan(&u.ID, &u.PersonType, &u.NameEncrypted, &u.EmailEncrypted, &u.GenderEncrypted, &u.PhoneEncrypted)
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

func (s *Server) withConsent(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userFromCtx(r)
		var granted int64
		err := s.db.QueryRow(`SELECT granted FROM user_consent_status WHERE user_id = ?`, u.ID).Scan(&granted)
		if err != nil && err != sql.ErrNoRows {
			writeInternalError(w, err)
			return
		}
		if err == sql.ErrNoRows || granted == 0 {
			writeError(w, http.StatusForbidden, "Location tracking consent not granted")
			return
		}
		next(w, r)
	}
}
