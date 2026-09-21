package dbstore

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"
)

func readSchema(t *testing.T) string {
	t.Helper()
	// Schema lives at backend/sql/001_init.sql; this package is at
	// backend/internal/dbstore, so it's two directories up.
	b, err := os.ReadFile(filepath.Join("..", "..", "sql", "001_init.sql"))
	if err != nil {
		t.Fatalf("reading schema file: %v", err)
	}
	return string(b)
}

func TestOpenAndMigrateCreatesExpectedTables(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test.db")

	db, err := Open(dbPath)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer db.Close()

	if err := Migrate(db, readSchema(t)); err != nil {
		t.Fatalf("Migrate: %v", err)
	}

	wantTables := []string{"users", "consent_records", "location_reports"}
	for _, name := range wantTables {
		var got string
		err := db.QueryRow(`SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?`, name).Scan(&got)
		if err != nil {
			t.Errorf("expected table %q to exist: %v", name, err)
		}
	}

	var viewName string
	err = db.QueryRow(`SELECT name FROM sqlite_master WHERE type = 'view' AND name = 'user_consent_status'`).Scan(&viewName)
	if err != nil {
		t.Errorf("expected view user_consent_status to exist: %v", err)
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "test.db")

	db, err := Open(dbPath)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer db.Close()

	schema := readSchema(t)
	if err := Migrate(db, schema); err != nil {
		t.Fatalf("first Migrate: %v", err)
	}
	if err := Migrate(db, schema); err != nil {
		t.Fatalf("second Migrate should be a no-op, got error: %v", err)
	}
}

func userColumns(t *testing.T, db *sql.DB) map[string]bool {
	t.Helper()
	rows, err := db.Query("PRAGMA table_info(users)")
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notNull, pk int
		var name, ctype string
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			t.Fatal(err)
		}
		cols[name] = true
	}
	return cols
}

// A database created before the profile-picture columns existed must be
// upgraded in place, keeping its data, and re-running the migration (which
// happens on every start) must stay harmless.
func TestMigrateUpgradesAnExistingDatabase(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "old.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// The users table exactly as the first release created it.
	if _, err := db.Exec(`CREATE TABLE users (
		id TEXT PRIMARY KEY,
		person_type TEXT NOT NULL DEFAULT 'homeless',
		name_encrypted BLOB NOT NULL,
		email_encrypted BLOB,
		gender_encrypted BLOB,
		phone_encrypted BLOB,
		token_hash TEXT NOT NULL UNIQUE,
		created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
	)`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO users (id, name_encrypted, token_hash) VALUES ('u1', x'00', 'hash1')`); err != nil {
		t.Fatal(err)
	}
	if userColumns(t, db)["profile_picture_key"] {
		t.Fatal("test setup should start without the new column")
	}

	schema := readSchema(t)
	for i := 0; i < 2; i++ { // twice: must be idempotent
		if err := Migrate(db, schema); err != nil {
			t.Fatalf("Migrate run %d: %v", i+1, err)
		}
	}

	cols := userColumns(t, db)
	if !cols["profile_picture_key"] || !cols["profile_picture_mime"] {
		t.Fatalf("expected the new columns after migrating, got %v", cols)
	}
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM users WHERE id = 'u1'`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("existing user should survive the upgrade (n=%d, err=%v)", n, err)
	}
}
