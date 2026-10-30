// Vokop HTTPS fetcher: strict TLS, no redirects, marked sockets including DNS.
// SPDX-License-Identifier: GPL-2.0-or-later
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const maxResponse = 4 * 1024 * 1024

var allowedHeaders = map[string]bool{"user-agent": true, "x-hwid": true, "accept-language": true}

type headers []string

func (h *headers) String() string     { return "headers" }
func (h *headers) Set(s string) error { *h = append(*h, s); return nil }

type options struct {
	URL, URLFile, Output, HeadersFile, TokenFile, BodyFile, Method, Proxy string
	Headers                                                               headers
}

func parseURL(s string) (*url.URL, error) {
	u, e := url.Parse(s)
	if e != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.Fragment != "" || len(s) > 8192 || strings.ContainsAny(s, "\r\n\x00") {
		return nil, errors.New("invalid HTTPS URL")
	}
	return u, nil
}
func secureRead(path string, limit int64) ([]byte, error) {
	f, e := os.Open(path)
	if e != nil {
		return nil, e
	}
	defer f.Close()
	st, e := f.Stat()
	if e != nil || !st.Mode().IsRegular() || st.Mode().Perm()&0077 != 0 {
		return nil, errors.New("private regular file required")
	}
	b, e := io.ReadAll(io.LimitReader(f, limit+1))
	if e != nil || int64(len(b)) > limit {
		return nil, errors.New("file too large")
	}
	return b, nil
}
func atomicWrite(path string, data []byte) error {
	if path == "" {
		return errors.New("output path required")
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".vokop-fetch-*")
	if e != nil {
		return e
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if e = f.Chmod(0600); e == nil {
		_, e = f.Write(data)
	}
	if e == nil {
		e = f.Sync()
	}
	closeErr := f.Close()
	if e == nil {
		e = closeErr
	}
	if e != nil {
		return e
	}
	return os.Rename(tmp, path)
}
func client(proxy string) (*http.Client, error) {
	d := directDialer()
	tr := &http.Transport{Proxy: nil, DialContext: d.DialContext, TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12}}
	if proxy != "" {
		u, e := url.Parse(proxy)
		if e != nil || u.Scheme != "http" || u.User != nil || u.Path != "" || u.RawQuery != "" || u.Fragment != "" || net.ParseIP(u.Hostname()) == nil || !net.ParseIP(u.Hostname()).IsLoopback() {
			return nil, errors.New("only loopback HTTP proxy allowed")
		}
		tr.Proxy = http.ProxyURL(u)
	}
	return &http.Client{Transport: tr, Timeout: 30 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("redirect refused") }}, nil
}
func fetch(ctx context.Context, o options, h *http.Client) error {
	if o.URLFile != "" {
		if o.URL != "" {
			return errors.New("ambiguous URL")
		}
		b, e := secureRead(o.URLFile, 8192)
		if e != nil {
			return errors.New("invalid URL file")
		}
		o.URL = strings.TrimSpace(string(b))
	}
	u, e := parseURL(o.URL)
	if e != nil {
		return e
	}
	if o.Method != "GET" && o.Method != "POST" {
		return errors.New("unsupported method")
	}
	var body []byte
	if o.BodyFile != "" {
		body, e = secureRead(o.BodyFile, 256*1024)
		if e != nil {
			return errors.New("invalid body file")
		}
	}
	req, e := http.NewRequestWithContext(ctx, o.Method, u.String(), bytes.NewReader(body))
	if e != nil {
		return errors.New("invalid request")
	}
	req.Header.Set("User-Agent", "Vokop/1")
	req.Header.Set("Accept", "application/json, text/plain;q=0.9")
	if o.Method == "POST" {
		req.Header.Set("Content-Type", "application/json")
	}
	for _, s := range o.Headers {
		key, val, ok := strings.Cut(s, ":")
		key = strings.TrimSpace(key)
		val = strings.TrimSpace(val)
		if !ok || !allowedHeaders[strings.ToLower(key)] || strings.ContainsAny(val, "\r\n\x00") || len(val) > 1024 {
			return errors.New("invalid header")
		}
		req.Header.Set(key, val)
	}
	if o.TokenFile != "" {
		b, e := secureRead(o.TokenFile, 4096)
		if e != nil {
			return errors.New("invalid token file")
		}
		token := strings.TrimSpace(string(b))
		if len(token) < 16 || strings.ContainsAny(token, "\r\n\x00") {
			return errors.New("invalid token")
		}
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, e := h.Do(req)
	if e != nil {
		return errors.New("HTTPS request failed")
	}
	defer res.Body.Close()
	if res.StatusCode != 200 && res.StatusCode != 204 {
		return errors.New("HTTP request rejected")
	}
	b, e := io.ReadAll(io.LimitReader(res.Body, maxResponse+1))
	if e != nil || len(b) > maxResponse {
		return errors.New("response too large or unreadable")
	}
	if o.HeadersFile != "" {
		var header bytes.Buffer
		for _, key := range []string{"Content-Type", "Subscription-Userinfo", "Profile-Title", "Profile-Update-Interval", "Profile-Web-Page-Url", "Support-Url"} {
			if val := res.Header.Get(key); val != "" && !strings.ContainsAny(val, "\r\n\x00") {
				fmt.Fprintf(&header, "%s: %s\r\n", key, val)
			}
		}
		if e = atomicWrite(o.HeadersFile, header.Bytes()); e != nil {
			return errors.New("headers write failed")
		}
	}
	if e = atomicWrite(o.Output, b); e != nil {
		return errors.New("response write failed")
	}
	return nil
}
func main() {
	var o options
	flag.StringVar(&o.URL, "url", "", "HTTPS URL")
	flag.StringVar(&o.URLFile, "url-file", "", "private HTTPS URL file")
	flag.StringVar(&o.Output, "output", "", "private response file")
	flag.StringVar(&o.HeadersFile, "headers-output", "", "response metadata file")
	flag.StringVar(&o.TokenFile, "token-file", "", "private bearer token file")
	flag.StringVar(&o.BodyFile, "body-file", "", "private JSON request body")
	flag.StringVar(&o.Method, "method", "GET", "GET or POST")
	flag.StringVar(&o.Proxy, "proxy", "", "optional local HTTP proxy")
	flag.Var(&o.Headers, "header", "allowed compatibility header")
	flag.Parse()
	h, e := client(o.Proxy)
	if e == nil {
		e = fetch(context.Background(), o, h)
	}
	if e != nil {
		fmt.Fprintln(os.Stderr, "VOKOP_FETCH_FAILED")
		os.Exit(1)
	}
}
