package content

import (
	"encoding/json"
	"net/url"
	"regexp"
	"strings"
	"testing"
)

type fullTopic struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Summary  string `json:"summary"`
	Sections []struct {
		Heading string   `json:"heading"`
		Items   []string `json:"items"`
	} `json:"sections"`
	Links  []struct{ Label, URL string }           `json:"links"`
	Phones []struct{ Label, Display, Dial string } `json:"phones"`
}

type fullPlace struct {
	ID       string                         `json:"id"`
	Name     string                         `json:"name"`
	Address  string                         `json:"address"`
	Lat      float64                        `json:"lat"`
	Lng      float64                        `json:"lng"`
	URL      string                         `json:"url"`
	Note     string                         `json:"note"`
	Verified string                         `json:"verifiedOn"`
	Phone    struct{ Display, Dial string } `json:"phone"`
}

type fullDoc struct {
	UpdatedAt       string      `json:"updatedAt"`
	DocumentGuides  []fullTopic `json:"documentGuides"`
	BenefitPrograms []fullTopic `json:"benefitPrograms"`
	Places          []fullPlace `json:"places"`
}

func load(t *testing.T) fullDoc {
	t.Helper()
	var d fullDoc
	if err := json.Unmarshal(JSON(), &d); err != nil {
		t.Fatalf("resources.json is not valid: %v", err)
	}
	return d
}

func TestContentIsCompleteAndWellFormed(t *testing.T) {
	d := load(t)
	if !regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`).MatchString(d.UpdatedAt) {
		t.Fatalf("updatedAt must be a date, got %q", d.UpdatedAt)
	}
	if len(d.DocumentGuides) == 0 || len(d.BenefitPrograms) == 0 || len(d.Places) == 0 {
		t.Fatalf("expected guides, programs and places, got %d/%d/%d", len(d.DocumentGuides), len(d.BenefitPrograms), len(d.Places))
	}

	ids := map[string]bool{}
	dial := regexp.MustCompile(`^\d{3,11}$`)
	for _, tp := range append(append([]fullTopic{}, d.DocumentGuides...), d.BenefitPrograms...) {
		if tp.ID == "" || ids[tp.ID] {
			t.Fatalf("topic ids must be present and unique: %q", tp.ID)
		}
		ids[tp.ID] = true
		if tp.Title == "" || tp.Summary == "" || len(tp.Sections) == 0 {
			t.Fatalf("%s: needs a title, summary and sections", tp.ID)
		}
		for _, s := range tp.Sections {
			if s.Heading == "" || len(s.Items) == 0 {
				t.Fatalf("%s: empty section %q", tp.ID, s.Heading)
			}
		}
		for _, l := range tp.Links {
			if u, err := url.Parse(l.URL); err != nil || u.Scheme != "https" || u.Host == "" {
				t.Fatalf("%s: link must be https: %q", tp.ID, l.URL)
			}
		}
		for _, p := range tp.Phones {
			if !dial.MatchString(p.Dial) || p.Display == "" {
				t.Fatalf("%s: bad phone %+v", tp.ID, p)
			}
		}
	}
}

func TestPlacesAreInTheSavannahArea(t *testing.T) {
	for _, p := range load(t).Places {
		if p.Name == "" || p.Address == "" || p.Note == "" {
			t.Fatalf("%s: needs a name, address and note", p.ID)
		}
		if p.Lat < 31.8 || p.Lat > 32.3 || p.Lng < -81.4 || p.Lng > -80.8 {
			t.Fatalf("%s: coordinates (%v, %v) are outside the Savannah area", p.ID, p.Lat, p.Lng)
		}
		if !strings.HasPrefix(p.URL, "https://") {
			t.Fatalf("%s: url must be https", p.ID)
		}
		if !regexp.MustCompile(`^\d{10}$`).MatchString(p.Phone.Dial) {
			t.Fatalf("%s: phone must be 10 digits, got %q", p.ID, p.Phone.Dial)
		}
		if p.Verified == "" {
			t.Fatalf("%s: must say when it was verified", p.ID)
		}
	}
}

func TestSourceURLsCoverEveryLinkAndPlace(t *testing.T) {
	urls := SourceURLs()
	have := map[string]bool{}
	for _, u := range urls {
		if have[u] {
			t.Fatalf("duplicate source %s", u)
		}
		have[u] = true
	}
	d := load(t)
	for _, tp := range append(append([]fullTopic{}, d.DocumentGuides...), d.BenefitPrograms...) {
		for _, l := range tp.Links {
			if !have[l.URL] {
				t.Fatalf("link %s is not being watched", l.URL)
			}
		}
	}
	for _, p := range d.Places {
		if !have[p.URL] {
			t.Fatalf("place %s is not being watched", p.URL)
		}
	}
}

func TestETagChangesOnlyWithTheContent(t *testing.T) {
	if ETag() != ETag() || ETag() == "" {
		t.Fatal("etag must be stable and non-empty")
	}
}
