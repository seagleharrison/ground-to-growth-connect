// Package blobstore stores and retrieves already-encrypted document bytes by
// key. It never sees plaintext — callers (internal/api) encrypt before Put
// and decrypt after Get, so whichever Store implementation is active (local
// disk for dev, Backblaze B2 in production) never holds a readable copy.
package blobstore

import (
	"context"
	"errors"
)

// ErrNotFound is returned by Get and Delete when the key doesn't exist.
var ErrNotFound = errors.New("blobstore: not found")

type Store interface {
	Put(ctx context.Context, key string, data []byte) error
	Get(ctx context.Context, key string) ([]byte, error)
	Delete(ctx context.Context, key string) error
}
