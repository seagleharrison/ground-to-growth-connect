// Package pages holds the public web pages the app stores require: a privacy
// policy and a support page. They are served by the API itself so they live
// at a stable address on our own domain.
package pages

import (
	"bytes"
	_ "embed"
	"html/template"
	"net/http"
	"os"
	"strings"

	"ground-to-growth-connect-backend/internal/consent"
)

//go:embed privacy.html.tmpl
var privacySource string

//go:embed support.html.tmpl
var supportSource string

// Updated is the "last updated" date shown on the privacy policy. Change it
// whenever the policy's text changes.
const Updated = "October 14, 2026"

type data struct {
	Updated      string
	OrgAddress   string
	ContactEmail string
}

func render(source string) ([]byte, error) {
	t, err := template.New("page").Parse(source)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	err = t.Execute(&buf, data{
		Updated:      Updated,
		OrgAddress:   consent.OrgAddress,
		ContactEmail: strings.TrimSpace(os.Getenv("CONTACT_EMAIL")),
	})
	return buf.Bytes(), err
}

func serve(source string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := render(source)
		if err != nil {
			http.Error(w, "Something went wrong", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// The API's usual policy blocks everything; these pages need their own
		// inline stylesheet and nothing else.
		w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'")
		w.Header().Set("Cache-Control", "public, max-age=300")
		_, _ = w.Write(body)
	}
}

// Privacy and Support are public (no sign-in): the stores and anyone reading
// them need to reach them without an account.
func Privacy() http.HandlerFunc { return serve(privacySource) }
func Support() http.HandlerFunc { return serve(supportSource) }
