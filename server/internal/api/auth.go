package api

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

const sessionMaxAge = 12 * 3600 // seconds

func loadOrCreateToken(repoRoot string) (string, error) {
	tokenPath := filepath.Join(repoRoot, ".devkit-token")
	if data, err := os.ReadFile(tokenPath); err == nil {
		if t := strings.TrimSpace(string(data)); len(t) == 64 {
			return t, nil
		}
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	_ = os.WriteFile(tokenPath, []byte(token+"\n"), 0o600)
	return token, nil
}

// tokenMatches compares the presented token to the server token in constant
// time so the comparison does not leak how many leading bytes matched.
func (s *Server) tokenMatches(got string) bool {
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) == 1
}

func (s *Server) tokenAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/health" || p == "/auth/bootstrap" || strings.HasPrefix(p, "/static/") {
			next.ServeHTTP(w, r)
			return
		}

		// The token is accepted only from the request header or the session
		// cookie. It is deliberately not read from the query string, which would
		// otherwise persist in browser history, referrer headers and access logs.
		got := r.Header.Get("X-DevKit-Token")
		if got == "" {
			if c, err := r.Cookie("devkit_token"); err == nil {
				got = c.Value
			}
		}

		if !s.tokenMatches(got) {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// safeNext returns a local redirect target rebuilt from a parsed path. Anything
// with a scheme or host (including protocol-relative "//host" and backslash
// "/\\host" forms a browser treats as absolute) collapses to "/".
func safeNext(next string) string {
	if next == "" {
		return "/"
	}
	u, err := url.Parse(next)
	if err != nil || u.IsAbs() || u.Host != "" ||
		!strings.HasPrefix(u.Path, "/") || strings.HasPrefix(u.Path, "//") {
		return "/"
	}
	return u.Path
}

func (s *Server) handleAuthBootstrap(w http.ResponseWriter, r *http.Request) {
	// The one-time hand-off token still arrives in the query string here; make
	// sure it cannot leak onward through the referrer header.
	w.Header().Set("Referrer-Policy", "no-referrer")

	if !s.tokenMatches(r.URL.Query().Get("devkit_token")) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	next := safeNext(r.URL.Query().Get("next"))
	http.SetCookie(w, &http.Cookie{
		Name:     "devkit_token",
		Value:    s.token,
		Path:     "/",
		HttpOnly: true,
		Secure:   r.TLS != nil,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   sessionMaxAge,
	})
	http.Redirect(w, r, next, http.StatusFound)
}
