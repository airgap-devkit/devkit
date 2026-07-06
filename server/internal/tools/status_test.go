package tools

import (
	"os"
	"path/filepath"
	"testing"
)

const toolName = "cmake"

func writeReceipt(t *testing.T, prefix, receiptFile, content string) {
	t.Helper()
	toolDir := filepath.Join(prefix, toolName)
	if err := os.MkdirAll(toolDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(toolDir, receiptFile), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestParseReceiptSuccess(t *testing.T) {
	prefix := t.TempDir()
	writeReceipt(t, prefix, "INSTALL_RECEIPT.txt",
		"Status: success\nVersion: 3.29.1\nInstall-Path: /opt/cmake\n")

	r := GetReceipt(prefix, toolName)
	if !r.Exists || r.Status != "success" || r.Version != "3.29.1" || r.InstallPath != "/opt/cmake" {
		t.Fatalf("parsed receipt wrong: %+v", r)
	}
}

func TestGetReceiptMissing(t *testing.T) {
	r := GetReceipt(t.TempDir(), "nope")
	if r.Exists || r.Status != "not_installed" {
		t.Fatalf("missing receipt: %+v", r)
	}
}

func TestReceiptInstalledAtImpliesSuccess(t *testing.T) {
	prefix := t.TempDir()
	writeReceipt(t, prefix, "INSTALL_LOG.txt", "Installed-At: 2026-07-06 05:40 UTC\nVersion: 1.0\n")

	r := GetReceipt(prefix, toolName)
	if r.Status != "success" || r.Date == "" {
		t.Fatalf("installed-at should imply success with a normalised date: %+v", r)
	}
}

func TestExtractVersion(t *testing.T) {
	cases := map[string]string{
		"cmake version 3.29.1": "3.29.1",
		"clang 17.0.6 (rev)":   "17.0.6",
		"no digits here":       "no digits here",
		"":                     "",
	}
	for in, want := range cases {
		if got := extractVersion(in); got != want {
			t.Errorf("extractVersion(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGetStatusInstalledWithUpdate(t *testing.T) {
	prefix := t.TempDir()
	writeReceipt(t, prefix, "INSTALL_RECEIPT.txt", "Status: success\nVersion: 3.28.0\n")

	tool := Tool{ID: toolName, ReceiptName: toolName, Version: "3.29.0", Platform: "both"}
	st := GetStatus(tool, prefix, "linux")
	if !st.Installed || !st.Available {
		t.Fatalf("want installed+available: %+v", st)
	}
	if !st.UpdateAvailable {
		t.Fatal("version mismatch should flag an available update")
	}
}

func TestGetStatusNotInstalled(t *testing.T) {
	tool := Tool{ID: toolName, ReceiptName: toolName, Version: "3.29.0", Platform: "linux"}
	st := GetStatus(tool, t.TempDir(), "linux")
	if st.Installed {
		t.Fatal("no receipt should read as not installed")
	}
	if !st.Available {
		t.Fatal("a linux tool on linux should be available")
	}
	if st.UpdateAvailable {
		t.Fatal("uninstalled tool must not report an update")
	}
}
