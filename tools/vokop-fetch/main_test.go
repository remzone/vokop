package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestURLs(t *testing.T) {
	for _, s := range []string{"http://example.com", "https://u:p@example.com", "file:///etc/passwd", "https://example.com/#fragment", "https://example.com/\n"} {
		if _, e := parseURL(s); e == nil {
			t.Fatalf("accepted %q", s)
		}
	}
	if _, e := parseURL("https://example.com/sub/token"); e != nil {
		t.Fatal(e)
	}
}
func TestFetch(t *testing.T) {
	s := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Device-Model") != "" || r.Header.Get("X-HWID") != "" {
			t.Error("unsolicited hardware")
		}
		w.Write([]byte(`{"ok":true}`))
	}))
	defer s.Close()
	p := filepath.Join(t.TempDir(), "out")
	if e := fetch(context.Background(), options{URL: s.URL, Output: p, Method: "GET"}, s.Client()); e != nil {
		t.Fatal(e)
	}
	st, _ := os.Stat(p)
	if st.Mode().Perm() != 0600 {
		t.Fatal("permissions")
	}
}
func TestTokenFile(t *testing.T) {
	d := t.TempDir()
	p := filepath.Join(d, "token")
	os.WriteFile(p, []byte("secret-secret-secret"), 0644)
	if _, e := secureRead(p, 4096); e == nil {
		t.Fatal("accepted public token")
	}
}
func TestOversizeAndHeaders(t *testing.T) {
	s := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(strings.Repeat("x", maxResponse+1))) }))
	defer s.Close()
	o := options{URL: s.URL, Output: filepath.Join(t.TempDir(), "out"), Method: "GET"}
	if e := fetch(context.Background(), o, s.Client()); e == nil {
		t.Fatal("accepted oversized")
	}
	o.Headers = []string{"X-HWID: x\r\nInjected: yes"}
	if e := fetch(context.Background(), o, s.Client()); e == nil {
		t.Fatal("header injection")
	}
}
func TestProxy(t *testing.T) {
	for _, s := range []string{"http://evil.example:1234", "http://user:pw@127.0.0.1:1", "http://127.0.0.1:1/?x=y"} {
		if _, e := client(s); e == nil {
			t.Fatal("accepted proxy", s)
		}
	}
}
func TestRedirectAndOldFile(t *testing.T) {
	var reached bool
	target := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { reached = true; w.Write([]byte("leak")) }))
	defer target.Close()
	source := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, http.StatusFound) }))
	defer source.Close()
	h, _ := client("")
	h.Transport = source.Client().Transport
	p := filepath.Join(t.TempDir(), "out")
	os.WriteFile(p, []byte("last-good"), 0600)
	if e := fetch(context.Background(), options{URL: source.URL, Output: p, Method: "GET"}, h); e == nil {
		t.Fatal("redirect accepted")
	}
	b, _ := os.ReadFile(p)
	if string(b) != "last-good" || reached {
		t.Fatal("unsafe redirect/write")
	}
}
