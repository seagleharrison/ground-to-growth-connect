// Package dbstore opens the SQLite database and runs the (idempotent) schema migration.
package dbstore

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

func Open(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}

	// SQLite allows only one writer at a time; serialize through a single
	// connection so concurrent requests don't race on "database is locked".
	db.SetMaxOpenConns(1)

	if _, err := db.Exec("PRAGMA journal_mode = WAL"); err != nil {
		db.Close()
		return nil, err
	}
	if _, err := db.Exec("PRAGMA foreign_keys = ON"); err != nil {
		db.Close()
		return nil, err
	}

	return db, nil
}

// columnsAddedAfterV1 are columns that were added to existing tables after
// the first release. CREATE TABLE IF NOT EXISTS leaves an already-created
// table untouched, so a database made before these columns existed needs them
// added here; a brand-new database already has them from 001_init.sql.
var columnsAddedAfterV1 = []struct{ table, column, definition string }{
	{"users", "profile_picture_key", "TEXT"},
	{"users", "profile_picture_mime", "TEXT"},
}

func Migrate(db *sql.DB, migrationSQL string) error {
	if _, err := db.Exec(migrationSQL); err != nil {
		return err
	}
	for _, c := range columnsAddedAfterV1 {
		if err := ensureColumn(db, c.table, c.column, c.definition); err != nil {
			return err
		}
	}
	return nil
}

// ensureColumn adds a column if the table doesn't have it yet, so running the
// migration repeatedly (it runs on every start) stays safe.
func ensureColumn(db *sql.DB, table, column, definition string) error {
	rows, err := db.Query(fmt.Sprintf("PRAGMA table_info(%s)", table))
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var cid int
		var name, ctype string
		var notNull, pk int
		var dflt sql.NullString
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return err
		}
		if name == column {
			return nil
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	rows.Close()

	_, err = db.Exec(fmt.Sprintf("ALTER TABLE %s ADD COLUMN %s %s", table, column, definition))
	return err
}
