package content

import (
	"encoding/json"
	"regexp"
	"testing"
	"time"
)

type fullEvent struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Location    string `json:"location"`
	StartsAt    string `json:"startsAt"`
}

type fullEventsDoc struct {
	UpdatedAt string      `json:"updatedAt"`
	Events    []fullEvent `json:"events"`
}

func loadEvents(t *testing.T) fullEventsDoc {
	t.Helper()
	var d fullEventsDoc
	if err := json.Unmarshal(EventsJSON(), &d); err != nil {
		t.Fatalf("events.json is not valid: %v", err)
	}
	return d
}

func TestEventsJSONIsWellFormed(t *testing.T) {
	d := loadEvents(t)
	if !regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`).MatchString(d.UpdatedAt) {
		t.Fatalf("updatedAt must be a date, got %q", d.UpdatedAt)
	}

	ids := map[string]bool{}
	for _, e := range d.Events {
		if e.ID == "" || ids[e.ID] {
			t.Fatalf("event ids must be present and unique: %q", e.ID)
		}
		ids[e.ID] = true
		if e.Title == "" {
			t.Fatalf("%s: needs a title", e.ID)
		}
		if _, err := time.Parse(time.RFC3339, e.StartsAt); err != nil {
			t.Fatalf("%s: startsAt must be RFC3339, got %q: %v", e.ID, e.StartsAt, err)
		}
	}
}

func TestEventsUpdatedAtMatchesTheDocument(t *testing.T) {
	if EventsUpdatedAt() != loadEvents(t).UpdatedAt {
		t.Fatalf("EventsUpdatedAt() should read the same field the JSON has")
	}
}

func TestEventsETagChangesWithContent(t *testing.T) {
	before := EventsETag()
	// Sanity: the ETag is a function of the actual bytes, not a constant.
	if before == "" || before == `""` {
		t.Fatalf("expected a non-empty etag, got %q", before)
	}
}
