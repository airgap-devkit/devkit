package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	TeamName       string `json:"team_name"`
	OrgName        string `json:"org_name"`
	DevkitName     string `json:"devkit_name"`
	ThemeColor     string `json:"theme_color"`
	DashboardTitle string `json:"dashboard_title"`
	Hostname       string `json:"hostname"`
	Port           int    `json:"port"`
	DefaultProfile string `json:"default_profile"`
	TeamConfigRepo string `json:"team_config_repo"`
	SetupComplete  bool   `json:"setup_complete"`
}

func Load(repoRoot string) Config {
	cfg := Config{
		TeamName:       "My Team",
		OrgName:        "",
		DevkitName:     "AirGap DevKit",
		ThemeColor:     "#2563eb",
		DashboardTitle: "Tool Dashboard",
		Hostname:       "127.0.0.1",
		Port:           9090,
		DefaultProfile: "minimal",
	}
	path := filepath.Join(repoRoot, "devkit.config.json")
	data, err := os.ReadFile(path)
	if err != nil {
		// No config file yet — defaults are sane; skip the setup wizard so the
		// API is immediately usable on a fresh install.
		cfg.SetupComplete = true
		return cfg
	}
	_ = json.Unmarshal(data, &cfg)
	if cfg.TeamName == "" {
		cfg.TeamName = "My Team"
	}
	if cfg.DevkitName == "" {
		cfg.DevkitName = "AirGap DevKit"
	}
	return cfg
}

func Save(repoRoot string, cfg Config) error {
	path := filepath.Join(repoRoot, "devkit.config.json")
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}
