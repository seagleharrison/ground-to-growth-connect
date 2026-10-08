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
	"ground-to-growth-connect-backend/internal/push"
)

type Server struct {
	db           *sql.DB
	docs         blobstore.Store
	corsOrigins  []string
	corsWildcard bool

	// push is nil until an Apple key is configured.
	push     push.Sender
	pushSync bool
}

func NewServer(db *sql.DB, docs blobstore.Store, opts ...Option) http.Handler {
	s := &Server{db: db, docs: docs}
	for _, opt := range opts {
		opt(s)
	}

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
	mux.HandleFunc("POST /api/recover", s.handleRecover)
	mux.HandleFunc("GET /api/me", s.withAuth(s.handleMe))
	mux.HandleFunc("PATCH /api/me", s.withAuth(s.handleUpdateProfile))
	mux.HandleFunc("PUT /api/me/picture", s.withAuth(s.handlePutProfilePicture))
	mux.HandleFunc("GET /api/me/picture", s.withAuth(s.handleGetProfilePicture))
	mux.HandleFunc("DELETE /api/me/picture", s.withAuth(s.handleDeleteProfilePicture))
	mux.HandleFunc("DELETE /api/account", s.withAuth(s.handleDeleteAccount))
	mux.HandleFunc("POST /api/me/recovery-code", s.withAuth(s.handleRegenerateRecoveryCode))

	mux.HandleFunc("GET /api/consent/disclosure", s.handleDisclosure)
	mux.HandleFunc("GET /api/consent/status", s.withAuth(s.handleConsentStatus))
	mux.HandleFunc("GET /api/consent/history", s.withAuth(s.handleConsentHistory))
	mux.HandleFunc("POST /api/consent", s.withAuth(s.handleSetConsent))

	mux.HandleFunc("GET /api/consent/documents/disclosure", s.handleDocumentDisclosure)
	mux.HandleFunc("GET /api/consent/documents/status", s.withAuth(s.handleDocumentConsentStatus))
	mux.HandleFunc("GET /api/consent/documents/history", s.withAuth(s.handleDocumentConsentHistory))
	mux.HandleFunc("POST /api/consent/documents", s.withAuth(s.handleSetDocumentConsent))

	mux.HandleFunc("POST /api/locations", s.withAuth(s.withConsent(s.handleCreateLocation)))
	mux.HandleFunc("GET /api/locations/latest", s.withAuth(s.withAdmin(s.handleLatestLocations)))
	mux.HandleFunc("GET /api/resources", s.handleResources)
	mux.HandleFunc("GET /api/events", s.handleEvents)
	mux.HandleFunc("POST /api/appointments", s.withAuth(s.handleCreateAppointment))
	mux.HandleFunc("GET /api/appointments", s.withAuth(s.handleListAppointments))
	mux.HandleFunc("PATCH /api/appointments/{id}", s.withAuth(s.handleUpdateAppointment))
	mux.HandleFunc("DELETE /api/appointments/{id}", s.withAuth(s.handleDeleteAppointment))

	mux.HandleFunc("POST /api/help-requests", s.withAuth(s.handleCreateHelpRequest))
	mux.HandleFunc("GET /api/help-requests/mine", s.withAuth(s.handleMyHelpRequests))
	mux.HandleFunc("GET /api/help-requests", s.withAuth(s.withApprovedStaff(s.handleHelpBoard)))
	mux.HandleFunc("POST /api/help-requests/{id}/claim", s.withAuth(s.withApprovedStaff(s.handleClaimHelpRequest)))
	mux.HandleFunc("POST /api/help-requests/{id}/release", s.withAuth(s.withApprovedStaff(s.handleReleaseHelpRequest)))
	mux.HandleFunc("POST /api/help-requests/{id}/complete", s.withAuth(s.handleCompleteHelpRequest))
	mux.HandleFunc("DELETE /api/help-requests/{id}", s.withAuth(s.handleDeleteHelpRequest))
	mux.HandleFunc("POST /api/help-requests/{id}/progress", s.withAuth(s.handleHelpProgress))
	mux.HandleFunc("POST /api/help-requests/{id}/rating", s.withAuth(s.handleRateHelp))
	mux.HandleFunc("POST /api/help-offers/{id}/approve", s.withAuth(s.withAdmin(s.handleApproveOffer)))
	mux.HandleFunc("POST /api/help-offers/{id}/decline", s.withAuth(s.withAdmin(s.handleDeclineOffer)))
	mux.HandleFunc("DELETE /api/help-offers/{id}", s.withAuth(s.withApprovedStaff(s.handleWithdrawOffer)))
	mux.HandleFunc("GET /api/admin/people", s.withAuth(s.withAdmin(s.handlePeopleList)))
	mux.HandleFunc("GET /api/admin/people/{id}", s.withAuth(s.withAdmin(s.handlePersonDetail)))
	mux.HandleFunc("GET /api/admin/help-history", s.withAuth(s.withAdmin(s.handleHelpHistory)))

	mux.HandleFunc("GET /api/conversations", s.withAuth(s.handleConversations))
	mux.HandleFunc("GET /api/messages/{userId}", s.withAuth(s.handleGetMessages))
	mux.HandleFunc("POST /api/messages/{userId}", s.withAuth(s.handleSendMessage))

	mux.HandleFunc("PUT /api/push-token", s.withAuth(s.handleRegisterPushToken))
	mux.HandleFunc("DELETE /api/push-token", s.withAuth(s.handleUnregisterPushToken))

	mux.HandleFunc("POST /api/blocks", s.withAuth(s.handleBlock))
	mux.HandleFunc("GET /api/blocks", s.withAuth(s.handleListBlocks))
	mux.HandleFunc("DELETE /api/blocks/{userId}", s.withAuth(s.handleUnblock))
	mux.HandleFunc("POST /api/reports", s.withAuth(s.handleCreateReport))
	mux.HandleFunc("GET /api/reports", s.withAuth(s.withAdmin(s.handleListReports)))
	mux.HandleFunc("POST /api/reports/{id}/resolve", s.withAuth(s.withAdmin(s.handleResolveReport)))

	mux.HandleFunc("GET /api/admin/conversations", s.withAuth(s.withAdmin(s.handleAdminConversations)))
	mux.HandleFunc("GET /api/admin/conversations/{a}/{b}", s.withAuth(s.withAdmin(s.handleAdminReadConversation)))
	mux.HandleFunc("GET /api/admin/access-log", s.withAuth(s.withAdmin(s.handleMessageAccessLog)))
	mux.HandleFunc("GET /api/admin/volunteers", s.withAuth(s.withAdmin(s.handleListVolunteers)))
	mux.HandleFunc("POST /api/admin/volunteers/{id}/approve", s.withAuth(s.withAdmin(s.handleApproveVolunteer)))
	mux.HandleFunc("POST /api/admin/volunteers/{id}/revoke", s.withAuth(s.withAdmin(s.handleRevokeVolunteer)))
	mux.HandleFunc("POST /api/admin/volunteers/{id}/pause", s.withAuth(s.withAdmin(s.handlePauseVolunteer)))
	mux.HandleFunc("POST /api/admin/volunteers/{id}/unpause", s.withAuth(s.withAdmin(s.handleUnpauseVolunteer)))
	mux.HandleFunc("GET /api/analytics", s.withAuth(s.withAdmin(s.handleAnalytics)))
	mux.HandleFunc("GET /api/analytics/sources", s.withAuth(s.withAdmin(s.handleSourceReport)))
	mux.HandleFunc("POST /api/analytics/sources/reviewed", s.withAuth(s.withAdmin(s.handleSourceReviewed)))
	mux.HandleFunc("GET /api/locations/mine", s.withAuth(s.handleMyLocations))

	mux.HandleFunc("POST /api/documents", s.withAuth(s.withDocumentConsent(s.handleUploadDocument)))
	mux.HandleFunc("GET /api/documents", s.withAuth(s.handleListDocuments))
	mux.HandleFunc("GET /api/documents/on-file", s.withAuth(s.withApprovedStaff(s.handleDocumentsOnFile)))
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

		// Routes that accept real files apply their own, larger cap inside the
		// handler. They must be exempt here: wrapping a MaxBytesReader inside
		// another one leaves the smaller limit in force, so a route that only
		// re-wraps would still reject anything over 16kb.
		if !hasLargeBody(r) {
			r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
		}
		next.ServeHTTP(w, r)
	})
}

// hasLargeBody reports whether the request is to a route that carries a file
// (a scanned document or a profile picture) rather than a small JSON payload.
func hasLargeBody(r *http.Request) bool {
	return (r.Method == http.MethodPost && r.URL.Path == "/api/documents") ||
		(r.Method == http.MethodPut && r.URL.Path == "/api/me/picture")
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
	w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,PUT,DELETE,OPTIONS")
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
