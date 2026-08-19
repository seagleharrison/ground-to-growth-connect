// Package api implements the HTTP surface, 1:1 with the original Express
// routes/api.js: same paths, JSON field casing, status codes, and auth rules.
package api

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"

	"ground-to-growth-connect-backend/internal/blobstore"
)

type Server struct {
	db           *sql.DB
	docs         blobstore.Store
	corsOrigins  []string
	corsWildcard bool
}

func NewServer(db *sql.DB, docs blobstore.Store) http.Handler {
	s := &Server{db: db, docs: docs}

	raw := os.Getenv("CORS_ORIGIN")
	if raw == "" {
		raw = "http://localhost:5173"
	}
	if strings.TrimSpace(raw) == "*" {
		s.corsWildcard = true
	} else {
		for _, o := range strings.Split(raw, ",") {
			o = strings.TrimSpace(o)
			if o != "" {
				s.corsOrigins = append(s.corsOrigins, o)
			}
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.handleHealth)

	mux.HandleFunc("POST /api/users", s.handleRegister)
	mux.HandleFunc("GET /api/me", s.withAuth(s.handleMe))
	mux.HandleFunc("DELETE /api/account", s.withAuth(s.handleDeleteAccount))

	mux.HandleFunc("GET /api/consent/disclosure", s.handleDisclosure)
	mux.HandleFunc("GET /api/consent/status", s.withAuth(s.handleConsentStatus))
	mux.HandleFunc("GET /api/consent/history", s.withAuth(s.handleConsentHistory))
	mux.HandleFunc("POST /api/consent", s.withAuth(s.handleSetConsent))

	mux.HandleFunc("GET /api/consent/documents/disclosure", s.handleDocumentDisclosure)
	mux.HandleFunc("GET /api/consent/documents/status", s.withAuth(s.handleDocumentConsentStatus))
	mux.HandleFunc("GET /api/consent/documents/history", s.withAuth(s.handleDocumentConsentHistory))
	mux.HandleFunc("POST /api/consent/documents", s.withAuth(s.handleSetDocumentConsent))

	mux.HandleFunc("POST /api/locations", s.withAuth(s.withConsent(s.handleCreateLocation)))
	mux.HandleFunc("GET /api/locations/latest", s.withAuth(s.withStaff(s.handleLatestLocations)))
	mux.HandleFunc("GET /api/locations/mine", s.withAuth(s.handleMyLocations))

	mux.HandleFunc("POST /api/documents", s.withAuth(s.withDocumentConsent(s.handleUploadDocument)))
	mux.HandleFunc("GET /api/documents", s.withAuth(s.handleListDocuments))
	mux.HandleFunc("GET /api/documents/on-file", s.withAuth(s.withStaff(s.handleDocumentsOnFile)))
	mux.HandleFunc("GET /api/documents/{id}", s.withAuth(s.handleGetDocument))
	mux.HandleFunc("DELETE /api/documents/{id}", s.withAuth(s.handleDeleteDocument))

	mux.HandleFunc("/", s.handleNotFound)

	return s.withMiddleware(mux)
}

// withMiddleware applies security headers, CORS, panic recovery (mirrors the
// Express central error handler — no stack traces leaked), and a 16kb body
// cap, wrapping every request the same way `app.use(...)` did in index.js.
func (s *Server) withMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic: %v", rec)
				writeError(w, http.StatusInternalServerError, "Internal server error")
			}
		}()

		setSecurityHeaders(w)
		allowed := s.applyCORS(w, r)

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if !allowed {
			writeError(w, http.StatusForbidden, "Origin not allowed")
			return
		}

		r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
		next.ServeHTTP(w, r)
	})
}

func setSecurityHeaders(w http.ResponseWriter) {
	h := w.Header()
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("X-Frame-Options", "DENY")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("X-DNS-Prefetch-Control", "off")
	h.Set("X-Download-Options", "noopen")
	h.Set("X-Permitted-Cross-Domain-Policies", "none")
	h.Set("X-XSS-Protection", "0")
	h.Set("Strict-Transport-Security", "max-age=15552000; includeSubDomains")
	h.Set("Content-Security-Policy", "default-src 'none'")
}

// applyCORS mirrors the Node cors() config: CORS_ORIGIN may be "*" (reflect
// any origin), a comma-separated allowlist, or absent (default dev origin).
// Requests with no Origin header (e.g. the iOS app) are always allowed.
func (s *Server) applyCORS(w http.ResponseWriter, r *http.Request) bool {
	origin := r.Header.Get("Origin")
	w.Header().Set("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if s.corsWildcard {
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		return true
	}

	if origin == "" {
		return true
	}
	for _, o := range s.corsOrigins {
		if o == origin {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			return true
		}
	}
	return false
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// writeInternalError logs the real underlying error server-side (never sent
// to the client) before responding with the generic 500 message.
func writeInternalError(w http.ResponseWriter, err error) {
	log.Printf("internal server error: %v", err)
	writeError(w, http.StatusInternalServerError, "Internal server error")
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": "0.1.0"})
}

func (s *Server) handleNotFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotFound, "Not found")
}
