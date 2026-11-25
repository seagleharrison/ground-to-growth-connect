package api

import (
	"math"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Limits for the two routes anyone can call without signing in. They are per
// client IP address and generous enough for a shelter or event where many
// people sign up over the same Wi-Fi, while stopping a script from creating
// accounts in bulk or guessing recovery codes.
const (
	registerLimit  = 30
	registerWindow = time.Hour
	recoverLimit   = 10
	recoverWindow  = 15 * time.Minute
)

// rateLimiter counts requests per key (a client IP) in fixed windows. It lives
// in memory, which is enough because the API runs as a single instance (SQLite
// on one volume); a restart simply starts every count over.
type rateLimiter struct {
	limit  int
	window time.Duration
	now    func() time.Time

	mu        sync.Mutex
	hits      map[string]*rateWindow
	lastSweep time.Time
}

type rateWindow struct {
	start time.Time
	count int
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{limit: limit, window: window, now: time.Now, hits: map[string]*rateWindow{}}
}

// allow records one request for key and reports whether it is within the
// limit. When it isn't, retryAfter says how long until the window resets.
func (l *rateLimiter) allow(key string) (ok bool, retryAfter time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.sweep(now)

	w := l.hits[key]
	if w == nil || now.Sub(w.start) >= l.window {
		w = &rateWindow{start: now}
		l.hits[key] = w
	}
	if w.count >= l.limit {
		return false, w.start.Add(l.window).Sub(now)
	}
	w.count++
	return true, 0
}

// sweep drops finished windows now and then, so the map can't grow without
// bound as new addresses come and go.
func (l *rateLimiter) sweep(now time.Time) {
	if now.Sub(l.lastSweep) < l.window {
		return
	}
	l.lastSweep = now
	for k, w := range l.hits {
		if now.Sub(w.start) >= l.window {
			delete(l.hits, k)
		}
	}
}

// withRateLimit answers 429 Too Many Requests, with a Retry-After header, once
// a client IP has used up its allowance for this route.
func (s *Server) withRateLimit(l *rateLimiter, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if l != nil {
			if ok, retryAfter := l.allow(s.clientIP(r)); !ok {
				secs := int(math.Ceil(retryAfter.Seconds()))
				if secs < 1 {
					secs = 1
				}
				w.Header().Set("Retry-After", strconv.Itoa(secs))
				writeError(w, http.StatusTooManyRequests, "Too many attempts from this network. Please wait a few minutes and try again.")
				return
			}
		}
		next(w, r)
	}
}

// clientIP is the address a request came from. Behind a reverse proxy every
// request arrives from the proxy, so CLIENT_IP_HEADER names the header the
// proxy puts the real address in: "Fly-Client-IP" on Fly.io, or
// "X-Forwarded-For" behind Caddy. Only set it when a proxy you control is in
// front, because clients can send any header themselves. For a comma-separated
// list the last entry is used, since that one was added by the nearest proxy.
func (s *Server) clientIP(r *http.Request) string {
	if s.clientIPHeader != "" {
		if v := r.Header.Get(s.clientIPHeader); v != "" {
			parts := strings.Split(v, ",")
			for i := len(parts) - 1; i >= 0; i-- {
				if ip := strings.TrimSpace(parts[i]); ip != "" {
					return ip
				}
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// withRateLimits replaces the sign-up and recovery limiters. Tests use it to
// turn limits off (nil) or make them small enough to hit.
func withRateLimits(register, recover *rateLimiter) Option {
	return func(s *Server) {
		s.registerLimiter = register
		s.recoverLimiter = recover
	}
}
