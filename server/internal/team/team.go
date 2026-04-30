package team

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/nimzshafie/airgap-devkit/server/internal/export"
)

const dirName = ".devkit-team-config"

type Status struct {
	Configured bool      `json:"configured"`
	RepoURL    string    `json:"repo_url"`
	LastSync   time.Time `json:"last_sync"`
	Commit     string    `json:"commit"`
	Error      string    `json:"error,omitempty"`
}

func Dir(repoRoot string) string {
	return filepath.Join(repoRoot, dirName)
}

func CustomToolsDir(repoRoot string) string {
	return filepath.Join(Dir(repoRoot), "tools")
}

// CloneOrPull clones repoURL into destDir if it doesn't exist, otherwise pulls.
// Returns the short commit hash of HEAD after the operation.
func CloneOrPull(repoURL, destDir string) (string, error) {
	if _, err := os.Stat(filepath.Join(destDir, ".git")); os.IsNotExist(err) {
		if err2 := os.MkdirAll(filepath.Dir(destDir), 0o755); err2 != nil {
			return "", fmt.Errorf("mkdir: %w", err2)
		}
		cmd := exec.Command("git", "clone", "--depth=1", repoURL, destDir)
		cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
		if out, err2 := cmd.CombinedOutput(); err2 != nil {
			return "", fmt.Errorf("git clone: %s", strings.TrimSpace(string(out)))
		}
	} else {
		cmd := exec.Command("git", "-C", destDir, "pull", "--ff-only")
		cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
		if out, err2 := cmd.CombinedOutput(); err2 != nil {
			return "", fmt.Errorf("git pull: %s", strings.TrimSpace(string(out)))
		}
	}
	return LastCommit(destDir), nil
}

// LastCommit returns "shortHash subject" for HEAD, or empty string on error.
func LastCommit(destDir string) string {
	out, err := exec.Command("git", "-C", destDir, "log", "-1", "--format=%h %s").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// LoadConfig reads team-config.json from the cloned team config directory.
func LoadConfig(destDir string) (*export.TeamConfig, error) {
	path := filepath.Join(destDir, "team-config.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("team-config.json not found: %w", err)
	}
	var tc export.TeamConfig
	if err := json.Unmarshal(data, &tc); err != nil {
		return nil, fmt.Errorf("invalid team-config.json: %w", err)
	}
	return &tc, nil
}
