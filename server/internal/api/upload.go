package api

import (
	"archive/zip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/tus/tusd/v2/pkg/filestore"
	"github.com/tus/tusd/v2/pkg/handler"
	"golang.org/x/exp/slog"

	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

// The package-upload transport supports arbitrarily large archives (multi-GB
// toolchains) via two intake paths that converge on finalizePackageZip:
//
//   1. Resumable chunked upload (tus protocol) for remote / team-server clients.
//      The archive is streamed to disk in chunks, survives dropped connections
//      and page reloads, and never buffers the whole file in RAM.
//   2. Import-from-disk for localhost, where the file already lives on the same
//      machine as the server and there is nothing to transfer over the network.

// uploadBasePath is the URL prefix the resumable handler is mounted at. tusd's
// router matches on the path with this prefix stripped, while its Location
// headers are rebuilt from the same value (set as BasePath below).
const uploadBasePath = "/packages/upload"

var uploadJanitorOnce sync.Once

// tusHandler builds the resumable-upload handler backed by an on-disk filestore.
// It returns nil (uploads disabled, logged) if the temp directory cannot be
// created so the rest of the server still starts.
func (s *Server) tusHandler() http.Handler {
	tmp := s.Config.UploadTempDir
	if err := os.MkdirAll(tmp, 0o750); err != nil {
		log.Printf("upload: cannot create temp dir %q, resumable upload disabled: %v", tmp, err)
		return nil
	}

	store := filestore.New(tmp)
	composer := handler.NewStoreComposer()
	store.UseIn(composer)

	h, err := handler.NewHandler(handler.Config{
		BasePath:                  uploadBasePath + "/",
		StoreComposer:             composer,
		MaxSize:                   s.Config.UploadMaxBytes,
		NotifyCompleteUploads:     false,
		PreFinishResponseCallback: s.onUploadFinish,
		// tusd emits its own request logs; the devkit has its own logging, so
		// discard tusd's to keep the console clean.
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	if err != nil {
		log.Printf("upload: tus handler init failed, resumable upload disabled: %v", err)
		return nil
	}

	uploadJanitorOnce.Do(s.startUploadJanitor)
	// tusd's router matches on the path with the mount prefix removed.
	return http.StripPrefix(uploadBasePath, h)
}

// onUploadFinish runs after the final chunk lands but before tusd replies to the
// client. It validates and installs the assembled archive, then removes the
// temp files. Returning an error surfaces the failure to the uploading client.
func (s *Server) onUploadFinish(hook handler.HookEvent) (handler.HTTPResponse, error) {
	zipPath := hook.Upload.Storage[filestore.StorageKeyPath]
	name := strings.TrimSpace(hook.Upload.MetaData["filename"])
	if name == "" {
		name = hook.Upload.ID + ".zip"
	}
	defer s.cleanupUpload(hook.Upload)

	if !strings.EqualFold(filepath.Ext(name), ".zip") {
		return handler.HTTPResponse{}, handler.NewError("ERR_NOT_ZIP", "only .zip packages are supported", http.StatusBadRequest)
	}

	toolID, err := s.finalizePackageZip(zipPath, name)
	if err != nil {
		return handler.HTTPResponse{}, handler.NewError("ERR_FINALIZE", err.Error(), http.StatusBadRequest)
	}
	return handler.HTTPResponse{
		StatusCode: http.StatusOK,
		Header:     handler.HTTPHeader{"X-Devkit-Tool-Id": toolID},
	}, nil
}

// cleanupUpload removes the assembled binary and its .info sidecar so abandoned
// or completed uploads do not accumulate on disk.
func (s *Server) cleanupUpload(info handler.FileInfo) {
	for _, key := range []string{filestore.StorageKeyPath, filestore.StorageKeyInfoPath} {
		if p := info.Storage[key]; p != "" {
			_ = os.Remove(p)
		}
	}
}

// startUploadJanitor periodically reaps temp upload files older than the
// configured TTL, reclaiming disk from uploads that were never completed.
func (s *Server) startUploadJanitor() {
	ttl := time.Duration(s.Config.UploadSessionTTLHours) * time.Hour
	if ttl <= 0 {
		return
	}
	go func() {
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			s.reapStaleUploads(ttl)
			<-ticker.C
		}
	}()
}

func (s *Server) reapStaleUploads(ttl time.Duration) {
	entries, err := os.ReadDir(s.Config.UploadTempDir)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-ttl)
	for _, e := range entries {
		info, err := e.Info()
		if err != nil || info.ModTime().After(cutoff) {
			continue
		}
		_ = os.Remove(filepath.Join(s.Config.UploadTempDir, e.Name()))
	}
}

// finalizePackageZip validates an on-disk .zip and installs it as a user
// package. It streams the archive with a ReaderAt (no full-file buffering),
// enforces the expansion and per-entry caps, extracts with path-traversal
// guards, writes a manifest, and reloads the tool list. Returns the tool ID.
func (s *Server) finalizePackageZip(zipPath, displayName string) (string, error) {
	f, err := os.Open(zipPath)
	if err != nil {
		return "", fmt.Errorf("cannot open upload: %w", err)
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return "", fmt.Errorf("cannot stat upload: %w", err)
	}

	zr, err := zip.NewReader(f, fi.Size())
	if err != nil {
		return "", fmt.Errorf("invalid zip: %w", err)
	}

	var totalUncompressed uint64
	for _, zf := range zr.File {
		totalUncompressed += zf.UncompressedSize64
	}
	if int64(totalUncompressed) > s.Config.ZipMaxUncompressed {
		return "", fmt.Errorf("zip expands to %d MB which exceeds the %d MB limit",
			totalUncompressed>>20, s.Config.ZipMaxUncompressed>>20)
	}

	base := displayName
	if strings.EqualFold(filepath.Ext(base), ".zip") {
		base = base[:len(base)-len(filepath.Ext(base))]
	}
	base = sanitizeDisplayName(filepath.Base(base))
	toolID := slugify(base)
	if toolID == "" {
		toolID = "user-package"
		base = "user-package"
	}

	destDir := filepath.Join(s.RepoRoot, userPackagesDir, toolID)
	if err := os.MkdirAll(destDir, 0o750); err != nil {
		return "", fmt.Errorf("cannot create package dir: %w", err)
	}

	if _, msg := extractZipTo(zr, destDir, s.Config.ZipMaxEntryBytes); msg != "" {
		return "", errors.New(msg)
	}

	uploadedBy := currentOSUsername()
	// Stored canonically; the UI re-renders it in the user's chosen style on read.
	uploadedAt := time.Now().UTC().Format(time.RFC3339)
	devkitJSON := filepath.Join(destDir, devkitJSONFile)
	// Generate a manifest and installer independently — a package may bundle one
	// but not the other. Manifest first so the setup step can honour its "setup"
	// field; sanitize between them to normalise the (possibly user-supplied) JSON.
	ensurePackageManifest(devkitJSON, toolID, base, uploadedBy, uploadedAt)
	sanitizePackageManifest(devkitJSON, toolID, uploadedBy, uploadedAt)
	ensurePackageSetup(destDir, devkitJSON, toolID, base)

	s.mu.Lock()
	if loaded, err := tools.Load(s.RepoRoot); err == nil {
		s.allTools = loaded
	}
	s.mu.Unlock()

	return toolID, nil
}

// handleUploadConfig exposes the upload limits so the browser client can size
// its chunks and validate before starting a multi-GB transfer.
func (s *Server) handleUploadConfig(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, map[string]any{
		"max_bytes":         s.Config.UploadMaxBytes,
		"chunk_size":        s.Config.UploadChunkSize,
		"allow_path_import": s.Config.AllowPathImport && isLoopback(r),
	})
}

// handlePackageImport installs a .zip that already exists on the server's local
// disk — the reliable path for multi-GB archives on a localhost install, where
// pushing the bytes through an HTTP body would be pure overhead. It is gated to
// loopback callers and to config.AllowPathImport so a networked team server
// cannot be coaxed into reading arbitrary local files.
func (s *Server) handlePackageImport(w http.ResponseWriter, r *http.Request) {
	if !s.Config.AllowPathImport || !isLoopback(r) {
		jsonErr(w, "import from path is only available on a localhost install", http.StatusForbidden)
		return
	}

	var body struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, errInvalidBody, http.StatusBadRequest)
		return
	}
	p := strings.TrimSpace(body.Path)
	if p == "" || !strings.EqualFold(filepath.Ext(p), ".zip") {
		jsonErr(w, "path must point to a .zip file", http.StatusBadRequest)
		return
	}
	fi, err := os.Stat(p)
	if err != nil || fi.IsDir() {
		jsonErr(w, "file not found: "+p, http.StatusBadRequest)
		return
	}
	if fi.Size() > s.Config.UploadMaxBytes {
		jsonErr(w, fmt.Sprintf("file is %d MB which exceeds the %d MB limit",
			fi.Size()>>20, s.Config.UploadMaxBytes>>20), http.StatusBadRequest)
		return
	}

	toolID, err := s.finalizePackageZip(p, filepath.Base(p))
	if err != nil {
		jsonErr(w, err.Error(), http.StatusBadRequest)
		return
	}
	jsonOK(w, map[string]any{
		"ok":      true,
		"id":      toolID,
		"message": fmt.Sprintf("Imported '%s' and registered tool '%s'", filepath.Base(p), toolID),
	})
}

// isLoopback reports whether the request originated from the local machine.
func isLoopback(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
