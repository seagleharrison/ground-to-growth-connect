package main

import (
	"context"
	_ "embed"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ground-to-growth-connect-backend/internal/api"
	"ground-to-growth-connect-backend/internal/dbstore"

	_ "modernc.org/sqlite"
)

//go:embed sql/001_init.sql
var migrationSQL string

func main() {
	sqlitePath := os.Getenv("SQLITE_PATH")
	if sqlitePath == "" {
		sqlitePath = "locvault.db"
	}

	db, err := dbstore.Open(sqlitePath)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer db.Close()

	if err := dbstore.Migrate(db, migrationSQL); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	log.Printf("Migration complete. Database: %s", sqlitePath)

	port := os.Getenv("PORT")
	if port == "" {
		port = "3001"
	}
	host := os.Getenv("HOST")
	if host == "" {
		host = "0.0.0.0"
	}

	handler := api.NewServer(db)
	srv := &http.Server{
		Addr:              host + ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("Ground to Growth Connect API listening on http://%s:%s", host, port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	sig := <-stop
	log.Printf("%s received, shutting down...", sig)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}
