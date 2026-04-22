package tools

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type Receipt struct {
	Exists      bool   `json:"exists"`
	Status      string `json:"status"`
	Version     string `json:"version"`
	Date        string `json:"date"`
	InstallPath string `json:"install_path"`
}

type ToolStatus struct {
	Tool
	Installed       bool    `json:"installed"`
	Available       bool    `json:"available"`
	Receipt         Receipt `json:"receipt"`
	UpdateAvailable bool    `json:"update_available"`
}

func GetReceipt(prefix, receiptName string) Receipt {
	clean := strings.ReplaceAll(receiptName, "/", string(os.PathSeparator))
	toolDir := filepath.Join(prefix, clean)

	// Prefer new name, fall back to legacy
	for _, name := range []string{"INSTALL_LOG.txt", "INSTALL_RECEIPT.txt"} {
		path := filepath.Join(toolDir, name)
		if r, ok := parseReceipt(path); ok {
			return r
		}
	}
	return Receipt{Status: "not_installed"}
}

func parseReceipt(path string) (Receipt, bool) {
	f, err := os.Open(path)
	if err != nil {
		return Receipt{}, false
	}
	defer f.Close()

	r := Receipt{Exists: true, Status: "not_installed"}
	hasInstalledAt := false

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		var key, val string
		ei := strings.Index(line, "=")
		ci := strings.Index(line, ":")
		if ei != -1 && (ci == -1 || ei < ci) {
			// '=' separator (receipt format: key=value)
			key = strings.ToLower(strings.TrimSpace(line[:ei]))
			val = strings.TrimSpace(line[ei+1:])
		} else if ci != -1 {
			// ':' separator (log format: Key: value)
			key = strings.ToLower(strings.TrimSpace(line[:ci]))
			val = strings.TrimSpace(line[ci+1:])
		} else {
			continue
		}
		key = strings.ReplaceAll(key, "-", "_")
		switch key {
		case "version":
			r.Version = val
		case "status":
			r.Status = val
		case "installed_at":
			r.Date = normaliseDate(val)
			hasInstalledAt = true
		case "date":
			r.Date = normaliseDate(val)
		case "install_path", "install_prefix":
			r.InstallPath = val
		}
	}
	if r.Status == "not_installed" && hasInstalledAt {
		r.Status = "success"
	}
	return r, true
}

var dateFmts = []string{
	"01/02/2006 15:04",
	"200601021504",
	"Mon Jan 02 15:04:05 MST 2006",
	"Mon Jan 02 15:04:05 2006",
	"2006-01-02T15:04:05Z",
	"2006-01-02T15:04:05",
	"2006-01-02 15:04:05",
	"2006-01-02 15:04",
	"2006-01-02",
}

func normaliseDate(raw string) string {
	raw = strings.TrimSpace(raw)
	for _, fmt := range dateFmts {
		if t, err := time.Parse(fmt, raw); err == nil {
			return t.Format("01/02/2006 15:04")
		}
	}
	return raw
}

// probeSystemInstall runs check_cmd to detect a system-installed tool (no receipt).
// Returns the version string extracted from output, or "" if not found.
func probeSystemInstall(checkCmd string) string {
	if checkCmd == "" {
		return ""
	}
	parts := strings.Fields(checkCmd)
	if len(parts) == 0 {
		return ""
	}
	cmd := exec.Command(parts[0], parts[1:]...)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	// Extract first version-like token from output (e.g. "cmake version 4.2.3" → "4.2.3")
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		for _, f := range fields {
			if len(f) > 0 && (f[0] >= '0' && f[0] <= '9') && strings.Contains(f, ".") {
				return f
			}
		}
		// Return truncated first line as fallback
		if len(line) > 60 {
			line = line[:60]
		}
		return line
	}
	return ""
}

func GetStatus(t Tool, prefix, currentOS string) ToolStatus {
	receipt := GetReceipt(prefix, t.ReceiptName)
	installed := receipt.Status == "success"
	available := t.Platform == "both" || t.Platform == currentOS

	// If no receipt, probe system PATH via check_cmd
	if !installed && t.CheckCmd != "" {
		// On Windows, run via cmd /c so PATH-based tools resolve correctly
		checkCmd := t.CheckCmd
		if runtime.GOOS == "windows" {
			checkCmd = "cmd /c " + checkCmd
		}
		if ver := probeSystemInstall(checkCmd); ver != "" {
			installed = true
			receipt = Receipt{
				Exists:  true,
				Status:  "success",
				Version: ver,
				Date:    "(system install)",
			}
		}
	}

	updateAvailable := false
	installedVer := strings.TrimSpace(receipt.Version)
	availVer := strings.TrimSpace(t.Version)
	if installed && installedVer != "" && availVer != "" && installedVer != availVer {
		updateAvailable = true
	}

	return ToolStatus{
		Tool:            t,
		Installed:       installed,
		Available:       available,
		Receipt:         receipt,
		UpdateAvailable: updateAvailable,
	}
}
