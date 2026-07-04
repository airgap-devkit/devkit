package api

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultProfilesFallback(t *testing.T) {
	// No profiles.defaults.json in an empty dir → compiled-in fallback.
	dir := t.TempDir()
	got := defaultProfiles(dir, []string{"a", "b"})
	if len(got) != 4 {
		t.Fatalf("fallback: expected 4 profiles, got %d", len(got))
	}
	if full := got["full"]; len(full.ToolIDs) != 2 {
		t.Fatalf("fallback: full should carry allIDs, got %v", full.ToolIDs)
	}
}

func TestDefaultProfilesFromFile(t *testing.T) {
	dir := t.TempDir()
	json := `{
	  "_doc": "ignore me",
	  "minimal": {"name": "Min", "description": "d", "color": "gray", "tool_ids": ["cmake"]},
	  "full": {"name": "Full", "description": "d", "color": "purple", "tool_ids": ["__all__"]}
	}`
	if err := os.WriteFile(filepath.Join(dir, "profiles.defaults.json"), []byte(json), 0o600); err != nil {
		t.Fatal(err)
	}
	all := []string{"cmake", "python", "conan"}
	got := defaultProfiles(dir, all)

	if _, ok := got["_doc"]; ok {
		t.Error("keys beginning with _ must be skipped")
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 profiles, got %d", len(got))
	}
	if m := got["minimal"]; m.ID != "minimal" || m.Name != "Min" || len(m.ToolIDs) != 1 {
		t.Errorf("minimal parsed incorrectly: %+v", m)
	}
	if f := got["full"]; len(f.ToolIDs) != len(all) {
		t.Errorf("__all__ should expand to allIDs, got %v", f.ToolIDs)
	}
}

func TestDefaultProfilesInvalidJSON(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "profiles.defaults.json"), []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := defaultProfiles(dir, nil); len(got) != 4 {
		t.Fatalf("invalid JSON should fall back to 4 built-in profiles, got %d", len(got))
	}
}
