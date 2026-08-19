package blobstore

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// LocalDiskStore writes encrypted blobs to a directory on disk. Used
// automatically when no Backblaze B2 credentials are configured (local dev,
// or before a bucket has been set up) so the app works out of the box.
type LocalDiskStore struct {
	root string
}

func NewLocalDiskStore(root string) (*LocalDiskStore, error) {
	if err := os.MkdirAll(root, 0o700); err != nil {
		return nil, fmt.Errorf("creating blob store root: %w", err)
	}
	return &LocalDiskStore{root: root}, nil
}

// safePath rejects anything that could escape root (e.g. "../../etc/passwd")
// — keys are server-generated (user/document IDs), never raw user input, but
// this is cheap insurance against a future caller passing something unsafe.
func (s *LocalDiskStore) safePath(key string) (string, error) {
	if key == "" || strings.Contains(key, "..") || strings.HasPrefix(key, "/") {
		return "", fmt.Errorf("blobstore: invalid key %q", key)
	}
	return filepath.Join(s.root, filepath.FromSlash(key)), nil
}

func (s *LocalDiskStore) Put(ctx context.Context, key string, data []byte) error {
	path, err := s.safePath(key)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}

	// Write-then-rename so a crash mid-write never leaves a partial file
	// at the real path.
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func (s *LocalDiskStore) Get(ctx context.Context, key string) ([]byte, error) {
	path, err := s.safePath(key)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, ErrNotFound
	}
	return data, err
}

func (s *LocalDiskStore) Delete(ctx context.Context, key string) error {
	path, err := s.safePath(key)
	if err != nil {
		return err
	}
	err = os.Remove(path)
	if os.IsNotExist(err) {
		return nil // already gone — deleting is idempotent
	}
	return err
}
