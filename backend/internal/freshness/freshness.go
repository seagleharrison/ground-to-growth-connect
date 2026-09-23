// Package freshness keeps an eye on the official pages the Resources tab
// points to. It can't tell whether wording is still right — only a person can —
// but it reliably notices when a page disappears or changes, so an admin can
// re-check that entry instead of it quietly going stale.
package freshness

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"html"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"
)

var (
	scriptOrStyle = regexp.MustCompile(`(?is)<(script|style|noscript)\b.*?</(script|style|noscript)>`)
	htmlComment   = regexp.MustCompile(`(?s)<!--.*?-->`)
	anyTag        = regexp.MustCompile(`(?s)<[^>]*>`)
	whitespace    = regexp.MustCompile(`\s+`)
)

// fingerprint hashes what a person would read on the page, ignoring markup,
// scripts and spacing, so cosmetic changes don't raise false alarms.
func fingerprint(body []byte) string {
	text := string(body)
	text = scriptOrStyle.ReplaceAllString(text, " ")
	text = htmlComment.ReplaceAllString(text, " ")
	text = anyTag.ReplaceAllString(text, " ")
	text = html.UnescapeString(text)
	text = strings.ToLower(whitespace.ReplaceAllString(text, " "))
	sum := sha256.Sum256([]byte(strings.TrimSpace(text)))
	return hex.EncodeToString(sum[:])
}

type Checker struct {
	DB      *sql.DB
	Client  *http.Client
	URLs    func() []string
	Now     func() time.Time
	Timeout time.Duration
}

func NewChecker(db *sql.DB, urls func() []string) *Checker {
	return &Checker{
		DB:      db,
		Client:  &http.Client{Timeout: 25 * time.Second},
		URLs:    urls,
		Now:     time.Now,
		Timeout: 25 * time.Second,
	}
}

func stamp(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000Z") }

// RunOnce checks every source once and records what it found.
func (c *Checker) RunOnce(ctx context.Context) {
	for _, u := range c.URLs() {
		if ctx.Err() != nil {
			return
		}
		status, hash, errText := c.fetch(ctx, u)
		if err := c.record(u, status, hash, errText); err != nil {
			log.Printf("freshness: recording %s: %v", u, err)
		}
	}
}

func (c *Checker) fetch(ctx context.Context, url string) (status int, hash string, errText string) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, "", err.Error()
	}
	req.Header.Set("User-Agent", "GroundToGrowthConnect-FreshnessCheck/1.0 (+https://groundtogrowth.org)")
	resp, err := c.Client.Do(req)
	if err != nil {
		return 0, "", err.Error()
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return resp.StatusCode, "", err.Error()
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return resp.StatusCode, "", ""
	}
	return resp.StatusCode, fingerprint(body), ""
}

func (c *Checker) record(url string, status int, hash, errText string) error {
	now := stamp(c.Now())
	good := status >= 200 && status < 300 && hash != ""

	// The first good reading is the baseline: it's what was true when someone
	// last reviewed the content, so it isn't "a change".
	_, err := c.DB.Exec(`
		INSERT INTO source_checks (url, status, error, content_hash, reviewed_hash, checked_at, first_checked_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(url) DO UPDATE SET
		  status = excluded.status,
		  error = excluded.error,
		  content_hash = CASE WHEN ? THEN excluded.content_hash ELSE source_checks.content_hash END,
		  reviewed_hash = COALESCE(source_checks.reviewed_hash, excluded.reviewed_hash),
		  checked_at = excluded.checked_at`,
		url, status, nullIfEmpty(errText), nullIfEmpty(hash), nullIfEmpty(hashIf(good, hash)), now, now, good,
	)
	return err
}

func hashIf(ok bool, h string) string {
	if ok {
		return h
	}
	return ""
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

// Loop runs a check shortly after start-up and then every interval, until ctx ends.
func (c *Checker) Loop(ctx context.Context, interval time.Duration) {
	timer := time.NewTimer(time.Minute)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
			c.RunOnce(ctx)
			timer.Reset(interval)
		}
	}
}

// Attention is one page an admin should look at again.
type Attention struct {
	URL       string `json:"url"`
	Reason    string `json:"reason"`
	Status    int    `json:"status"`
	CheckedAt string `json:"checkedAt"`
}

// Report is what the admin screen shows.
type Report struct {
	Total          int         `json:"total"`
	LastCheckedAt  string      `json:"lastCheckedAt"`
	NeedsAttention []Attention `json:"needsAttention"`

	// CannotCheck lists pages whose websites refuse automated visitors (many
	// government sites do this to everything that isn't a person with a
	// browser). That says nothing about whether the page is fine, so they aren't
	// counted as problems; an admin can open them now and then to confirm.
	CannotCheck []Attention `json:"cannotCheck"`
}

// refusesAutomatedVisitors reports whether an HTTP status is a site turning our
// checker away rather than saying the page is gone.
func refusesAutomatedVisitors(status int) bool {
	return status == http.StatusUnauthorized || status == http.StatusForbidden || status == http.StatusTooManyRequests
}

func BuildReport(db *sql.DB) (Report, error) {
	rep := Report{NeedsAttention: []Attention{}, CannotCheck: []Attention{}}
	rows, err := db.Query(`
		SELECT url, status, COALESCE(error, ''), content_hash, reviewed_hash, acknowledged_status, checked_at
		FROM source_checks ORDER BY url`)
	if err != nil {
		return rep, err
	}
	defer rows.Close()
	for rows.Next() {
		var url, errText, checkedAt string
		var status int
		var hash, reviewed sql.NullString
		var acked sql.NullInt64
		if err := rows.Scan(&url, &status, &errText, &hash, &reviewed, &acked, &checkedAt); err != nil {
			return rep, err
		}
		rep.Total++
		if checkedAt > rep.LastCheckedAt {
			rep.LastCheckedAt = checkedAt
		}
		switch {
		case refusesAutomatedVisitors(status):
			rep.CannotCheck = append(rep.CannotCheck, Attention{url, fmt.Sprintf("This website turns away automatic checks (HTTP %d), so we can't tell if it changed. Open it now and then to make sure it still looks right.", status), status, checkedAt})
		case (status < 200 || status >= 300) && !(acked.Valid && int(acked.Int64) == status):
			reason := fmt.Sprintf("Page returned an error (HTTP %d). It may have moved or been taken down.", status)
			if status == 0 {
				reason = "The page couldn't be reached. It may have moved or been taken down."
			}
			rep.NeedsAttention = append(rep.NeedsAttention, Attention{url, reason, status, checkedAt})
		case status >= 200 && status < 300 && hash.Valid && reviewed.Valid && hash.String != reviewed.String:
			rep.NeedsAttention = append(rep.NeedsAttention, Attention{url, "The page's wording changed since it was last reviewed. Check that our guide still matches.", status, checkedAt})
		}
	}
	return rep, rows.Err()
}

// MarkReviewed records that a person has looked at the page and the guide is fine.
func MarkReviewed(db *sql.DB, url string) (bool, error) {
	res, err := db.Exec(`
		UPDATE source_checks SET reviewed_hash = content_hash, acknowledged_status = status WHERE url = ?`, url)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
