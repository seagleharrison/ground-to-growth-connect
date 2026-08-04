package cryptox

import (
	"strings"
	"testing"
)

const testKey = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestEncryptDecryptStringRoundTrip(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	original := "Jane Doe"
	blob, err := EncryptString(&original)
	if err != nil {
		t.Fatalf("EncryptString: %v", err)
	}
	if blob == nil {
		t.Fatal("expected non-nil ciphertext")
	}

	got, err := DecryptString(blob)
	if err != nil {
		t.Fatalf("DecryptString: %v", err)
	}
	if got == nil || *got != original {
		t.Fatalf("round trip mismatch: got %v, want %q", got, original)
	}
}

func TestEncryptStringNilInput(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	blob, err := EncryptString(nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if blob != nil {
		t.Fatalf("expected nil blob for nil input, got %v", blob)
	}
}

func TestDecryptNilInput(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	got, err := DecryptString(nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != nil {
		t.Fatalf("expected nil string for nil blob, got %v", got)
	}
}

func TestEncryptDifferentIVsEachTime(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	value := "same input"
	blob1, _ := EncryptString(&value)
	blob2, _ := EncryptString(&value)

	if string(blob1) == string(blob2) {
		t.Fatal("expected different ciphertext blobs due to random IV, got identical output")
	}
}

func TestDecryptTamperedCiphertextFails(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	value := "sensitive"
	blob, err := EncryptString(&value)
	if err != nil {
		t.Fatalf("EncryptString: %v", err)
	}

	tampered := make([]byte, len(blob))
	copy(tampered, blob)
	tampered[len(tampered)-1] ^= 0xFF // flip last ciphertext byte

	if _, err := DecryptString(tampered); err == nil {
		t.Fatal("expected authentication failure on tampered ciphertext, got no error")
	}
}

func TestDecryptTooShortBlobFails(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	if _, err := DecryptString([]byte{1, 2, 3}); err == nil {
		t.Fatal("expected error for undersized ciphertext blob")
	}
}

func TestMissingEncryptionKeyFails(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", "")

	value := "x"
	if _, err := EncryptString(&value); err == nil {
		t.Fatal("expected error when ENCRYPTION_KEY is unset")
	}
}

func TestWrongLengthEncryptionKeyFails(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", "tooshort")

	value := "x"
	if _, err := EncryptString(&value); err == nil {
		t.Fatal("expected error when ENCRYPTION_KEY is not 64 hex chars")
	}
}

func TestEncryptCoordinateRoundTrip(t *testing.T) {
	t.Setenv("ENCRYPTION_KEY", testKey)

	original := 32.080489
	blob, err := EncryptCoordinate(original)
	if err != nil {
		t.Fatalf("EncryptCoordinate: %v", err)
	}
	got, err := DecryptCoordinate(blob)
	if err != nil {
		t.Fatalf("DecryptCoordinate: %v", err)
	}
	if got != original {
		t.Fatalf("coordinate round trip mismatch: got %v, want %v", got, original)
	}
}

func TestSnapToGridIsWithinGridTolerance(t *testing.T) {
	lat, lng := 32.0809, -81.0912
	gridLat, gridLng := SnapToGrid(lat, lng)

	// The privacy grid is ~200m; at Savannah's latitude that's a small
	// fraction of a degree. Snapped coordinates should stay close to the
	// original, never wildly off.
	if diff := lat - gridLat; diff > 0.01 || diff < -0.01 {
		t.Fatalf("snapped latitude drifted too far: %v -> %v", lat, gridLat)
	}
	if diff := lng - gridLng; diff > 0.01 || diff < -0.01 {
		t.Fatalf("snapped longitude drifted too far: %v -> %v", lng, gridLng)
	}
}

func TestSnapToGridIsDeterministic(t *testing.T) {
	lat1, lng1 := SnapToGrid(32.0809, -81.0912)
	lat2, lng2 := SnapToGrid(32.0809, -81.0912)
	if lat1 != lat2 || lng1 != lng2 {
		t.Fatal("SnapToGrid should be deterministic for identical input")
	}
}

func TestHashTokenIsDeterministicAndDistinct(t *testing.T) {
	a := HashToken("token-a")
	b := HashToken("token-a")
	c := HashToken("token-b")

	if a != b {
		t.Fatal("HashToken should be deterministic for the same input")
	}
	if a == c {
		t.Fatal("HashToken should differ for different input")
	}
	if len(a) != 64 { // sha256 hex-encoded
		t.Fatalf("expected 64-char hex digest, got %d chars", len(a))
	}
}

func TestHashUserAgentEmptyReturnsNil(t *testing.T) {
	if got := HashUserAgent(""); got != nil {
		t.Fatalf("expected nil for empty user agent, got %v", got)
	}
}

func TestHashUserAgentNonEmpty(t *testing.T) {
	got := HashUserAgent("Mozilla/5.0")
	if got == nil {
		t.Fatal("expected non-nil hash for non-empty user agent")
	}
	if len(*got) != 64 {
		t.Fatalf("expected 64-char hex digest, got %d chars", len(*got))
	}
	// Must never store the raw user agent string.
	if strings.Contains(*got, "Mozilla") {
		t.Fatal("hash must not contain the original user agent text")
	}
}

func TestGenerateTokenUniqueAndWellFormed(t *testing.T) {
	a, err := GenerateToken()
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	b, err := GenerateToken()
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	if a == b {
		t.Fatal("expected two generated tokens to differ")
	}
	if len(a) != 64 { // 32 random bytes, hex-encoded
		t.Fatalf("expected 64-char hex token, got %d chars", len(a))
	}
}
