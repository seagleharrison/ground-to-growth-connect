// Package cryptox mirrors the original Node crypto.js: AES-256-GCM at-rest
// encryption stored as [iv | tag | ciphertext], SHA-256 hashing, and the
// fixed privacy grid used to coarsen coordinates before they're stored.
package cryptox

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
)

const (
	ivLength  = 12
	tagLength = 16

	// GridMeters is the fixed privacy grid size, in meters. Coordinates are
	// snapped to this grid before encryption.
	GridMeters      = 200.0
	metersPerDegLat = 111_320.0
)

func getKey() ([]byte, error) {
	hexKey := os.Getenv("ENCRYPTION_KEY")
	if len(hexKey) != 64 {
		return nil, errors.New(
			"ENCRYPTION_KEY must be a 64-character hex string (32 bytes). " +
				"Generate with: openssl rand -hex 32",
		)
	}
	key, err := hex.DecodeString(hexKey)
	if err != nil {
		return nil, fmt.Errorf("ENCRYPTION_KEY must be valid hex: %w", err)
	}
	return key, nil
}

func newGCM() (cipher.AEAD, error) {
	key, err := getKey()
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// EncryptString encrypts a value to an [iv | tag | ciphertext] blob for BLOB
// storage. A nil input returns a nil blob (mirrors the Node `value == null` check).
func EncryptString(value *string) ([]byte, error) {
	if value == nil {
		return nil, nil
	}
	gcm, err := newGCM()
	if err != nil {
		return nil, err
	}
	iv := make([]byte, ivLength)
	if _, err := rand.Read(iv); err != nil {
		return nil, err
	}
	// gcm.Seal appends the tag to the end of the ciphertext; reorder to
	// [iv | tag | ciphertext] to match the existing on-disk/wire format.
	sealed := gcm.Seal(nil, iv, []byte(*value), nil)
	ciphertext := sealed[:len(sealed)-tagLength]
	tag := sealed[len(sealed)-tagLength:]

	out := make([]byte, 0, ivLength+tagLength+len(ciphertext))
	out = append(out, iv...)
	out = append(out, tag...)
	out = append(out, ciphertext...)
	return out, nil
}

// DecryptString reverses EncryptString. A nil blob returns a nil string.
func DecryptString(blob []byte) (*string, error) {
	if blob == nil {
		return nil, nil
	}
	if len(blob) < ivLength+tagLength {
		return nil, errors.New("ciphertext too short")
	}
	gcm, err := newGCM()
	if err != nil {
		return nil, err
	}
	iv := blob[:ivLength]
	tag := blob[ivLength : ivLength+tagLength]
	ciphertext := blob[ivLength+tagLength:]

	sealed := make([]byte, 0, len(ciphertext)+len(tag))
	sealed = append(sealed, ciphertext...)
	sealed = append(sealed, tag...)

	plain, err := gcm.Open(nil, iv, sealed, nil)
	if err != nil {
		return nil, err
	}
	s := string(plain)
	return &s, nil
}

func EncryptCoordinate(v float64) ([]byte, error) {
	s := strconv.FormatFloat(v, 'f', -1, 64)
	return EncryptString(&s)
}

func DecryptCoordinate(blob []byte) (float64, error) {
	s, err := DecryptString(blob)
	if err != nil {
		return 0, err
	}
	if s == nil {
		return 0, errors.New("coordinate blob is nil")
	}
	return strconv.ParseFloat(*s, 64)
}

// SnapToGrid snaps a coordinate pair to a fixed ~GridMeters grid before
// storage. Longitude cell size is adjusted by latitude so cells stay ~square.
func SnapToGrid(lat, lng float64) (float64, float64) {
	latCell := GridMeters / metersPerDegLat
	snappedLat := math.Round(lat/latCell) * latCell

	cos := math.Cos(lat * math.Pi / 180)
	absCos := math.Abs(cos)
	if absCos < 1e-6 {
		absCos = 1e-6
	}
	lngCell := GridMeters / (metersPerDegLat * absCos)
	snappedLng := math.Round(lng/lngCell) * lngCell

	return math.Round(snappedLat*1e6) / 1e6, math.Round(snappedLng*1e6) / 1e6
}

func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func HashUserAgent(userAgent string) *string {
	if userAgent == "" {
		return nil
	}
	sum := sha256.Sum256([]byte(userAgent))
	s := hex.EncodeToString(sum[:])
	return &s
}

func GenerateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
