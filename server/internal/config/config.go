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
	AllowEgress    bool   `json:"allow_egress"`
	TimeFormat     string `json:"time_format"` // selected timestamp style id (see internal/timefmt); empty = default

	// Package upload limits and behaviour. All sizes are in bytes. Zero means
	// "use the built-in default" (applied in Load); a caller may set an explicit
	// value to raise or lower any cap without recompiling.
	UploadMaxBytes        int64  `json:"upload_max_bytes"`         // total archive size accepted by the resumable endpoint
	UploadChunkSize       int64  `json:"upload_chunk_size"`        // client chunk size hint (bytes per PATCH)
	ZipMaxUncompressed    int64  `json:"zip_max_uncompressed"`     // guard against zip-bomb expansion
	ZipMaxEntryBytes      int64  `json:"zip_max_entry_bytes"`      // per-file cap inside the archive
	UploadTempDir         string `json:"upload_temp_dir"`          // where in-progress uploads are assembled (needs archive + extraction headroom)
	UploadSessionTTLHours int    `json:"upload_session_ttl_hours"` // abandoned uploads older than this are reaped
	AllowPathImport       bool   `json:"allow_path_import"`        // enable the localhost import-from-disk endpoint
}

// Upload default limits. Chosen to comfortably exceed multi-GB toolchain
// archives while still bounding disk use on a shared team server.
const (
	DefaultUploadMaxBytes        = 8 << 30  // 8 GiB
	DefaultUploadChunkSize       = 16 << 20 // 16 MiB per PATCH
	DefaultZipMaxUncompressed    = 16 << 30 // 16 GiB expanded
	DefaultZipMaxEntryBytes      = 8 << 30  // 8 GiB per file
	DefaultUploadSessionTTLHours = 24
)

// applyUploadDefaults fills any unset (zero) upload field with its built-in
// default so older config files and fresh installs behave identically.
func (c *Config) applyUploadDefaults(repoRoot string) {
	if c.UploadMaxBytes == 0 {
		c.UploadMaxBytes = DefaultUploadMaxBytes
	}
	if c.UploadChunkSize == 0 {
		c.UploadChunkSize = DefaultUploadChunkSize
	}
	if c.ZipMaxUncompressed == 0 {
		c.ZipMaxUncompressed = DefaultZipMaxUncompressed
	}
	if c.ZipMaxEntryBytes == 0 {
		c.ZipMaxEntryBytes = DefaultZipMaxEntryBytes
	}
	if c.UploadSessionTTLHours == 0 {
		c.UploadSessionTTLHours = DefaultUploadSessionTTLHours
	}
	if c.UploadTempDir == "" {
		c.UploadTempDir = filepath.Join(repoRoot, ".devkit-uploads")
	}
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
		cfg.applyUploadDefaults(repoRoot)
		return cfg
	}
	_ = json.Unmarshal(data, &cfg)
	if cfg.TeamName == "" {
		cfg.TeamName = "My Team"
	}
	if cfg.DevkitName == "" {
		cfg.DevkitName = "AirGap DevKit"
	}
	cfg.applyUploadDefaults(repoRoot)
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
