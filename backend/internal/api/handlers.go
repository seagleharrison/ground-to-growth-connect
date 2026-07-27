package api

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"ground-to-growth-connect-backend/internal/consent"
	"ground-to-growth-connect-backend/internal/cryptox"
)

var personTypes = []string{"homeless", "volunteer", "employee", "admin"}
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
	}, nil
}

// --- users ---

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

	staffInvite := os.Getenv("STAFF_INVITE_CODE")
	if staffInvite == "" {
		staffInvite = "g2g-staff"
	}
	if isStaff(personType) && body.StaffCode != staffInvite {
		writeError(w, http.StatusForbidden, "A valid staff invite code is required for staff accounts.")
		return
	}

	token, err := cryptox.GenerateToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	tokenHash := cryptox.HashToken(token)

	nameTrunc := truncateRunes(name, 200)
	nameEnc, err := cryptox.EncryptString(&nameTrunc)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	var emailEnc []byte
	if e := strings.TrimSpace(body.Email); e != "" {
		e = truncateRunes(e, 200)
		if emailEnc, err = cryptox.EncryptString(&e); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
	}

	var genderEnc []byte
	if body.Gender != "" {
		g := body.Gender
		if genderEnc, err = cryptox.EncryptString(&g); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
	}

	var phoneEnc []byte
	if p := strings.TrimSpace(body.Phone); p != "" {
		p = truncateRunes(p, 40)
		if phoneEnc, err = cryptox.EncryptString(&p); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
	}

	var u authUser
	u.PersonType = personType
	err = s.db.QueryRow(
		`INSERT INTO users (person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted, token_hash)
		 VALUES (?, ?, ?, ?, ?, ?)
		 RETURNING id, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted`,
		personType, nameEnc, emailEnc, genderEnc, phoneEnc, tokenHash,
	).Scan(&u.ID, &u.NameEncrypted, &u.EmailEncrypted, &u.GenderEncrypted, &u.PhoneEncrypted)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	profile, err := profileFromUser(&u)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"user":    profile,
		"token":   token,
		"message": "Store this token securely. It cannot be recovered.",
	})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	profile, err := profileFromUser(userFromCtx(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": profile})
}

func (s *Server) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	if _, err := s.db.Exec(`DELETE FROM users WHERE id = ?`, u.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

// --- consent ---

func (s *Server) handleDisclosure(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"version": consent.Version(),
		"text":    consent.DisclosureText(),
	})
}

func (s *Server) handleConsentStatus(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	var granted int64
	var consentVersion, grantedAt, revokedAt, lastRecordedAt sql.NullString

	err := s.db.QueryRow(
		`SELECT granted, consent_version, granted_at, revoked_at, last_recorded_at
		 FROM user_consent_status WHERE user_id = ?`,
		u.ID,
	).Scan(&granted, &consentVersion, &grantedAt, &revokedAt, &lastRecordedAt)

	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"granted": false,
			"version": consent.Version(),
		})
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
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

type consentRecordJSON struct {
	ID             string  `json:"id"`
	ConsentVersion *string `json:"consent_version"`
	Granted        bool    `json:"granted"`
	GrantedAt      *string `json:"granted_at"`
	RevokedAt      *string `json:"revoked_at"`
	CreatedAt      string  `json:"created_at"`
}

func (s *Server) handleConsentHistory(w http.ResponseWriter, r *http.Request) {
	u := userFromCtx(r)
	rows, err := s.db.Query(
		`SELECT id, consent_version, granted, granted_at, revoked_at, created_at
		 FROM consent_records WHERE user_id = ? ORDER BY created_at DESC LIMIT 50`,
		u.ID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	records := []consentRecordJSON{}
	for rows.Next() {
		var rec consentRecordJSON
		var version, grantedAt, revokedAt sql.NullString
		var granted int64
		if err := rows.Scan(&rec.ID, &version, &granted, &grantedAt, &revokedAt, &rec.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
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

type setConsentRequest struct {
	Granted *bool `json:"granted"`
}

func (s *Server) handleSetConsent(w http.ResponseWriter, r *http.Request) {
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
		   (user_id, consent_version, disclosure_text, granted, granted_at, revoked_at, user_agent_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 RETURNING id, consent_version, granted, granted_at, revoked_at, created_at`,
		u.ID, consent.Version(), consent.DisclosureText(), boolToInt(*body.Granted), grantedAtArg, revokedAtArg, uaHashArg,
	).Scan(&rec.ID, &version, &grantedInt, &ga, &ra, &rec.CreatedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}

	rec.ConsentVersion = toPtr(version)
	rec.Granted = grantedInt != 0
	rec.GrantedAt = toPtr(ga)
	rec.RevokedAt = toPtr(ra)

	writeJSON(w, http.StatusOK, map[string]interface{}{"record": rec})
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
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	lngEnc, err := cryptox.EncryptCoordinate(gridLng)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
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
		writeError(w, http.StatusInternalServerError, "Internal server error")
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
		    ROW_NUMBER() OVER (
		      PARTITION BY lr.user_id ORDER BY lr.reported_at DESC, lr.id DESC
		    ) AS rn
		  FROM location_reports lr
		  JOIN users u ON u.id = lr.user_id
		  JOIN user_consent_status cs ON cs.user_id = u.id AND cs.granted = 1
		  WHERE u.person_type = 'homeless'
		)
		WHERE rn = 1`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	locations := []userLocationJSON{}
	for rows.Next() {
		var nameEnc, latEnc, lngEnc []byte
		var accuracy sql.NullFloat64
		var loc userLocationJSON
		if err := rows.Scan(&loc.UserID, &nameEnc, &loc.PersonType, &latEnc, &lngEnc, &accuracy, &loc.ReportedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		name, err := cryptox.DecryptString(nameEnc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		lat, err := cryptox.DecryptCoordinate(latEnc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		lng, err := cryptox.DecryptCoordinate(lngEnc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
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
		writeError(w, http.StatusInternalServerError, "Internal server error")
		return
	}
	defer rows.Close()

	reports := []myLocationJSON{}
	for rows.Next() {
		var latEnc, lngEnc []byte
		var accuracy sql.NullFloat64
		var rep myLocationJSON
		if err := rows.Scan(&latEnc, &lngEnc, &accuracy, &rep.ReportedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		lat, err := cryptox.DecryptCoordinate(latEnc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
			return
		}
		lng, err := cryptox.DecryptCoordinate(lngEnc)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Internal server error")
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
