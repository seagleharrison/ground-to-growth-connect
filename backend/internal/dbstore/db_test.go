package dbstore

import (
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
