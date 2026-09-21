package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/content"
	"ground-to-growth-connect-backend/internal/freshness"
)

// handleResources serves the guides, programs and local places for the
// Resources tab. It's public information, so no sign-in is needed (someone
// with a lost phone or no account yet can still read it). The ETag lets the
// app ask "anything new?" cheaply every time it opens the tab.
func (s *Server) handleResources(w http.ResponseWriter, r *http.Request) {
	etag := content.ETag()
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "public, max-age=300")
	if match := r.Header.Get("If-None-Match"); match != "" && strings.Contains(match, etag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(content.JSON())
}

// handleSourceReport tells an admin which official pages need another look.
func (s *Server) handleSourceReport(w http.ResponseWriter, r *http.Request) {
	rep, err := freshness.BuildReport(s.db)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, rep)
}

type sourceReviewedRequest struct {
	URL string `json:"url"`
}

// handleSourceReviewed lets an admin say "I checked; the guide is still right".
func (s *Server) handleSourceReviewed(w http.ResponseWriter, r *http.Request) {
	var body sourceReviewedRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.URL == "" {
		writeError(w, http.StatusBadRequest, "url is required")
		return
	}
	found, err := freshness.MarkReviewed(s.db, body.URL)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if !found {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	s.handleSourceReport(w, r)
}
