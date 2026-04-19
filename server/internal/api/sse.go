package api

import (
	"fmt"
	"io"
	"net/http"
	"strings"
)

type sseWriter struct {
	w       http.ResponseWriter
	flusher http.Flusher
}

func newSSE(w http.ResponseWriter) (*sseWriter, bool) {
	f, ok := w.(http.Flusher)
	if !ok {
		return nil, false
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	return &sseWriter{w: w, flusher: f}, true
}

func (s *sseWriter) Send(line string) {
	line = strings.TrimRight(line, "\r\n")
	fmt.Fprintf(s.w, "data: %s\n\n", line)
	s.flusher.Flush()
}

func (s *sseWriter) Done(status string) {
	fmt.Fprintf(s.w, "data: DONE:%s\n\n", status)
	s.flusher.Flush()
}

// pipeWriter adapts sseWriter to io.Writer so exec output can be streamed line-by-line.
type pipeWriter struct {
	sse *sseWriter
	buf strings.Builder
}

func newPipe(sse *sseWriter) io.Writer {
	return &pipeWriter{sse: sse}
}

func (p *pipeWriter) Write(b []byte) (int, error) {
	p.buf.Write(b)
	s := p.buf.String()
	for {
		idx := strings.IndexAny(s, "\r\n")
		if idx < 0 {
			break
		}
		line := s[:idx]
		s = s[idx+1:]
		if strings.HasPrefix(line, "data: ") {
			// already formatted (from installer.go header line)
			fmt.Fprintf(p.sse.w, "%s\n\n", line)
			p.sse.flusher.Flush()
		} else if line != "" {
			p.sse.Send(line)
		}
	}
	p.buf.Reset()
	p.buf.WriteString(s)
	return len(b), nil
}
