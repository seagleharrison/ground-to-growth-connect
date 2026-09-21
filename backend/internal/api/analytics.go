package api

import (
	"net/http"
	"time"
	_ "time/tzdata" // the runtime image has no system time zone database
)

// analyticsDays is how many recent days the daily breakdown covers.
const analyticsDays = 14

// analyticsZone is where the organization works; "today" and each day's
// boundaries follow Savannah's clock, not UTC.
const analyticsZone = "America/New_York"

type analyticsPeople struct {
	Participants int `json:"participants"`
	Volunteers   int `json:"volunteers"`
	Employees    int `json:"employees"`
	Admins       int `json:"admins"`
}

type analyticsSharing struct {
	ParticipantsSharing int `json:"participantsSharing"`
	ActiveLast24Hours   int `json:"activeLast24Hours"`
	ActiveLast7Days     int `json:"activeLast7Days"`
}

type analyticsDocuments struct {
	ParticipantsUsingStorage int `json:"participantsUsingStorage"`
	ParticipantsWithAllThree int `json:"participantsWithAllThree"`
	DocumentsStored          int `json:"documentsStored"`
}

type analyticsDay struct {
	Date     string `json:"date"` // yyyy-MM-dd in Savannah time
	Signups  int    `json:"signups"`
	CheckIns int    `json:"checkIns"`
}

type analyticsResponse struct {
	GeneratedAt string             `json:"generatedAt"`
	People      analyticsPeople    `json:"people"`
	Sharing     analyticsSharing   `json:"sharing"`
	Documents   analyticsDocuments `json:"documents"`
	Daily       []analyticsDay     `json:"daily"` // oldest first, ends with today
}

// withAdmin lets only admin accounts through. Staff roles (volunteer,
// employee) can see the map but not the organization-wide numbers.
func (s *Server) withAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if userFromCtx(r).PersonType != "admin" {
			writeError(w, http.StatusForbidden, "Admin access required")
			return
		}
		next(w, r)
	}
}

func isoAt(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000Z") }

// handleAnalytics returns organization-wide totals. It is aggregate only: no
// names, no locations, no document contents — just counts.
func (s *Server) handleAnalytics(w http.ResponseWriter, r *http.Request) {
	loc, err := time.LoadLocation(analyticsZone)
	if err != nil {
		writeInternalError(w, err)
		return
	}
	now := time.Now()

	var out analyticsResponse
	out.GeneratedAt = isoAt(now)

	count := func(dest *int, query string, args ...interface{}) bool {
		if err := s.db.QueryRow(query, args...).Scan(dest); err != nil {
			writeInternalError(w, err)
			return false
		}
		return true
	}

	ok := count(&out.People.Participants, `SELECT COUNT(*) FROM users WHERE person_type = 'homeless'`) &&
		count(&out.People.Volunteers, `SELECT COUNT(*) FROM users WHERE person_type = 'volunteer'`) &&
		count(&out.People.Employees, `SELECT COUNT(*) FROM users WHERE person_type = 'employee'`) &&
		count(&out.People.Admins, `SELECT COUNT(*) FROM users WHERE person_type = 'admin'`) &&
		count(&out.Sharing.ParticipantsSharing,
			`SELECT COUNT(*) FROM user_consent_status cs JOIN users u ON u.id = cs.user_id
			 WHERE cs.consent_type = ? AND cs.granted = 1 AND u.person_type = 'homeless'`, consentTypeLocation) &&
		count(&out.Sharing.ActiveLast24Hours,
			`SELECT COUNT(DISTINCT lr.user_id) FROM location_reports lr JOIN users u ON u.id = lr.user_id
			 WHERE u.person_type = 'homeless' AND lr.created_at >= ?`, isoAt(now.Add(-24*time.Hour))) &&
		count(&out.Sharing.ActiveLast7Days,
			`SELECT COUNT(DISTINCT lr.user_id) FROM location_reports lr JOIN users u ON u.id = lr.user_id
			 WHERE u.person_type = 'homeless' AND lr.created_at >= ?`, isoAt(now.Add(-7*24*time.Hour))) &&
		count(&out.Documents.ParticipantsUsingStorage,
			`SELECT COUNT(*) FROM user_consent_status cs JOIN users u ON u.id = cs.user_id
			 WHERE cs.consent_type = ? AND cs.granted = 1 AND u.person_type = 'homeless'`, consentTypeDocuments) &&
		count(&out.Documents.ParticipantsWithAllThree,
			`SELECT COUNT(*) FROM (
			   SELECT d.user_id FROM documents d JOIN users u ON u.id = d.user_id
			   WHERE u.person_type = 'homeless'
			     AND d.document_type IN ('government_id', 'social_security_card', 'birth_certificate')
			   GROUP BY d.user_id HAVING COUNT(DISTINCT d.document_type) = 3)`) &&
		count(&out.Documents.DocumentsStored, `SELECT COUNT(*) FROM documents`)
	if !ok {
		return
	}

	// One row per local day, oldest first. Each day runs from local midnight
	// to the next local midnight, so late-evening check-ins land on the right day.
	today := time.Date(now.In(loc).Year(), now.In(loc).Month(), now.In(loc).Day(), 0, 0, 0, 0, loc)
	for i := analyticsDays - 1; i >= 0; i-- {
		start := today.AddDate(0, 0, -i)
		end := start.AddDate(0, 0, 1)
		day := analyticsDay{Date: start.Format("2006-01-02")}
		if !count(&day.Signups, `SELECT COUNT(*) FROM users WHERE created_at >= ? AND created_at < ?`, isoAt(start), isoAt(end)) ||
			!count(&day.CheckIns, `SELECT COUNT(*) FROM location_reports WHERE created_at >= ? AND created_at < ?`, isoAt(start), isoAt(end)) {
			return
		}
		out.Daily = append(out.Daily, day)
	}

	writeJSON(w, http.StatusOK, out)
}
