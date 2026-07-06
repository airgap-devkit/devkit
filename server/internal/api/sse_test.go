package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// noFlushWriter is an http.ResponseWriter that is deliberately NOT an
// http.Flusher, so newSSE must reject it.
type noFlushWriter struct{ h http.Header }

func (n noFlushWriter) Header() http.Header       { return n.h }
func (noFlushWriter) Write(b []byte) (int, error) { return len(b), nil }

func (noFlushWriter) WriteHeader(int) {
	// No-op: the SSE rejection path is decided before any status code is
	// written, so this stub only exists to satisfy http.ResponseWriter.
}

func TestNewSSE(t *testing.T) {
	rec := httptest.NewRecorder()
	sse, ok := newSSE(rec)
	if !ok || sse == nil {
		t.Fatal("recorder should support SSE")
	}
	if ct := rec.Header().Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("content-type = %q", ct)
	}
	if _, ok := newSSE(noFlushWriter{h: http.Header{}}); ok {
		t.Error("a non-flusher writer must not support SSE")
	}
}

func TestSSESendAndDone(t *testing.T) {
	rec := httptest.NewRecorder()
	sse, _ := newSSE(rec)
	sse.Send("hello world\n")
	sse.Done("success")

	body := rec.Body.String()
	if !strings.Contains(body, "data: hello world\n\n") {
		t.Errorf("Send output missing: %q", body)
	}
	if !strings.Contains(body, "data: DONE:success\n\n") {
		t.Errorf("Done output missing: %q", body)
	}
}

func TestPipeWriterLineFraming(t *testing.T) {
	rec := httptest.NewRecorder()
	sse, _ := newSSE(rec)
	p := newPipe(sse)

	if _, err := p.Write([]byte("first line\nsecond line\n")); err != nil {
		t.Fatal(err)
	}
	// A pre-formatted "data: " line is passed through untouched.
	if _, err := p.Write([]byte("data: preformatted\n")); err != nil {
		t.Fatal(err)
	}

	body := rec.Body.String()
	for _, want := range []string{"data: first line\n\n", "data: second line\n\n", "data: preformatted\n\n"} {
		if !strings.Contains(body, want) {
			t.Errorf("pipe output missing %q in %q", want, body)
		}
	}
}
