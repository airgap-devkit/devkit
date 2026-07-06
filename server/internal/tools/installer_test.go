package tools

import (
	"runtime"
	"strings"
	"testing"
)

func TestToBashPath(t *testing.T) {
	// Paths without a drive letter are returned unchanged on every platform.
	for _, p := range []string{"/already/posix", "relative/dir"} {
		if got := ToBashPath(p); got != p {
			t.Errorf("ToBashPath(%q) = %q, want unchanged", p, got)
		}
	}
	// The drive-letter → /c/ rewrite only applies on Windows.
	if runtime.GOOS == "windows" {
		if got := ToBashPath(`C:\Users\x`); got != "/c/Users/x" {
			t.Errorf("ToBashPath drive letter = %q, want /c/Users/x", got)
		}
	}
}

func TestBuildEnv(t *testing.T) {
	tool := Tool{ID: "cmake", ReceiptName: "cmake"}
	env := BuildEnv(tool, "/opt/prefix", "/opt/prebuilt", "linux")

	var sawOS, sawPrefix, sawPrebuilt bool
	for _, e := range env {
		switch {
		case e == "AIRGAP_OS=linux":
			sawOS = true
		case strings.HasPrefix(e, "INSTALL_PREFIX=") && strings.Contains(e, "cmake"):
			sawPrefix = true
		case strings.HasPrefix(e, "PREBUILT_DIR="):
			sawPrebuilt = true
		}
	}
	if !sawOS || !sawPrefix || !sawPrebuilt {
		t.Fatalf("BuildEnv missing entries: os=%v prefix=%v prebuilt=%v", sawOS, sawPrefix, sawPrebuilt)
	}
}

func TestFindBash(t *testing.T) {
	if FindBash() == "" {
		t.Fatal("FindBash returned empty")
	}
}
