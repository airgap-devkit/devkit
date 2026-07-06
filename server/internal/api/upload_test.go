package api

import (
	"archive/zip"
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nimzshafie/airgap-devkit/server/internal/config"
)

// Test-only shared literals. Filename literals (devkit.json, setup.sh,
// user-packages) reuse the production constants so the tests track the exact
// names the server writes.
const (
	hdrTusResumable = "Tus-Resumable"
	hdrUploadOffset = "Upload-Offset"
	tusVersion      = "1.0.0"
	binPayloadPath  = "bin/payload"
)

// newTestServer builds a minimal Server rooted at a temp dir with upload
// defaults applied, suitable for exercising the package-intake paths.
func newTestServer(t *testing.T) *Server {
	t.Helper()
	dir := t.TempDir()
	return &Server{RepoRoot: dir, Config: config.Load(dir)}
}

// zipBytes returns a valid .zip archive containing a single named entry.
func zipBytes(t *testing.T, name, body string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create(name)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte(body)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func meta(kv map[string]string) string {
	parts := make([]string, 0, len(kv))
	for k, v := range kv {
		parts = append(parts, k+" "+base64.StdEncoding.EncodeToString([]byte(v)))
	}
	return strings.Join(parts, ",")
}

// mustExist fails the test with msg when path is not present on disk.
func mustExist(t *testing.T, path, msg string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatal(msg)
	}
}

// TestResumableUploadRoundTrip drives the tus handler through a create, an
// interrupted first chunk, a HEAD offset check (the resume signal), and a
// final chunk that finalises the package.
func TestResumableUploadRoundTrip(t *testing.T) {
	s := newTestServer(t)
	h := s.tusHandler()
	if h == nil {
		t.Fatal("tusHandler returned nil")
	}

	archive := zipBytes(t, "hello.txt", "hello world payload")

	// 1. Create the upload.
	createReq := httptest.NewRequest(http.MethodPost, "/packages/upload/", nil)
	createReq.Header.Set(hdrTusResumable, tusVersion)
	createReq.Header.Set("Upload-Length", itoa(len(archive)))
	createReq.Header.Set("Upload-Metadata", meta(map[string]string{"filename": "My Tool.zip"}))
	createRec := httptest.NewRecorder()
	h.ServeHTTP(createRec, createReq)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create: want 201, got %d (%s)", createRec.Code, createRec.Body.String())
	}
	loc := createRec.Header().Get("Location")
	if loc == "" {
		t.Fatal("create: missing Location header")
	}
	uploadPath := "/packages/upload/" + loc[strings.LastIndex(loc, "/")+1:]

	// 2. Send only the first half — simulating a dropped connection.
	half := len(archive) / 2
	patch1 := httptest.NewRequest(http.MethodPatch, uploadPath, bytes.NewReader(archive[:half]))
	patch1.Header.Set(hdrTusResumable, tusVersion)
	patch1.Header.Set(hdrUploadOffset, "0")
	patch1.Header.Set("Content-Type", "application/offset+octet-stream")
	patch1Rec := httptest.NewRecorder()
	h.ServeHTTP(patch1Rec, patch1)
	if patch1Rec.Code != http.StatusNoContent {
		t.Fatalf("patch1: want 204, got %d (%s)", patch1Rec.Code, patch1Rec.Body.String())
	}

	// 3. HEAD to discover the stored offset — this is what lets the client resume.
	headReq := httptest.NewRequest(http.MethodHead, uploadPath, nil)
	headReq.Header.Set(hdrTusResumable, tusVersion)
	headRec := httptest.NewRecorder()
	h.ServeHTTP(headRec, headReq)
	if got := headRec.Header().Get(hdrUploadOffset); got != itoa(half) {
		t.Fatalf("resume offset: want %d, got %q", half, got)
	}

	// 4. Send the remainder from the resumed offset; this finalises the package.
	patch2 := httptest.NewRequest(http.MethodPatch, uploadPath, bytes.NewReader(archive[half:]))
	patch2.Header.Set(hdrTusResumable, tusVersion)
	patch2.Header.Set(hdrUploadOffset, itoa(half))
	patch2.Header.Set("Content-Type", "application/offset+octet-stream")
	patch2Rec := httptest.NewRecorder()
	h.ServeHTTP(patch2Rec, patch2)
	if patch2Rec.Code >= 300 {
		t.Fatalf("patch2: want success, got %d (%s)", patch2Rec.Code, patch2Rec.Body.String())
	}

	// The package must now be registered under a slug derived from the filename.
	dest := filepath.Join(s.RepoRoot, userPackagesDir, "my-tool")
	if _, err := os.Stat(filepath.Join(dest, "hello.txt")); err != nil {
		t.Fatalf("extracted payload missing: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dest, devkitJSONFile)); err != nil {
		t.Fatalf("generated manifest missing: %v", err)
	}

	// tus temp files must be cleaned up on finalise.
	entries, _ := os.ReadDir(s.Config.UploadTempDir)
	if len(entries) != 0 {
		t.Fatalf("upload temp dir not cleaned, has %d entries", len(entries))
	}
}

func TestImportFromPathLoopbackOnly(t *testing.T) {
	s := newTestServer(t)
	s.Config.AllowPathImport = true

	archive := zipBytes(t, "bin/tool", "payload")
	zipPath := filepath.Join(t.TempDir(), "Imported Tool.zip")
	if err := os.WriteFile(zipPath, archive, 0o600); err != nil {
		t.Fatal(err)
	}

	body, _ := json.Marshal(map[string]string{"path": zipPath})

	// Non-loopback caller is rejected.
	remoteReq := httptest.NewRequest(http.MethodPost, "/packages/import", bytes.NewReader(body))
	remoteReq.RemoteAddr = "203.0.113.5:4444"
	remoteRec := httptest.NewRecorder()
	s.handlePackageImport(remoteRec, remoteReq)
	if remoteRec.Code != http.StatusForbidden {
		t.Fatalf("remote import: want 403, got %d", remoteRec.Code)
	}

	// Loopback caller succeeds.
	localReq := httptest.NewRequest(http.MethodPost, "/packages/import", bytes.NewReader(body))
	localReq.RemoteAddr = "127.0.0.1:5555"
	localRec := httptest.NewRecorder()
	s.handlePackageImport(localRec, localReq)
	if localRec.Code != http.StatusOK {
		t.Fatalf("local import: want 200, got %d (%s)", localRec.Code, localRec.Body.String())
	}
	if _, err := os.Stat(filepath.Join(s.RepoRoot, userPackagesDir, "imported-tool", "bin", "tool")); err != nil {
		t.Fatalf("imported payload missing: %v", err)
	}
}

// zipFrom builds a .zip whose entries are the given name→content map.
func zipFrom(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range files {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// installFromZip writes a zip to disk and runs it through finalize, returning
// the package directory.
func installFromZip(t *testing.T, s *Server, name string, files map[string]string) string {
	t.Helper()
	zp := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(zp, zipFrom(t, files), 0o600); err != nil {
		t.Fatal(err)
	}
	id, err := s.finalizePackageZip(zp, name)
	if err != nil {
		t.Fatalf("finalize %s: %v", name, err)
	}
	return filepath.Join(s.RepoRoot, userPackagesDir, id)
}

func mustRead(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}

// TestManifestAndSetupGeneration verifies the "auto-generated if not included"
// promise holds in every combination, and that bundled files are never
// clobbered.
func TestManifestAndSetupGeneration(t *testing.T) {
	t.Run("neither included generates both", func(t *testing.T) {
		s := newTestServer(t)
		dir := installFromZip(t, s, "Alpha.zip", map[string]string{binPayloadPath: "x"})
		mustExist(t, filepath.Join(dir, devkitJSONFile), "devkit.json not generated")
		mustExist(t, filepath.Join(dir, setupScriptName), "setup.sh not generated")
	})

	t.Run("manifest included, setup generated", func(t *testing.T) {
		s := newTestServer(t)
		manifest := `{"id":"x","name":"Beta","version":"9.9","setup":"setup.sh","description":"KEEPME"}`
		dir := installFromZip(t, s, "Beta.zip", map[string]string{
			devkitJSONFile: manifest,
			binPayloadPath: "x",
		})
		// The user's manifest must survive (description preserved).
		if got := mustRead(t, filepath.Join(dir, devkitJSONFile)); !strings.Contains(got, "KEEPME") {
			t.Fatalf("provided manifest was clobbered: %s", got)
		}
		// setup.sh must have been generated even though the manifest was present.
		mustExist(t, filepath.Join(dir, setupScriptName), "setup.sh not generated alongside a provided manifest")
	})

	t.Run("setup included, manifest generated and setup preserved", func(t *testing.T) {
		s := newTestServer(t)
		customSetup := "#!/usr/bin/env bash\necho CUSTOM_INSTALLER\n"
		dir := installFromZip(t, s, "Gamma.zip", map[string]string{
			setupScriptName: customSetup,
			binPayloadPath:  "x",
		})
		mustExist(t, filepath.Join(dir, devkitJSONFile), "devkit.json not generated alongside a provided setup.sh")
		// The user's installer must not be overwritten.
		if got := mustRead(t, filepath.Join(dir, setupScriptName)); got != customSetup {
			t.Fatalf("provided setup.sh was overwritten:\n%s", got)
		}
	})

	t.Run("malformed manifest is replaced so package still registers", func(t *testing.T) {
		s := newTestServer(t)
		dir := installFromZip(t, s, "Delta.zip", map[string]string{
			devkitJSONFile: "{ this is not valid json",
			binPayloadPath: "x",
		})
		var meta map[string]any
		if err := json.Unmarshal([]byte(mustRead(t, filepath.Join(dir, devkitJSONFile))), &meta); err != nil {
			t.Fatalf("malformed manifest was not replaced with valid JSON: %v", err)
		}
		if meta["id"] != "delta" {
			t.Fatalf("regenerated manifest has wrong id: %v", meta["id"])
		}
		mustExist(t, filepath.Join(dir, setupScriptName), "setup.sh not generated for a malformed-manifest package")
	})
}

// itoa avoids pulling strconv into multiple call sites for tiny ints.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
