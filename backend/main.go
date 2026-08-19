package main

import (
	"context"
	_ "embed"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"ground-to-growth-connect-backend/internal/api"
	"ground-to-growth-connect-backend/internal/blobstore"
	"ground-to-growth-connect-backend/internal/dbstore"
)

//go:embed sql/001_init.sql
var migrationSQL string

// loadDotEnv is a minimal stand-in for the Node backend's `dotenv` dependency,
// used for local (non-container) development. In Docker, docker-compose's
// env_file already populates the real environment, so this is a no-op there
// (any variable already set in the real environment always wins).
func loadDotEnv(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		os.Setenv(key, strings.TrimSpace(value))
	}
}

// newDocumentStore uses Backblaze B2 when all B2_* env vars are set, and
// otherwise falls back to a local directory next to the SQLite database —
// so the app works out of the box before a bucket has been configured.
func newDocumentStore(sqlitePath string) (blobstore.Store, error) {
	endpoint := os.Getenv("B2_ENDPOINT")
	region := os.Getenv("B2_REGION")
	bucket := os.Getenv("B2_BUCKET")
	keyID := os.Getenv("B2_KEY_ID")
	appKey := os.Getenv("B2_APPLICATION_KEY")

	if endpoint != "" && region != "" && bucket != "" && keyID != "" && appKey != "" {
		log.Printf("Document storage: Backblaze B2 bucket %q", bucket)
		return blobstore.NewB2Store(blobstore.B2Config{
			Endpoint:       endpoint,
			Region:         region,
			Bucket:         bucket,
			KeyID:          keyID,
			ApplicationKey: appKey,
		}), nil
	}

	localPath := os.Getenv("DOCUMENTS_LOCAL_PATH")
	if localPath == "" {
		localPath = filepath.Join(filepath.Dir(sqlitePath), "documents")
	}
	log.Printf("Document storage: local disk at %s (set B2_* env vars to use Backblaze B2 instead)", localPath)
	return blobstore.NewLocalDiskStore(localPath)
}

func main() {
	loadDotEnv(".env")

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

	docs, err := newDocumentStore(sqlitePath)
	if err != nil {
		log.Fatalf("configure document storage: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "3001"
	}
	host := os.Getenv("HOST")
	if host == "" {
		host = "0.0.0.0"
	}

	handler := api.NewServer(db, docs)
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
