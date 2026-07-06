package config

import (
	"os"
	"path/filepath"
	"testing"
)

const defaultTeam = "My Team"

func TestLoadDefaultsWhenNoFile(t *testing.T) {
	cfg := Load(t.TempDir())
	if !cfg.SetupComplete {
		t.Error("missing config should default SetupComplete=true")
	}
	if cfg.TeamName != defaultTeam || cfg.Port != 9090 {
		t.Errorf("defaults wrong: team=%q port=%d", cfg.TeamName, cfg.Port)
	}
	if cfg.UploadMaxBytes != DefaultUploadMaxBytes || cfg.UploadTempDir == "" {
		t.Errorf("upload defaults not applied: max=%d tmp=%q", cfg.UploadMaxBytes, cfg.UploadTempDir)
	}
}

func TestSaveLoadRoundtrip(t *testing.T) {
	dir := t.TempDir()
	in := Load(dir)
	in.OrgName = "ACME"
	in.DevkitName = "Kit"
	in.Port = 8123
	in.TimeFormat = "iso"
	in.AllowEgress = true
	if err := Save(dir, in); err != nil {
		t.Fatalf("save: %v", err)
	}
	out := Load(dir)
	if out.OrgName != "ACME" || out.DevkitName != "Kit" || out.Port != 8123 ||
		out.TimeFormat != "iso" || !out.AllowEgress {
		t.Fatalf("roundtrip mismatch: %+v", out)
	}
}

func TestLoadRestoresBlankNames(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "devkit.config.json")
	if err := os.WriteFile(path, []byte(`{"team_name":"","devkit_name":""}`), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := Load(dir)
	if cfg.TeamName != defaultTeam || cfg.DevkitName != "AirGap DevKit" {
		t.Fatalf("blank names not restored: %q %q", cfg.TeamName, cfg.DevkitName)
	}
}
