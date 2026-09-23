package api

import (
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"ground-to-growth-connect-backend/internal/consent"
	"ground-to-growth-connect-backend/internal/cryptox"
)

var personTypes = []string{"homeless", "volunteer", "admin"}
var genders = []string{"female", "male", "nonbinary", "other", "prefer_not_to_say"}

func contains(list []string, v string) bool {
	for _, item := range list {
		if item == v {
			return true
		}
	}
	return false
}

func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		return string(r[:n])
	}
	return s
}

func toPtr(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	v := ns.String
	return &v
}

func nowISO() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
}

// parseReportedAt mirrors `reportedAt ? new Date(reportedAt) : new Date()`
// followed by the pg-shim's `Date -> toISOString()` normalization.
func parseReportedAt(raw *string) (string, error) {
	if raw == nil || *raw == "" {
		return nowISO(), nil
	}
	layouts := []string{time.RFC3339Nano, time.RFC3339}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, *raw); err == nil {
			return t.UTC().Format("2006-01-02T15:04:05.000Z"), nil
		}
	}
	return "", fmt.Errorf("invalid reportedAt value: %q", *raw)
}

// --- user profile ---

type userProfile struct {
	ID         string  `json:"id"`
	PersonType string  `json:"personType"`
	Name       *string `json:"name"`
	Email      *string `json:"email"`
	Gender     *string `json:"gender"`
	Phone      *string `json:"phone"`
	IsStaff    bool    `json:"isStaff"`

	HasProfilePicture bool `json:"hasProfilePicture"`
}

func profileFromUser(u *authUser) (*userProfile, error) {
	name, err := cryptox.DecryptString(u.NameEncrypted)
	if err != nil {
		return nil, err
	}
	email, err := cryptox.DecryptString(u.EmailEncrypted)
	if err != nil {
		return nil, err
	}
	gender, err := cryptox.DecryptString(u.GenderEncrypted)
	if err != nil {
		return nil, err
	}
	phone, err := cryptox.DecryptString(u.PhoneEncrypted)
	if err != nil {
		return nil, err
	}
	return &userProfile{
		ID:         u.ID,
		PersonType: u.PersonType,
		Name:       name,
		Email:      email,
		Gender:     gender,
		Phone:      phone,
		IsStaff:    isStaff(u.PersonType),

		HasProfilePicture: u.ProfilePictureKey.Valid,
	}, nil
}

// --- users ---

// validStaffCode reports whether code matches the invite code that lets
// someone hold a staff account. It is the single gate for both signing up as
// staff and switching an existing account to a staff role.
func validStaffCode(code string) bool {
	invite := os.Getenv("STAFF_INVITE_CODE")
	if invite == "" {
		invite = "g2g-staff"
	}
	return subtle.ConstantTimeCompare([]byte(code), []byte(invite)) == 1
}

type registerRequest struct {
	Name       string `json:"name"`
	Email      string `json:"email"`
	Gender     string `json:"gender"`
	Phone      string `json:"phone"`
	PersonType string `json:"personType"`
	StaffCode  string `json:"staffCode"`
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var body registerRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}

	name := strings.TrimSpace(body.Name)
	if name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if strings.TrimSpace(body.Phone) == "" {
		writeError(w, http.StatusBadRequest, "phone is required")
		return
	}

	personType := body.PersonType
	if personType == "" {
		personType = "homeless"
	}
	if !contains(personTypes, personType) {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("personType must be one of: %s", strings.Join(personTypes, ", ")))
		return
	}
	if body.Gender != "" && !contains(genders, body.Gender) {
		writeError(w, http.StatusBadRequest, fmt.Sprintf("gender must be one of: %s", strings.Join(genders, ", ")))
		return
	}

	if isStaff(personType) && !validStaffCode(body.StaffCode) {
		writeError(w, http.StatusForbidden, "A valid staff invite code is required for staff accounts.")
		return
	}

	token, err := cryptox.GenerateToken()
	if err != nil {
		writeInternalError(w, err)
		return
	}
	recoveryCode, err := cryptox.GenerateRecoveryCode()
	if err != nil {
		writeInternalError(w, err)
		return
	}
	tokenHash := cryptox.HashToken(token)

	nameTrunc := truncateRunes(name, 200)
	nameEnc, err := cryptox.EncryptString(&nameTrunc)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	var emailEnc []byte
	if e := strings.TrimSpace(body.Email); e != "" {
		e = truncateRunes(e, 200)
		if emailEnc, err = cryptox.EncryptString(&e); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	var genderEnc []byte
	if body.Gender != "" {
		g := body.Gender
		if genderEnc, err = cryptox.EncryptString(&g); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	var phoneEnc []byte
	if p := strings.TrimSpace(body.Phone); p != "" {
		p = truncateRunes(p, 40)
		if phoneEnc, err = cryptox.EncryptString(&p); err != nil {
			writeInternalError(w, err)
			return
		}
	}

	var u authUser
	u.PersonType = personType
	err = s.db.QueryRow(
		`INSERT INTO users (person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted, token_hash, recovery_code_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 RETURNING id, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted`,
		personType, nameEnc, emailEnc, genderEnc, phoneEnc, tokenHash, cryptox.HashRecoveryCode(recoveryCode),
	).Scan(&u.ID, &u.NameEncrypted, &u.EmailEncrypted, &u.GenderEncrypted, &u.PhoneEncrypted)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	profile, err := profileFromUser(&u)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"user":         profile,
		"token":        token,
		"recoveryCode": recoveryCode,
		"message":      "Store this token securely. It cannot be recovered.",
	})
}

type recoverRequest struct {
	Code string `json:"code"`
}

// handleRecover lets someone who lost their phone, or changed numbers,
// get back into their existing account with only the recovery code they
// were given at sign-up — no email, no password, nothing else on file is
// required. A new token is issued and the old one stops working, the same
// way changing a password ends every other session.
func (s *Server) handleRecover(w http.ResponseWriter, r *http.Request) {
	var body recoverRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	normalized := cryptox.NormalizeRecoveryCode(body.Code)
	if normalized == "" {
		writeError(w, http.StatusBadRequest, "code is required")
		return
	}

	token, err := cryptox.GenerateToken()
	if err != nil {
		writeInternalError(w, err)
		return
	}

	var u authUser
	err = s.db.QueryRow(
		`UPDATE users SET token_hash = ? WHERE recovery_code_hash = ?
		 RETURNING id, person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted, profile_picture_key, profile_picture_mime`,
		cryptox.HashToken(token), cryptox.HashRecoveryCode(normalized),
	).Scan(&u.ID, &u.PersonType, &u.NameEncrypted, &u.EmailEncrypted, &u.GenderEncrypted, &u.PhoneEncrypted, &u.ProfilePictureKey, &u.ProfilePictureMime)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "That recovery code doesn't match any account. Double-check it, or ask Ground to Growth for help.")
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}

	profile, err := profileFromUser(&u)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"user":    profile,
		"token":   token,
		"message": "You're back in. Any other device using this account was signed out.",
	})
}

// handleRegenerateRecoveryCode replaces the account's recovery code with a
// new one, e.g. if someone lost the paper it was written on. The old code
// stops working the moment this runs.
func (s *Server) handleRegenerateRecoveryCode(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	recoveryCode, err := cryptox.GenerateRecoveryCode()
	if err != nil {
		writeInternalError(w, err)
		return
	}
	if _, err := s.db.Exec(`UPDATE users SET recovery_code_hash = ? WHERE id = ?`, cryptox.HashRecoveryCode(recoveryCode), u.ID); err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"recoveryCode": recoveryCode,
		"message":      "Store this new code securely. The old one no longer works.",
	})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	profile, err := profileFromUser(userFromCtx(r))
	if err != nil {
		writeInternalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": profile})
}

func (s *Server) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	// Collect every stored file before the rows that point at them are gone.
	// Deleting only the database rows would leave the encrypted files behind
	// in the blob store, which is not what "delete my data" promises.
	var blobKeys []string
	rows, err := s.db.Query(`SELECT storage_key FROM documents WHERE user_id = ?`, u.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	for rows.Next() {
		var key string
		if err := rows.Scan(&key); err != nil {
			rows.Close()
			writeInternalError(w, err)
			return
		}
		blobKeys = append(blobKeys, key)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		writeInternalError(w, err)
		return
	}
	if u.ProfilePictureKey.Valid {
		blobKeys = append(blobKeys, u.ProfilePictureKey.String)
	}

	if _, err := s.db.Exec(`DELETE FROM users WHERE id = ?`, u.ID); err != nil {
		writeInternalError(w, err)
		return
	}

	for _, key := range blobKeys {
		if err := s.docs.Delete(r.Context(), key); err != nil {
			log.Printf("orphaned blob %s after account deletion: %v", key, err)
		}
	}
	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

// --- consent ---
//
// Location sharing and document storage are independent consent flows
// (consent_type in the DB); the handlers below are thin, type-specific
// wrappers around shared logic so both sets of routes behave identically.

func (s *Server) handleDisclosure(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": consent.Version(),
		"text":    consent.LocationDisclosureText(),
	})
}

func (s *Server) handleDocumentDisclosure(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": consent.Version(),
		"text":    consent.DocumentDisclosureText(),
	})
}

func (s *Server) consentStatus(w http.ResponseWriter, r *http.Request, consentType string) {
	u := userFromCtx(r)
	var granted int64
	var consentVersion, grantedAt, revokedAt, lastRecordedAt sql.NullString

	err := s.db.QueryRow(
		`SELECT granted, consent_version, granted_at, revoked_at, last_recorded_at
		 FROM user_consent_status WHERE user_id = ? AND consent_type = ?`,
		u.ID, consentType,
	).Scan(&granted, &consentVersion, &grantedAt, &revokedAt, &lastRecordedAt)

	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"granted": false,
			"version": consent.Version(),
		})
		return
	}
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"granted":          granted != 0,
		"consent_version":  toPtr(consentVersion),
		"granted_at":       toPtr(grantedAt),
		"revoked_at":       toPtr(revokedAt),
		"last_recorded_at": toPtr(lastRecordedAt),
	})
}

func (s *Server) handleConsentStatus(w http.ResponseWriter, r *http.Request) {
	s.consentStatus(w, r, consentTypeLocation)
}

func (s *Server) handleDocumentConsentStatus(w http.ResponseWriter, r *http.Request) {
	s.consentStatus(w, r, consentTypeDocuments)
}

type consentRecordJSON struct {
	ID             string  `json:"id"`
	ConsentVersion *string `json:"consent_version"`
	Granted        bool    `json:"granted"`
	GrantedAt      *string `json:"granted_at"`
	RevokedAt      *string `json:"revoked_at"`
	CreatedAt      string  `json:"created_at"`
}

func (s *Server) consentHistory(w http.ResponseWriter, r *http.Request, consentType string) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT id, consent_version, granted, granted_at, revoked_at, created_at
		 FROM consent_records WHERE user_id = ? AND consent_type = ? ORDER BY created_at DESC LIMIT 50`,
		u.ID, consentType,
	)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	records := []consentRecordJSON{}
	for rows.Next() {
		var rec consentRecordJSON
		var version, grantedAt, revokedAt sql.NullString
		var granted int64
		if err := rows.Scan(&rec.ID, &version, &granted, &grantedAt, &revokedAt, &rec.CreatedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		rec.ConsentVersion = toPtr(version)
		rec.Granted = granted != 0
		rec.GrantedAt = toPtr(grantedAt)
		rec.RevokedAt = toPtr(revokedAt)
		records = append(records, rec)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"records": records})
}

func (s *Server) handleConsentHistory(w http.ResponseWriter, r *http.Request) {
	s.consentHistory(w, r, consentTypeLocation)
}

func (s *Server) handleDocumentConsentHistory(w http.ResponseWriter, r *http.Request) {
	s.consentHistory(w, r, consentTypeDocuments)
}

type setConsentRequest struct {
	Granted *bool `json:"granted"`
}

func (s *Server) setConsent(w http.ResponseWriter, r *http.Request, consentType, disclosureText string) {
	u := userFromCtx(r)

	var body setConsentRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Granted == nil {
		writeError(w, http.StatusBadRequest, "granted must be a boolean")
		return
	}

	now := nowISO()
	var uaHashArg interface{}
	if h := cryptox.HashUserAgent(r.Header.Get("User-Agent")); h != nil {
		uaHashArg = *h
	}

	var grantedAtArg, revokedAtArg interface{}
	if *body.Granted {
		grantedAtArg = now
	} else {
		revokedAtArg = now
	}

	var rec consentRecordJSON
	var version, ga, ra sql.NullString
	var grantedInt int64
	err := s.db.QueryRow(
		`INSERT INTO consent_records
		   (user_id, consent_type, consent_version, disclosure_text, granted, granted_at, revoked_at, user_agent_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 RETURNING id, consent_version, granted, granted_at, revoked_at, created_at`,
		u.ID, consentType, consent.Version(), disclosureText, boolToInt(*body.Granted), grantedAtArg, revokedAtArg, uaHashArg,
	).Scan(&rec.ID, &version, &grantedInt, &ga, &ra, &rec.CreatedAt)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	rec.ConsentVersion = toPtr(version)
	rec.Granted = grantedInt != 0
	rec.GrantedAt = toPtr(ga)
	rec.RevokedAt = toPtr(ra)

	writeJSON(w, http.StatusOK, map[string]interface{}{"record": rec})
}

func (s *Server) handleSetConsent(w http.ResponseWriter, r *http.Request) {
	s.setConsent(w, r, consentTypeLocation, consent.LocationDisclosureText())
}

func (s *Server) handleSetDocumentConsent(w http.ResponseWriter, r *http.Request) {
	s.setConsent(w, r, consentTypeDocuments, consent.DocumentDisclosureText())
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// --- locations ---

type locationRequest struct {
	Latitude       *float64 `json:"latitude"`
	Longitude      *float64 `json:"longitude"`
	AccuracyMeters *float64 `json:"accuracyMeters"`
	ReportedAt     *string  `json:"reportedAt"`
}

type locationReportJSON struct {
	ID         string `json:"id"`
	ReportedAt string `json:"reported_at"`
	CreatedAt  string `json:"created_at"`
}

func (s *Server) handleCreateLocation(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)

	var body locationRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid JSON body")
		return
	}
	if body.Latitude == nil || body.Longitude == nil {
		writeError(w, http.StatusBadRequest, "latitude and longitude are required numbers")
		return
	}
	lat, lng := *body.Latitude, *body.Longitude
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		writeError(w, http.StatusBadRequest, "Invalid coordinates")
		return
	}

	reportedAt, err := parseReportedAt(body.ReportedAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Invalid reportedAt value")
		return
	}

	gridLat, gridLng := cryptox.SnapToGrid(lat, lng)
	latEnc, err := cryptox.EncryptCoordinate(gridLat)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	lngEnc, err := cryptox.EncryptCoordinate(gridLng)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	var accuracyArg interface{}
	if body.AccuracyMeters != nil {
		accuracyArg = *body.AccuracyMeters
	}

	var rec locationReportJSON
	err = s.db.QueryRow(
		`INSERT INTO location_reports
		   (user_id, latitude_encrypted, longitude_encrypted, accuracy_meters, reported_at)
		 VALUES (?, ?, ?, ?, ?)
		 RETURNING id, reported_at, created_at`,
		u.ID, latEnc, lngEnc, accuracyArg, reportedAt,
	).Scan(&rec.ID, &rec.ReportedAt, &rec.CreatedAt)
	if err != nil {
		writeInternalError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{"report": rec})
}

type userLocationJSON struct {
	UserID         string   `json:"userId"`
	Name           *string  `json:"name"`
	PersonType     string   `json:"personType"`
	Latitude       float64  `json:"latitude"`
	Longitude      float64  `json:"longitude"`
	AccuracyMeters *float64 `json:"accuracyMeters"`
	ReportedAt     string   `json:"reportedAt"`
}

func (s *Server) handleLatestLocations(w http.ResponseWriter, r *http.Request) {
	viewer := userFromCtx(r)
	rows, err := s.db.Query(`
		SELECT user_id, name_encrypted, person_type, latitude_encrypted, longitude_encrypted,
		       accuracy_meters, reported_at
		FROM (
		  SELECT
		    u.id AS user_id,
		    u.name_encrypted,
		    u.person_type,
		    lr.latitude_encrypted,
		    lr.longitude_encrypted,
		    lr.accuracy_meters,
		    lr.reported_at,
		    -- Tie-break on rowid (insertion order), not id: id is a random
		    -- UUID and carries no ordering information within the same
		    -- reported_at millisecond.
		    ROW_NUMBER() OVER (
		      PARTITION BY lr.user_id ORDER BY lr.reported_at DESC, lr.rowid DESC
		    ) AS rn
		  FROM location_reports lr
		  JOIN users u ON u.id = lr.user_id
		  JOIN user_consent_status cs ON cs.user_id = u.id AND cs.granted = 1
		  -- Everyone who is sharing shows up here: participants, and staff who
		  -- turned on their own sharing so other staff can find them in the
		  -- field. A person never sees themselves in this list.
		  WHERE u.id != ?
		)
		WHERE rn = 1`, viewer.ID)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	locations := []userLocationJSON{}
	for rows.Next() {
		var nameEnc, latEnc, lngEnc []byte
		var accuracy sql.NullFloat64
		var loc userLocationJSON
		if err := rows.Scan(&loc.UserID, &nameEnc, &loc.PersonType, &latEnc, &lngEnc, &accuracy, &loc.ReportedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		name, err := cryptox.DecryptString(nameEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		lat, err := cryptox.DecryptCoordinate(latEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		lng, err := cryptox.DecryptCoordinate(lngEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		loc.Name = name
		loc.Latitude = lat
		loc.Longitude = lng
		if accuracy.Valid {
			v := accuracy.Float64
			loc.AccuracyMeters = &v
		}
		locations = append(locations, loc)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"locations": locations})
}

type myLocationJSON struct {
	Latitude       float64  `json:"latitude"`
	Longitude      float64  `json:"longitude"`
	AccuracyMeters *float64 `json:"accuracyMeters"`
	ReportedAt     string   `json:"reportedAt"`
}

func (s *Server) handleMyLocations(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT latitude_encrypted, longitude_encrypted, accuracy_meters, reported_at
		 FROM location_reports WHERE user_id = ? ORDER BY reported_at DESC LIMIT 100`,
		u.ID,
	)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	defer rows.Close()

	reports := []myLocationJSON{}
	for rows.Next() {
		var latEnc, lngEnc []byte
		var accuracy sql.NullFloat64
		var rep myLocationJSON
		if err := rows.Scan(&latEnc, &lngEnc, &accuracy, &rep.ReportedAt); err != nil {
			writeInternalError(w, err)
			return
		}
		lat, err := cryptox.DecryptCoordinate(latEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		lng, err := cryptox.DecryptCoordinate(lngEnc)
		if err != nil {
			writeInternalError(w, err)
			return
		}
		rep.Latitude = lat
		rep.Longitude = lng
		if accuracy.Valid {
			v := accuracy.Float64
			rep.AccuracyMeters = &v
		}
		reports = append(reports, rep)
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"reports": reports})
}
