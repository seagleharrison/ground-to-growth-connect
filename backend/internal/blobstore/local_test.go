package blobstore

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalDiskStorePutGetRoundTrip(t *testing.T) {
	store, err := NewLocalDiskStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewLocalDiskStore: %v", err)
	}
	ctx := context.Background()

	original := []byte("pretend this is encrypted document bytes")
	if err := store.Put(ctx, "documents/user1/doc1.enc", original); err != nil {
		t.Fatalf("Put: %v", err)
	}

	got, err := store.Get(ctx, "documents/user1/doc1.enc")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if string(got) != string(original) {
		t.Fatalf("round trip mismatch: got %q, want %q", got, original)
	}
}

func TestLocalDiskStoreGetMissingReturnsErrNotFound(t *testing.T) {
	store, err := NewLocalDiskStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewLocalDiskStore: %v", err)
	}

	_, err = store.Get(context.Background(), "documents/does/not/exist.enc")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestLocalDiskStoreDeleteIsIdempotent(t *testing.T) {
	store, err := NewLocalDiskStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewLocalDiskStore: %v", err)
	}
	ctx := context.Background()

	if err := store.Put(ctx, "documents/user1/doc1.enc", []byte("x")); err != nil {
		t.Fatalf("Put: %v", err)
	}
	if err := store.Delete(ctx, "documents/user1/doc1.enc"); err != nil {
		t.Fatalf("first Delete: %v", err)
	}
	if err := store.Delete(ctx, "documents/user1/doc1.enc"); err != nil {
		t.Fatalf("second Delete (already gone) should not error, got: %v", err)
	}

	if _, err := store.Get(ctx, "documents/user1/doc1.enc"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestLocalDiskStoreRejectsPathTraversal(t *testing.T) {
	store, err := NewLocalDiskStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewLocalDiskStore: %v", err)
	}
	ctx := context.Background()

	if err := store.Put(ctx, "../../etc/passwd", []byte("x")); err == nil {
		t.Fatal("expected an error for a path-traversal key, got nil")
	}
	if _, err := store.Get(ctx, "/etc/passwd"); err == nil {
		t.Fatal("expected an error for an absolute-path key, got nil")
	}
}

func TestLocalDiskStoreCreatesNestedDirectories(t *testing.T) {
	root := t.TempDir()
	store, err := NewLocalDiskStore(root)
	if err != nil {
		t.Fatalf("NewLocalDiskStore: %v", err)
	}

	if err := store.Put(context.Background(), "documents/deeply/nested/path/doc.enc", []byte("x")); err != nil {
		t.Fatalf("Put: %v", err)
	}

	expected := filepath.Join(root, "documents", "deeply", "nested", "path", "doc.enc")
	if _, err := os.Stat(expected); err != nil {
		t.Fatalf("expected file at %s, got error: %v", expected, err)
	}
}
