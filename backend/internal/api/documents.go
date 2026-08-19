package api

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"

	"ground-to-growth-connect-backend/internal/cryptox"
)

var documentTypes = []string{"government_id", "social_security_card", "birth_certificate", "other"}
var documentMimeTypes = []string{"image/jpeg", "image/png", "application/pdf"}

// maxDocumentUploadBytes overrides the global 16kb request-body cap for this
// one route: scanned documents are real files, not small JSON payloads.
// Sized generously for a base64-encoded (~33% larger than raw) scan or PDF.
const maxDocumentUploadBytes = 20 * 1024 * 1024

type documentMetaJSON struct {
	ID            string  `json:"id"`
	DocumentType  string  `json:"documentType"`
	Label         *string `json:"label"`
	MimeType      string  `json:"mimeType"`
	FileSizeBytes int64   `json:"fileSizeBytes"`
	CreatedAt     string  `json:"createdAt"`
}

type uploadDocumentRequest struct {
	DocumentType string  `json:"documentType"`
	Label        *string `json:"label"`
	MimeType     string  `json:"mimeType"`
	FileBase64   string  `json:"fileBase64"`
}

// newDocumentID generates a UUIDv4, independent of SQLite's id-generation
// expression, because the blob store key needs the id before the row exists.
func newDocumentID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

func documentStorageKey(userID, docID string) string {
	return "documents/" + userID + "/" + docID + ".enc"
}

func (s *Server) handleUploadDocument(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	ctx := r.Context()

	// Overrides the global 16kb cap set in withMiddleware — documents are
	// real files, this route specifically needs more room.
	r.Body = http.MaxBytesReader(w, r.Body, maxDocumentUploadBytes)

	var body uploadDocumentRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body, or file too large")
		return
	}

	if !contains(documentTypes, body.DocumentType) {
		writeError(w, http.StatusBadRequest, "documentType must be one of: "+strings.Join(documentTypes, ", "))
		return
	}
	if !contains(documentMimeTypes, body.MimeType) {
		writeError(w, http.StatusBadRequest, "mimeType must be one of: "+strings.Join(documentMimeTypes, ", "))
		return
	}
	if body.FileBase64 == "" {
		writeError(w, http.StatusBadRequest, "fileBase64 is required")
		return
	}

	fileBytes, err := base64.StdEncoding.DecodeString(body.FileBase64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "fileBase64 is not valid base64")
		return
	}
	if len(fileBytes) == 0 {
		writeError(w, http.StatusBadRequest, "file is empty")
		return
	}

	var labelArg interface{}
	if body.Label != nil {
		trimmed := strings.TrimSpace(*body.Label)
		if trimmed != "" {
			labelArg = truncateRunes(trimmed, 100)
		}
	}

	fileEnc, err := cryptox.EncryptBytes(fileBytes)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	docID, err := newDocumentID()
	if err != nil {
		writeInternalError(w, err)
		return
	}
	storageKey := documentStorageKey(u.ID, docID)

	// Write the blob first: if this fails, nothing references it, so there's
	// nothing to clean up. If the DB insert below fails instead, we do have
	// to clean up the blob we just wrote (see below).
	if err := s.docs.Put(ctx, storageKey, fileEnc); err != nil {
		writeInternalError(w, err)
		return
	}

	var meta documentMetaJSON
	var label sql.NullString
	err = s.db.QueryRow(
		`INSERT INTO documents (id, user_id, document_type, label, mime_type, storage_key, file_size_bytes)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 RETURNING id, document_type, label, mime_type, file_size_bytes, created_at`,
		docID, u.ID, body.DocumentType, labelArg, body.MimeType, storageKey, len(fileBytes),
	).Scan(&meta.ID, &meta.DocumentType, &label, &meta.MimeType, &meta.FileSizeBytes, &meta.CreatedAt)
	if err != nil {
		if delErr := s.docs.Delete(ctx, storageKey); delErr != nil {
			log.Printf("orphaned blob %s after failed insert: %v", storageKey, delErr)
		}
		writeInternalError(w, err)
		return
	}
	meta.Label = toPtr(label)

	writeJSON(w, http.StatusCreated, map[string]interface{}{"document": meta})
}

func (s *Server) handleListDocuments(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT id, document_type, label, mime_type, file_size_bytes, created_at
		 FROM documents WHERE user_id = ? ORDER BY created_at DESC`,
		u.ID,
	)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	documents := []documentMetaJSON{}
	for rows.Next() {
		var meta documentMetaJSON
		var label sql.NullString
		if err := rows.Scan(&meta.ID, &meta.DocumentType, &label, &meta.MimeType, &meta.FileSizeBytes, &meta.CreatedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		meta.Label = toPtr(label)
		documents = append(documents, meta)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"documents": documents})
}

func (s *Server) handleGetDocument(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	ctx := r.Context()

	var meta documentMetaJSON
	var label sql.NullString
	var storageKey string
	err := s.db.QueryRow(
		`SELECT id, document_type, label, mime_type, file_size_bytes, created_at, storage_key
		 FROM documents WHERE id = ? AND user_id = ?`,
		id, u.ID,
	).Scan(&meta.ID, &meta.DocumentType, &label, &meta.MimeType, &meta.FileSizeBytes, &meta.CreatedAt, &storageKey)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}
	meta.Label = toPtr(label)

	fileEnc, err := s.docs.Get(ctx, storageKey)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	fileBytes, err := cryptox.DecryptBytes(fileEnc)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	if _, err := s.db.Exec(
		`INSERT INTO document_access_log (document_id, user_id) VALUES (?, ?)`,
		meta.ID, u.ID,
	); err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"document":   meta,
		"fileBase64": base64.StdEncoding.EncodeToString(fileBytes),
	})
}

func (s *Server) handleDeleteDocument(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	id := r.PathValue("id")
	ctx := r.Context()

	var storageKey string
	err := s.db.QueryRow(
		`DELETE FROM documents WHERE id = ? AND user_id = ? RETURNING storage_key`,
		id, u.ID,
	).Scan(&storageKey)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Not found")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}

	// The DB row is already gone — the document is inaccessible to the user
	// either way — so a blob-delete failure here is logged, not fatal.
	if err := s.docs.Delete(ctx, storageKey); err != nil {
		log.Printf("failed to delete blob %s: %v", storageKey, err)
	}

	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

// --- staff visibility: existence only, never content ---

type documentsOnFileJSON struct {
	UserID        string   `json:"userId"`
	Name          *string  `json:"name"`
	DocumentTypes []string `json:"documentTypes"`
}

// handleDocumentsOnFile lets staff see which document *types* a participant
// has stored, so they know e.g. "ID on file: yes" — the query never selects
// storage_key, so document content is architecturally unreachable from this
// code path (and even with a key, the blob store only ever holds encrypted
// bytes).
func (s *Server) handleDocumentsOnFile(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`
		SELECT u.id, u.name_encrypted, d.document_type
		FROM documents d
		JOIN users u ON u.id = d.user_id
		WHERE u.person_type = 'homeless'
		ORDER BY u.id, d.document_type`)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	order := []string{}
	byUser := map[string]*documentsOnFileJSON{}
	nameByUser := map[string][]byte{}

	for rows.Next() {
		var userID, docType string
		var nameEnc []byte
		if err := rows.Scan(&userID, &nameEnc, &docType); err != nil {
			writeInternalError(w, err)
			return
		}
		entry, ok := byUser[userID]
		if !ok {
			entry = &documentsOnFileJSON{UserID: userID, DocumentTypes: []string{}}
			byUser[userID] = entry
			nameByUser[userID] = nameEnc
			order = append(order, userID)
		}
		entry.DocumentTypes = append(entry.DocumentTypes, docType)
	}

	participants := make([]documentsOnFileJSON, 0, len(order))
	for _, userID := range order {
		entry := byUser[userID]
		name, err := cryptox.DecryptString(nameByUser[userID])
		if err != nil {
			writeInternalError(w, err)
			return
		}
		entry.Name = name
		participants = append(participants, *entry)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"participants": participants})
}
