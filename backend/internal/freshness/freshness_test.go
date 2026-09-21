package freshness

import (
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"ground-to-growth-connect-backend/internal/dbstore"
)

const schema = `
CREATE TABLE source_checks (
  url TEXT PRIMARY KEY, status INTEGER NOT NULL DEFAULT 0, error TEXT, content_hash TEXT,
  reviewed_hash TEXT, acknowledged_status INTEGER, checked_at TEXT NOT NULL, first_checked_at TEXT NOT NULL);`

func testDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := dbstore.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	if _, err := db.Exec(schema); err != nil {
		t.Fatal(err)
	}
	return db
}

// site is a fake official website whose page can be changed or broken on demand.
type site struct {
	body   string
	status int
	srv    *httptest.Server
}

func newSite(t *testing.T, body string) *site {
	s := &site{body: body, status: 200}
	s.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(s.status)
		_, _ = w.Write([]byte(s.body))
	}))
	t.Cleanup(s.srv.Close)
	return s
}

func run(t *testing.T, db *sql.DB, urls ...string) {
	t.Helper()
	c := NewChecker(db, func() []string { return urls })
	c.RunOnce(context.Background())
}

func report(t *testing.T, db *sql.DB) Report {
	t.Helper()
	r, err := BuildReport(db)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestFirstCheckIsTheBaselineNotAChange(t *testing.T) {
	db := testDB(t)
	s := newSite(t, "<html><body><p>ID cards cost $32.</p></body></html>")
	run(t, db, s.srv.URL)
	r := report(t, db)
	if r.Total != 1 || len(r.NeedsAttention) != 0 {
		t.Fatalf("a first good check must not raise anything: %+v", r)
	}
}

func TestChangedWordingIsFlaggedUntilReviewed(t *testing.T) {
	db := testDB(t)
	s := newSite(t, "<p>ID cards cost $32.</p>")
	run(t, db, s.srv.URL)

	s.body = "<p>ID cards cost $40.</p>"
	run(t, db, s.srv.URL)
	r := report(t, db)
	if len(r.NeedsAttention) != 1 || r.NeedsAttention[0].URL != s.srv.URL {
		t.Fatalf("the price change must be flagged: %+v", r)
	}

	if ok, err := MarkReviewed(db, s.srv.URL); err != nil || !ok {
		t.Fatalf("mark reviewed: %v %v", ok, err)
	}
	if r := report(t, db); len(r.NeedsAttention) != 0 {
		t.Fatalf("a reviewed page must stop being flagged: %+v", r)
	}

	s.body = "<p>ID cards cost $45.</p>"
	run(t, db, s.srv.URL)
	if r := report(t, db); len(r.NeedsAttention) != 1 {
		t.Fatalf("a later change must be flagged again: %+v", r)
	}
}

func TestMarkupAndSpacingChangesAreIgnored(t *testing.T) {
	db := testDB(t)
	s := newSite(t, `<html><head><script>var t=1</script><style>p{}</style></head><body><p>Open   Monday</p></body></html>`)
	run(t, db, s.srv.URL)

	s.body = `<html><head><script>var t=2; track()</script></head><body><div class="new"><p>open monday</p></div><!-- build 42 --></body></html>`
	run(t, db, s.srv.URL)
	if r := report(t, db); len(r.NeedsAttention) != 0 {
		t.Fatalf("cosmetic changes must not raise a flag: %+v", r)
	}
}

func TestBrokenPagesAreFlaggedAndKeepTheirLastGoodFingerprint(t *testing.T) {
	db := testDB(t)
	s := newSite(t, "<p>Apply here.</p>")
	run(t, db, s.srv.URL)

	s.status, s.body = 404, "Not found"
	run(t, db, s.srv.URL)
	r := report(t, db)
	if len(r.NeedsAttention) != 1 || r.NeedsAttention[0].Status != 404 {
		t.Fatalf("a 404 must be flagged: %+v", r)
	}

	// The page comes back unchanged: no more flag, and no false "changed".
	s.status, s.body = 200, "<p>Apply here.</p>"
	run(t, db, s.srv.URL)
	if r := report(t, db); len(r.NeedsAttention) != 0 {
		t.Fatalf("a recovered, unchanged page must clear: %+v", r)
	}
}

func TestAnUnreachableSiteIsFlaggedAndCanBeAcknowledged(t *testing.T) {
	db := testDB(t)
	dead := httptest.NewServer(http.NotFoundHandler())
	url := dead.URL
	dead.Close() // nothing is listening any more

	run(t, db, url)
	r := report(t, db)
	if len(r.NeedsAttention) != 1 || r.NeedsAttention[0].Status != 0 {
		t.Fatalf("an unreachable page must be flagged: %+v", r)
	}
	if ok, _ := MarkReviewed(db, url); !ok {
		t.Fatal("should be able to acknowledge")
	}
	if r := report(t, db); len(r.NeedsAttention) != 0 {
		t.Fatalf("an acknowledged outage must stop being flagged: %+v", r)
	}
}

func TestMarkReviewedOnAnUnknownPage(t *testing.T) {
	db := testDB(t)
	if ok, err := MarkReviewed(db, "https://example.org/nope"); err != nil || ok {
		t.Fatalf("expected not found, got ok=%v err=%v", ok, err)
	}
}

func TestLoopRunsAndStops(t *testing.T) {
	db := testDB(t)
	s := newSite(t, "<p>hi</p>")
	c := NewChecker(db, func() []string { return []string{s.srv.URL} })
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { c.Loop(ctx, time.Hour); close(done) }()
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Loop did not stop when its context ended")
	}
}
