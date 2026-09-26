package content

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
)

// Shelter/program events (meals, drives, office hours) shown on participants'
// Calendar tab, alongside their own personal appointments. Like resources.json,
// this ships inside the server so an event can be added or changed without a
// new app release.
//
//go:embed events.json
var eventsJSON []byte

type eventsDoc struct {
	UpdatedAt string `json:"updatedAt"`
}

func parseEvents() eventsDoc {
	var d eventsDoc
	_ = json.Unmarshal(eventsJSON, &d) // validated by this package's tests
	return d
}

// EventsJSON is the exact document served to the app.
func EventsJSON() []byte { return eventsJSON }

func EventsETag() string {
	sum := sha256.Sum256(eventsJSON)
	return `"` + hex.EncodeToString(sum[:8]) + `"`
}

// EventsUpdatedAt is the date the event list was last edited.
func EventsUpdatedAt() string { return parseEvents().UpdatedAt }
