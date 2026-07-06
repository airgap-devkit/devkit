// Package timefmt renders every user-facing timestamp in one consistent shape.
// The shape is user-selectable (Settings ▸ Time Format) — 24-hour, 12-hour, US,
// long, and ISO variants — and always rendered in US Pacific time.
package timefmt

import (
	"strings"
	"sync"
	"time"
	_ "time/tzdata" // embed the zone database so America/Los_Angeles resolves on any host, including air-gapped RHEL and Windows without a system tzdata
)

// Format is one selectable timestamp style shown in Settings.
type Format struct {
	ID      string `json:"id"`
	Label   string `json:"label"`
	Layout  string `json:"layout"`
	Example string `json:"example"`
}

// DefaultID is the style applied when none is configured. It preserves the
// original 24-hour Pacific rendering, e.g. "2026-07-05-22:40 PDT".
const DefaultID = "iso"

// formats is the curated catalogue of popular styles. The MST token renders the
// zone abbreviation (PDT/PST); the ISO 8601 style carries a numeric offset.
var formats = []Format{
	{ID: "iso", Label: "ISO date, 24-hour", Layout: "2006-01-02-15:04 MST"},
	{ID: "iso24", Label: "ISO date & time, 24-hour", Layout: "2006-01-02 15:04 MST"},
	{ID: "iso12", Label: "ISO date, 12-hour", Layout: "2006-01-02 03:04 PM MST"},
	{ID: "us24", Label: "US (MM/DD/YYYY), 24-hour", Layout: "01/02/2006 15:04 MST"},
	{ID: "us12", Label: "US (MM/DD/YYYY), 12-hour", Layout: "01/02/2006 03:04 PM MST"},
	{ID: "long24", Label: "Long month, 24-hour", Layout: "Jan 2, 2006 15:04 MST"},
	{ID: "long12", Label: "Long month, 12-hour", Layout: "Jan 2, 2006 3:04 PM MST"},
	{ID: "iso8601", Label: "ISO 8601 (offset)", Layout: "2006-01-02T15:04:05-07:00"},
}

var (
	pacific = loadPacific()

	mu           sync.RWMutex
	activeLayout = layoutFor(DefaultID)
)

func loadPacific() *time.Location {
	if loc, err := time.LoadLocation("America/Los_Angeles"); err == nil {
		return loc
	}
	return time.UTC
}

func layoutFor(id string) string {
	for _, f := range formats {
		if f.ID == id {
			return f.Layout
		}
	}
	return formats[0].Layout
}

// SetFormat selects the active style by id. An empty or unknown id falls back to
// the default. Safe for concurrent use.
func SetFormat(id string) {
	if strings.TrimSpace(id) == "" {
		id = DefaultID
	}
	mu.Lock()
	activeLayout = layoutFor(id)
	mu.Unlock()
}

func layout() string {
	mu.RLock()
	defer mu.RUnlock()
	return activeLayout
}

// Formats returns the catalogue with a rendered Example for each style, so the
// Settings UI can preview them. The reference instant is 2026-07-05 22:40 PDT.
func Formats() []Format {
	ref := time.Date(2026, 7, 6, 5, 40, 0, 0, time.UTC).In(pacific)
	out := make([]Format, len(formats))
	copy(out, formats)
	for i := range out {
		out[i].Example = ref.Format(out[i].Layout)
	}
	return out
}

// Display formats an instant in Pacific time using the active style.
func Display(t time.Time) string {
	return t.In(pacific).Format(layout())
}

// Now returns the current instant formatted via Display.
func Now() string {
	return Display(time.Now())
}

// parseLayouts covers every canonical timestamp shape written to receipts,
// manifests, and history files, so stored values render consistently on read.
var parseLayouts = []string{
	time.RFC3339,
	"2006-01-02T15:04:05Z",
	"2006-01-02 15:04 UTC",
	"2006-01-02 15:04:05",
	"2006-01-02 15:04",
	"01/02/2006 15:04",
	"200601021504",
	"Mon Jan 02 15:04:05 MST 2006",
	"Mon Jan 02 15:04:05 2006",
	"Jan 02, 2006 15:04:05 MST",
	"2006-01-02",
}

// Normalize parses a stored timestamp in any canonical layout and re-renders it
// via Display. Values already rendered in a zone-abbreviated style (ending in
// PDT/PST) and unparseable input pass through unchanged, so applying it twice is
// safe and it never mis-reads its own zone-abbreviated output.
func Normalize(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" || strings.HasSuffix(raw, " PDT") || strings.HasSuffix(raw, " PST") {
		return raw
	}
	for _, l := range parseLayouts {
		if t, err := time.ParseInLocation(l, raw, time.UTC); err == nil {
			return Display(t)
		}
	}
	return raw
}
