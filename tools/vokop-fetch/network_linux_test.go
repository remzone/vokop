//go:build linux

package main

import (
	"testing"
)

func TestBypassMark(t *testing.T) {
	if bypassMark != 0x08000000 {
		t.Fatal("mark differs from Forkop routing exemption")
	}
	d := directDialer()
	if d.Control == nil || d.Resolver == nil || d.Resolver.Dial == nil || !d.Resolver.PreferGo {
		t.Fatal("DNS or connection may bypass marked dialer")
	}
}

func TestBootstrapDoesNotUseLocalResolver(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < len(bootstrapResolvers); i++ {
		a := nextBootstrapResolver()
		if a == "127.0.0.1:53" || a == "127.0.0.42:53" || a == "" {
			t.Fatal("local/FakeIP bootstrap")
		}
		seen[a] = true
	}
	if len(seen) != len(bootstrapResolvers) {
		t.Fatal("resolver rotation")
	}
}
