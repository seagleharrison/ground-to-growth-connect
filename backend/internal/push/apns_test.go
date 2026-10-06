package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func writeKey(t *testing.T) (string, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "AuthKey_TEST.p8")
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	return path, key
}

type seen struct {
	mu       sync.Mutex
	path     string
	headers  http.Header
	body     map[string]interface{}
	requests int
}

// fakeApple stands in for Apple's push servers.
func fakeApple(t *testing.T, status int, reason string) (*httptest.Server, *seen) {
	t.Helper()
	s := &seen{}
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		s.requests++
		s.path = r.URL.Path
		s.headers = r.Header.Clone()
		_ = json.NewDecoder(r.Body).Decode(&s.body)
		if status != http.StatusOK {
			w.WriteHeader(status)
			_ = json.NewEncoder(w).Encode(map[string]string{"reason": reason})
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	srv.EnableHTTP2 = true
	srv.StartTLS()
	t.Cleanup(srv.Close)
	return srv, s
}

func newClient(t *testing.T, srv *httptest.Server) (*Client, *ecdsa.PrivateKey) {
	t.Helper()
	path, key := writeKey(t)
	c, err := New(Config{
		KeyPath: path, KeyID: "KEY123ABCD", TeamID: "TEAM123456", Topic: "com.example.app",
		ProductionURL: srv.URL, SandboxURL: srv.URL, HTTPClient: srv.Client(),
	})
	if err != nil {
		t.Fatal(err)
	}
	return c, key
}

func TestSendBuildsTheRequestAppleExpects(t *testing.T) {
	srv, got := fakeApple(t, http.StatusOK, "")
	c, key := newClient(t, srv)
	badge := 3

	err := c.Send(context.Background(), "abc123", "production", Notification{
		Title: "New message", Body: "You have a new message", Badge: &badge, Data: map[string]string{"kind": "message"},
	})
	if err != nil {
		t.Fatalf("send: %v", err)
	}

	if got.path != "/3/device/abc123" {
		t.Fatalf("unexpected path %q", got.path)
	}
	if got.headers.Get("apns-topic") != "com.example.app" || got.headers.Get("apns-push-type") != "alert" {
		t.Fatalf("missing apns headers: %v", got.headers)
	}
	aps := got.body["aps"].(map[string]interface{})
	alert := aps["alert"].(map[string]interface{})
	if alert["title"] != "New message" || alert["body"] != "You have a new message" || aps["badge"].(float64) != 3 || aps["sound"] != "default" {
		t.Fatalf("unexpected payload: %v", got.body)
	}
	if got.body["data"].(map[string]interface{})["kind"] != "message" {
		t.Fatalf("data should ride along: %v", got.body)
	}

	// The authorization token is a real ES256 JWT that verifies with the key.
	auth := got.headers.Get("authorization")
	if !strings.HasPrefix(auth, "bearer ") {
		t.Fatalf("expected a bearer token, got %q", auth)
	}
	parts := strings.Split(strings.TrimPrefix(auth, "bearer "), ".")
	if len(parts) != 3 {
		t.Fatalf("expected a 3-part JWT, got %d parts", len(parts))
	}
	var header map[string]string
	hb, _ := base64.RawURLEncoding.DecodeString(parts[0])
	_ = json.Unmarshal(hb, &header)
	if header["alg"] != "ES256" || header["kid"] != "KEY123ABCD" {
		t.Fatalf("bad JWT header: %v", header)
	}
	var claims map[string]interface{}
	cb, _ := base64.RawURLEncoding.DecodeString(parts[1])
	_ = json.Unmarshal(cb, &claims)
	if claims["iss"] != "TEAM123456" || claims["iat"] == nil {
		t.Fatalf("bad JWT claims: %v", claims)
	}
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	if len(sig) != 64 {
		t.Fatalf("an ES256 signature is 64 bytes, got %d", len(sig))
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(&key.PublicKey, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		t.Fatalf("JWT signature does not verify")
	}
}

func TestProviderTokenIsReusedThenRefreshed(t *testing.T) {
	srv, _ := fakeApple(t, http.StatusOK, "")
	c, _ := newClient(t, srv)
	now := time.Now()
	c.now = func() time.Time { return now }

	first, _ := c.providerToken()
	now = now.Add(30 * time.Minute)
	again, _ := c.providerToken()
	if first != again {
		t.Fatalf("a token under 40 minutes old should be reused")
	}
	now = now.Add(20 * time.Minute)
	fresh, _ := c.providerToken()
	if fresh == first {
		t.Fatalf("a token over 40 minutes old should be replaced")
	}
}

func TestTokensAppleRejectsAreReportedAsUnregistered(t *testing.T) {
	for _, tc := range []struct {
		status int
		reason string
	}{
		{http.StatusGone, "Unregistered"},
		{http.StatusBadRequest, "BadDeviceToken"},
		{http.StatusBadRequest, "DeviceTokenNotForTopic"},
	} {
		srv, _ := fakeApple(t, tc.status, tc.reason)
		c, _ := newClient(t, srv)
		if err := c.Send(context.Background(), "dead", "production", Notification{Title: "x"}); err != ErrUnregistered {
			t.Fatalf("%d %s: expected ErrUnregistered, got %v", tc.status, tc.reason, err)
		}
	}
}

func TestOtherFailuresAreRealErrorsNotForgottenTokens(t *testing.T) {
	srv, _ := fakeApple(t, http.StatusForbidden, "InvalidProviderToken")
	c, _ := newClient(t, srv)
	err := c.Send(context.Background(), "tok", "production", Notification{Title: "x"})
	if err == nil || err == ErrUnregistered || !strings.Contains(err.Error(), "InvalidProviderToken") {
		t.Fatalf("expected a descriptive error, got %v", err)
	}
}

func TestSandboxAndProductionGoToTheirOwnHosts(t *testing.T) {
	prod, prodSeen := fakeApple(t, http.StatusOK, "")
	sand, sandSeen := fakeApple(t, http.StatusOK, "")
	path, _ := writeKey(t)
	c, err := New(Config{KeyPath: path, KeyID: "K", TeamID: "T", Topic: "t", ProductionURL: prod.URL, SandboxURL: sand.URL, HTTPClient: prod.Client()})
	if err != nil {
		t.Fatal(err)
	}
	// Both fake servers use different self-signed certs; trust both.
	pool := x509.NewCertPool()
	pool.AddCert(prod.Certificate())
	pool.AddCert(sand.Certificate())
	tr := prod.Client().Transport.(*http.Transport).Clone()
	tr.TLSClientConfig.RootCAs = pool
	c.http = &http.Client{Transport: tr}

	_ = c.Send(context.Background(), "a", "sandbox", Notification{Title: "x"})
	_ = c.Send(context.Background(), "b", "production", Notification{Title: "x"})
	if sandSeen.requests != 1 || prodSeen.requests != 1 {
		t.Fatalf("expected one request to each host, got sandbox=%d production=%d", sandSeen.requests, prodSeen.requests)
	}
}

func TestFromEnvIsOffUnlessFullyConfigured(t *testing.T) {
	for _, k := range []string{"APNS_KEY_PATH", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_TOPIC"} {
		t.Setenv(k, "")
	}
	if c, err := FromEnv(); c != nil || err != nil {
		t.Fatalf("with nothing set push must be quietly off, got %v %v", c, err)
	}
	t.Setenv("APNS_KEY_PATH", "/nope")
	t.Setenv("APNS_KEY_ID", "K")
	t.Setenv("APNS_TEAM_ID", "T")
	if c, err := FromEnv(); c != nil || err != nil {
		t.Fatalf("with a topic missing push must stay off, got %v %v", c, err)
	}
	t.Setenv("APNS_TOPIC", "com.example")
	if _, err := FromEnv(); err == nil {
		t.Fatalf("a configured but unreadable key should be reported")
	}
	path, _ := writeKey(t)
	t.Setenv("APNS_KEY_PATH", path)
	if c, err := FromEnv(); c == nil || err != nil {
		t.Fatalf("fully configured should work, got %v %v", c, err)
	}
}

func TestBadKeyFilesAreRejected(t *testing.T) {
	dir := t.TempDir()
	notPEM := filepath.Join(dir, "a.p8")
	_ = os.WriteFile(notPEM, []byte("hello"), 0o600)
	if _, err := New(Config{KeyPath: notPEM}); err == nil {
		t.Fatalf("a non-PEM file must be rejected")
	}
}
