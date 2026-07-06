package api

import (
	"os"
	"path/filepath"
	"testing"
)

const rhelSVG = "rhel.svg"

func TestDistroIcon(t *testing.T) {
	cases := map[string]string{
		"rhel":             rhelSVG,
		"redhat":           rhelSVG,
		"rocky":            "rocky.svg",
		"almalinux":        "almalinux.svg",
		"centos":           "centos.svg",
		"fedora":           "fedora.svg",
		"ubuntu":           "ubuntu.svg",
		"debian":           "debian.svg",
		"linuxmint":        "mint.svg",
		"opensuse-leap":    "opensuse.svg",
		"sles":             "suse.svg",
		"arch":             "arch.svg",
		"alpine":           "alpine.svg",
		"somethingunknown": "",
	}
	for id, want := range cases {
		if got := distroIcon(id); got != want {
			t.Errorf("distroIcon(%q) = %q, want %q", id, got, want)
		}
	}
}

func TestOSIconNonLinux(t *testing.T) {
	if got := osIcon("windows"); got != "windows.png" {
		t.Errorf("osIcon(windows) = %q", got)
	}
	if got := osIcon("darwin"); got != "macos.svg" {
		t.Errorf("osIcon(darwin) = %q", got)
	}
	if got := osIcon("plan9"); got != "linux.png" {
		t.Errorf("osIcon(plan9) fallback = %q", got)
	}
}

// Every filename osIcon can return must exist under web/static/img so the UI
// never points at a missing asset.
func TestOSIconAssetsExist(t *testing.T) {
	imgDir := filepath.Join("..", "..", "web", "static", "img")
	names := []string{
		"windows.png", "linux.png", "macos.svg",
		rhelSVG, "rocky.svg", "almalinux.svg", "centos.svg", "fedora.svg",
		"ubuntu.svg", "debian.svg", "mint.svg", "opensuse.svg", "suse.svg",
		"arch.svg", "alpine.svg",
	}
	for _, n := range names {
		if _, err := os.Stat(filepath.Join(imgDir, n)); err != nil {
			t.Errorf("missing logo asset %s: %v", n, err)
		}
	}
}
