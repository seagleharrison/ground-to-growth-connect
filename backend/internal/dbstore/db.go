// Package dbstore opens the SQLite database and runs the (idempotent) schema migration.
package dbstore

import (
	"database/sql"

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

func Migrate(db *sql.DB, migrationSQL string) error {
	_, err := db.Exec(migrationSQL)
	return err
}
