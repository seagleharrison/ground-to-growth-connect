// Package push sends notifications to iPhones through Apple's push service
// (APNs). Notifications deliberately carry no message text or names: a phone
// lock screen can be read by anyone nearby, so they only say that something
// needs attention.
package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"time"
)

const (
	productionHost = "https://api.push.apple.com"
	sandboxHost    = "https://api.sandbox.push.apple.com"
)

// Notification is what gets shown. Data rides along invisibly so tapping it
// can open the right screen.
type Notification struct {
	Title string
	Body  string
	Badge *int
	Data  map[string]string
}

// Sender is what the rest of the server needs. A nil Sender means push isn't
// set up, which is fine: everything else keeps working.
type Sender interface {
	Send(ctx context.Context, token, environment string, n Notification) error
}

// ErrUnregistered means Apple says this token is no longer valid (the app was
// deleted, or the token was never valid). Callers should forget it.
var ErrUnregistered = errors.New("push token is no longer valid")

type Config struct {
	KeyPath string // the .p8 file from Apple
	KeyID   string
	TeamID  string
	Topic   string // the app's bundle identifier

	// Overrides for tests.
	ProductionURL string
	SandboxURL    string
	HTTPClient    *http.Client
}

type Client struct {
	cfg  Config
	key  *ecdsa.PrivateKey
	http *http.Client

	mu        sync.Mutex
	jwt       string
	jwtMadeAt time.Time
	now       func() time.Time
}

// FromEnv returns a client when APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID and
// APNS_TOPIC are all set, and nil (push off) otherwise. A key that is set but
// unreadable is an error worth seeing at startup.
func FromEnv() (*Client, error) {
	cfg := Config{
		KeyPath: os.Getenv("APNS_KEY_PATH"),
		KeyID:   os.Getenv("APNS_KEY_ID"),
		TeamID:  os.Getenv("APNS_TEAM_ID"),
		Topic:   os.Getenv("APNS_TOPIC"),
	}
	if cfg.KeyPath == "" || cfg.KeyID == "" || cfg.TeamID == "" || cfg.Topic == "" {
		return nil, nil
	}
	return New(cfg)
}

func New(cfg Config) (*Client, error) {
	raw, err := os.ReadFile(cfg.KeyPath)
	if err != nil {
		return nil, fmt.Errorf("reading APNs key: %w", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, errors.New("APNs key is not a PEM file")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parsing APNs key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("APNs key is not an EC key")
	}
	httpClient := cfg.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{
			Timeout:   15 * time.Second,
			Transport: &http.Transport{ForceAttemptHTTP2: true},
		}
	}
	return &Client{cfg: cfg, key: key, http: httpClient, now: time.Now}, nil
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// providerToken builds (and reuses) the signed token Apple wants on every
// request. Apple asks that it be refreshed no more than every 20 minutes and
// no less than every 60.
func (c *Client) providerToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.jwt != "" && c.now().Sub(c.jwtMadeAt) < 40*time.Minute {
		return c.jwt, nil
	}
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": c.cfg.KeyID})
	claims, _ := json.Marshal(map[string]interface{}{"iss": c.cfg.TeamID, "iat": c.now().Unix()})
	signing := b64(header) + "." + b64(claims)
	digest := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, c.key, digest[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	c.jwt = signing + "." + b64(sig)
	c.jwtMadeAt = c.now()
	return c.jwt, nil
}

type apsPayload struct {
	Aps  aps               `json:"aps"`
	Data map[string]string `json:"data,omitempty"`
}

type aps struct {
	Alert alert  `json:"alert"`
	Badge *int   `json:"badge,omitempty"`
	Sound string `json:"sound"`
}

type alert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

func (c *Client) Send(ctx context.Context, token, environment string, n Notification) error {
	jwt, err := c.providerToken()
	if err != nil {
		return err
	}
	base := productionHost
	override := c.cfg.ProductionURL
	if environment == "sandbox" {
		base, override = sandboxHost, c.cfg.SandboxURL
	}
	if override != "" {
		base = override
	}

	body, err := json.Marshal(apsPayload{
		Aps:  aps{Alert: alert{Title: n.Title, Body: n.Body}, Badge: n.Badge, Sound: "default"},
		Data: n.Data,
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/3/device/"+token, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", c.cfg.Topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	var failure struct {
		Reason string `json:"reason"`
	}
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	_ = json.Unmarshal(raw, &failure)
	switch {
	case resp.StatusCode == http.StatusGone,
		failure.Reason == "BadDeviceToken", failure.Reason == "Unregistered", failure.Reason == "DeviceTokenNotForTopic":
		return ErrUnregistered
	}
	return fmt.Errorf("apns %d: %s", resp.StatusCode, failure.Reason)
}
