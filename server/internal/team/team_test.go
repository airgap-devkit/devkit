package team

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDirHelpers(t *testing.T) {
	root := t.TempDir()
	if got := Dir(root); !strings.HasSuffix(got, dirName) {
		t.Errorf("Dir = %q, want suffix %q", got, dirName)
	}
	if got := CustomToolsDir(root); !strings.HasSuffix(got, filepath.Join(dirName, "tools")) {
		t.Errorf("CustomToolsDir = %q", got)
	}
}

func TestSafeRepoURL(t *testing.T) {
	good := []string{"https://example.com/r.git", "ssh://git@host/r.git", "git@host:group/repo.git"}
	for _, u := range good {
		if !safeRepoURL(u) {
			t.Errorf("safeRepoURL(%q) = false, want true", u)
		}
	}
	bad := []string{"", "-oProxyCommand=evil", "ftp://x/y", "plainstring"}
	for _, u := range bad {
		if safeRepoURL(u) {
			t.Errorf("safeRepoURL(%q) = true, want false", u)
		}
	}
}

func TestCloneOrPullRejectsUnsafeURL(t *testing.T) {
	if _, err := CloneOrPull("-oProxyCommand=evil", t.TempDir()); err == nil {
		t.Fatal("CloneOrPull accepted an unsafe repo URL")
	}
}

func TestLastCommitNonRepo(t *testing.T) {
	if got := LastCommit(t.TempDir()); got != "" {
		t.Errorf("LastCommit of non-repo = %q, want empty", got)
	}
}

func TestLoadConfig(t *testing.T) {
	dir := t.TempDir()

	// Missing file → error.
	if _, err := LoadConfig(dir); err == nil {
		t.Fatal("LoadConfig accepted a missing file")
	}

	path := filepath.Join(dir, "team-config.json")

	// Invalid JSON → error.
	if err := os.WriteFile(path, []byte("{bad"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(dir); err == nil {
		t.Fatal("LoadConfig accepted invalid JSON")
	}

	// Valid file → parsed.
	if err := os.WriteFile(path, []byte(`{"team_name":"T","tool_ids":["cmake"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	tc, err := LoadConfig(dir)
	if err != nil {
		t.Fatalf("LoadConfig valid: %v", err)
	}
	if tc.TeamName != "T" || len(tc.ToolIDs) != 1 {
		t.Fatalf("parsed config wrong: %+v", tc)
	}
}
