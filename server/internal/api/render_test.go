package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestRenderedPages exercises every server-rendered HTML page against the real
// templates in web/, confirming each returns 200 with an HTML body.
func TestRenderedPages(t *testing.T) {
	h := apiTestServer(t).Routes()
	for _, path := range []string{"/", "/status", "/logs", "/api-docs"} {
		rec := authReq(t, h, http.MethodGet, path, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s: want 200, got %d (%s)", path, rec.Code, rec.Body.String())
		}
		if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "text/html") {
			t.Errorf("GET %s: content-type = %q", path, ct)
		}
		if rec.Body.Len() == 0 {
			t.Errorf("GET %s: empty body", path)
		}
	}
}

// TestSetupPageWhenIncomplete renders the first-run setup page (only shown while
// setup is incomplete) and confirms a completed setup redirects to the app.
func TestSetupPageWhenIncomplete(t *testing.T) {
	s := apiTestServer(t)
	s.Config.SetupComplete = false
	h := s.Routes()

	rec := authReq(t, h, http.MethodGet, pathSetup, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("setup page: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}

	// Once complete, /setup redirects to the dashboard.
	s.Config.SetupComplete = true
	rec = authReq(t, h, http.MethodGet, pathSetup, nil)
	if rec.Code != http.StatusFound {
		t.Fatalf("completed setup: want 302, got %d", rec.Code)
	}
}

func TestSaveSetup(t *testing.T) {
	s := apiTestServer(t)
	s.Config.SetupComplete = false
	h := s.Routes()

	rec := authReq(t, h, http.MethodPost, pathSetupAPI,
		[]byte(`{"team_name":"Team","devkit_name":"Kit","team_config_repo":""}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save setup: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	if !s.Config.SetupComplete {
		t.Fatal("save setup did not mark setup complete")
	}

	// Malformed body and insecure repo URL are rejected.
	if rec := authReq(t, h, http.MethodPost, pathSetupAPI, []byte(`nope`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("bad setup body: want 400, got %d", rec.Code)
	}
	if rec := authReq(t, h, http.MethodPost, pathSetupAPI,
		[]byte(`{"team_config_repo":"http://insecure/x.git"}`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("insecure repo: want 400, got %d", rec.Code)
	}
}

// TestRenderTemplateEscaping asserts the toJSON template helper neutralises a
// "</script>" sequence embedded in tool data so it cannot break out of a
// <script> block.
func TestRenderTemplateEscaping(t *testing.T) {
	s := apiTestServer(t)
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r = r.WithContext(context.WithValue(r.Context(), nonceKey, "test-nonce"))
	rec := httptest.NewRecorder()

	data := map[string]any{
		"Tools":       []map[string]any{{"id": "x", "name": "</script><b>pwn"}},
		"Categories":  map[string]any{},
		"Bundles":     []any{},
		"Profiles":    map[string]any{},
		"Config":      s.Config,
		"OS":          s.OS,
		"OSLabel":     "Linux",
		"OSIcon":      "linux.png",
		"Prefix":      s.prefix,
		"Year":        2026,
		"AppVersion":  AppVersion,
		"TimeFormats": []any{},
		"TimeFormat":  "iso",
	}
	if err := renderTemplate(s.webFS, "dashboard.html", rec, r, data); err != nil {
		t.Fatalf("render dashboard: %v", err)
	}
	body := rec.Body.String()
	// The payload data must be present (proving it was rendered) but every angle
	// bracket must be escaped — no raw "</script>" or "<b>" may reach the page.
	if !strings.Contains(body, "pwn") {
		t.Fatal("tool data was not rendered at all")
	}
	if strings.Contains(body, "</script><b>pwn") || strings.Contains(body, "<b>pwn") {
		t.Fatalf("angle brackets rendered unescaped into the page")
	}
	if !strings.Contains(body, `<`) {
		t.Fatal("expected unicode-escaped angle bracket from toJSON not found")
	}
}

// ── Tool log & manual-install handlers ───────────────────────────────────────

func TestToolLogEndpoints(t *testing.T) {
	h := apiTestServer(t).Routes()
	base := pathToolPre + toolCMakeID

	// No install log yet → ok:false but 200.
	rec := authReq(t, h, http.MethodGet, base+"/log", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("tool log: want 200, got %d", rec.Code)
	}

	// Empty log directory → ok:true, empty list.
	rec = authReq(t, h, http.MethodGet, base+"/logs", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("tool log list: want 200, got %d", rec.Code)
	}

	// A filename with letters/traversal is rejected by the charset allowlist.
	if rec := authReq(t, h, http.MethodGet, base+"/logs/not-a-valid-name", nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid log filename: want 400, got %d", rec.Code)
	}
	// A charset-valid but non-existent file → 404.
	if rec := authReq(t, h, http.MethodGet, base+"/logs/20260101-120000", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("missing log file: want 404, got %d", rec.Code)
	}
}

func TestManualInstall(t *testing.T) {
	h := apiTestServer(t).Routes()

	rec := authReq(t, h, http.MethodGet, pathToolPre+toolCMakeID+"/manual-install", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("manual install: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	if rec := authReq(t, h, http.MethodGet, pathToolPre+"nope/manual-install", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("manual install unknown: want 404, got %d", rec.Code)
	}
}
