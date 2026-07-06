package api

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/nimzshafie/airgap-devkit/server/internal/timefmt"
)

// apiEndpoint documents a single REST route on the /api-docs page.
type apiEndpoint struct {
	Method string
	Path   string
	Desc   string
	// Try holds a directly-openable URL for parameter-free GET endpoints, or
	// "" when the endpoint takes a path parameter / non-GET method.
	Try string
}

// apiGroup is a titled cluster of related endpoints.
type apiGroup struct {
	Name      string
	Endpoints []apiEndpoint
}

// apiReference is the curated endpoint catalogue rendered on /api-docs. It is
// kept in sync with Routes() by hand — only the stable, documented surface is
// listed here (internal SSE/HTMX plumbing is intentionally omitted).
func apiReference() []apiGroup {
	get := func(path, desc, try string) apiEndpoint {
		return apiEndpoint{Method: "GET", Path: path, Desc: desc, Try: try}
	}
	return []apiGroup{
		{Name: "Tools", Endpoints: []apiEndpoint{
			get("/api/tools", "List every tool with its live install status.", "/api/tools"),
			get("/api/tool/{id}", "Status for a single tool by id.", ""),
			get("/api/tool/{id}/versions", "Installed versions of a tool.", ""),
			get("/check/{id}", "Run a tool's check command and return its output.", ""),
		}},
		{Name: "Install & lifecycle", Endpoints: []apiEndpoint{
			get("/install/{id}", "Install a tool (server-sent event stream).", ""),
			get("/install-profile/{id}", "Install every tool in a profile (SSE stream).", ""),
			{Method: "DELETE", Path: "/uninstall/{id}", Desc: "Remove an installed tool and scrub its PATH entries."},
			get("/api/health/tools", "Validate all installed tools in parallel.", "/api/health/tools"),
		}},
		{Name: "Profiles", Endpoints: []apiEndpoint{
			get(pathAPIProfiles, "List the curated install profiles.", pathAPIProfiles),
			{Method: "POST", Path: pathAPIProfiles, Desc: "Create or update a profile."},
			{Method: "DELETE", Path: "/api/profiles/{id}", Desc: "Delete a profile."},
		}},
		{Name: "Configuration & team", Endpoints: []apiEndpoint{
			get("/api/prefix", "Current install prefix.", "/api/prefix"),
			{Method: "POST", Path: "/api/config", Desc: "Save team / org / devkit settings."},
			get("/api/export", "Download a shareable team-config JSON.", "/api/export"),
			{Method: "POST", Path: "/api/import", Desc: "Import a team-config JSON."},
			get("/api/team/status", "Team config sync status.", "/api/team/status"),
			{Method: "POST", Path: "/api/team/sync", Desc: "Trigger a team config sync."},
		}},
		{Name: "System", Endpoints: []apiEndpoint{
			get("/health", "Machine-readable liveness probe (JSON).", "/health"),
			get("/status", "Human-readable server status page.", "/status"),
			get("/api/network", "Network egress reachability check.", "/api/network"),
			get("/api/updates", "Check for available tool updates.", "/api/updates"),
		}},
	}
}

// formatUptime renders a duration as a compact human string (e.g. "2h 14m").
func formatUptime(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	days := int(d.Hours()) / 24
	hours := int(d.Hours()) % 24
	mins := int(d.Minutes()) % 60
	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh %dm", days, hours, mins)
	case hours > 0:
		return fmt.Sprintf("%dh %dm", hours, mins)
	default:
		return fmt.Sprintf("%dm", mins)
	}
}

func (s *Server) handleStatusPage(w http.ResponseWriter, r *http.Request) {
	ts := s.getTools()
	installed := 0
	for _, t := range ts {
		if t.Installed {
			installed++
		}
	}
	hostname, _ := os.Hostname()

	data := map[string]any{
		"Config":         s.Config,
		"OS":             s.OS,
		"OSLabel":        osLabel(s.OS),
		"OSIcon":         osIcon(s.OS),
		"Hostname":       hostname,
		"OSUsername":     currentOSUsername(),
		"Privilege":      detectPrivilege(),
		"Prefix":         s.currentPrefix(),
		"InstalledCount": installed,
		"TotalCount":     len(ts),
		"AppVersion":     AppVersion,
		"Uptime":         formatUptime(time.Since(s.startTime)),
		"StartedAt":      timefmt.Display(s.startTime),
		"Year":           time.Now().Year(),
	}
	if err := renderTemplate(s.webFS, "status.html", w, r, data); err != nil {
		http.Error(w, "template error: "+err.Error(), 500)
	}
}

func (s *Server) handleAPIDocs(w http.ResponseWriter, r *http.Request) {
	data := map[string]any{
		"Config":     s.Config,
		"OS":         s.OS,
		"AppVersion": AppVersion,
		"Groups":     apiReference(),
		"Year":       time.Now().Year(),
	}
	if err := renderTemplate(s.webFS, "api-docs.html", w, r, data); err != nil {
		http.Error(w, "template error: "+err.Error(), 500)
	}
}
