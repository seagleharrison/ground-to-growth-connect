// Package content holds the guides, program descriptions and local places the
// app shows on its Resources tab. They ship inside the server so they can be
// corrected and re-published without waiting for a new app release: the app
// fetches them each time it opens the Resources tab.
package content

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"sort"
)

//go:embed resources.json
var resourcesJSON []byte

type link struct {
	URL string `json:"url"`
}

type topic struct {
	ID    string `json:"id"`
	Links []link `json:"links"`
}

type place struct {
	ID  string `json:"id"`
	URL string `json:"url"`
}

type document struct {
	UpdatedAt       string  `json:"updatedAt"`
	DocumentGuides  []topic `json:"documentGuides"`
	BenefitPrograms []topic `json:"benefitPrograms"`
	Places          []place `json:"places"`
}

func parse() document {
	var d document
	_ = json.Unmarshal(resourcesJSON, &d) // validated by this package's tests
	return d
}

// JSON is the exact document served to the app.
func JSON() []byte { return resourcesJSON }

// ETag identifies this version of the content, so the app can ask "anything
// new?" and get a tiny "no" back.
func ETag() string {
	sum := sha256.Sum256(resourcesJSON)
	return `"` + hex.EncodeToString(sum[:8]) + `"`
}

// UpdatedAt is the date the content was last reviewed and published.
func UpdatedAt() string { return parse().UpdatedAt }

// SourceURLs lists every official page the content points people to. The
// freshness checker watches these for changes and broken links.
func SourceURLs() []string {
	d := parse()
	seen := map[string]bool{}
	add := func(u string) {
		if u != "" {
			seen[u] = true
		}
	}
	for _, t := range append(append([]topic{}, d.DocumentGuides...), d.BenefitPrograms...) {
		for _, l := range t.Links {
			add(l.URL)
		}
	}
	for _, p := range d.Places {
		add(p.URL)
	}
	urls := make([]string, 0, len(seen))
	for u := range seen {
		urls = append(urls, u)
	}
	sort.Strings(urls)
	return urls
}
