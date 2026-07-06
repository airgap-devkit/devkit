package timefmt

import (
	"testing"
	"time"
)

// pacific2240 is 2026-07-06 05:40 UTC rendered in the display zone (US Pacific).
const pacific2240 = "2026-07-05-22:40 PDT"

func TestDisplayIsPacific24h(t *testing.T) {
	// 2026-07-06 05:40 UTC == 2026-07-05 22:40 PDT.
	got := Display(time.Date(2026, 7, 6, 5, 40, 0, 0, time.UTC))
	if want := pacific2240; got != want {
		t.Fatalf("Display = %q, want %q", got, want)
	}
}

func TestNormalize(t *testing.T) {
	cases := map[string]string{
		"2026-04-19T06:51:06Z": "2026-04-18-23:51 PDT", // RFC3339 (modal Upload Time)
		"2026-07-06 05:40 UTC": pacific2240,            // legacy upload format
		"04/19/2026 00:39":     "2026-04-18-17:39 PDT", // legacy receipt date
		pacific2240:            pacific2240,            // already normalised (idempotent)
		"(system install)":     "(system install)",     // non-timestamp passes through
		"":                     "",
	}
	for in, want := range cases {
		if got := Normalize(in); got != want {
			t.Errorf("Normalize(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSetFormatSwitchesStyle(t *testing.T) {
	t.Cleanup(func() { SetFormat(DefaultID) })
	ref := time.Date(2026, 7, 6, 5, 40, 0, 0, time.UTC)
	cases := map[string]string{
		"us12":    "07/05/2026 10:40 PM PDT",
		"iso24":   "2026-07-05 22:40 PDT",
		"long12":  "Jul 5, 2026 10:40 PM PDT",
		"iso8601": "2026-07-05T22:40:00-07:00",
	}
	for id, want := range cases {
		SetFormat(id)
		if got := Display(ref); got != want {
			t.Errorf("Display after SetFormat(%q) = %q, want %q", id, got, want)
		}
	}
	// Unknown / empty ids fall back to the default style.
	SetFormat("bogus")
	if got := Display(ref); got != pacific2240 {
		t.Errorf("Display after unknown format = %q, want default %q", got, pacific2240)
	}
}

func TestFormatsHaveExamples(t *testing.T) {
	fs := Formats()
	if len(fs) == 0 {
		t.Fatal("Formats() returned nothing")
	}
	for _, f := range fs {
		if f.ID == "" || f.Label == "" || f.Example == "" {
			t.Errorf("incomplete format entry: %+v", f)
		}
	}
}
