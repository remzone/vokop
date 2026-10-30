//go:build linux

package main

import (
	"errors"
	"testing"
)

type refusedRawConn struct{ called bool }

func (r *refusedRawConn) Control(f func(uintptr)) error {
	r.called = true
	return errors.New("socket unavailable")
}
func (r *refusedRawConn) Read(f func(uintptr) bool) error  { return errors.New("unused") }
func (r *refusedRawConn) Write(f func(uintptr) bool) error { return errors.New("unused") }

func TestWANControlPreservesLoopback(t *testing.T) {
	for _, address := range []string{"127.0.0.1:9000", "[::1]:9000"} {
		raw := &refusedRawConn{}
		if err := wanSocketControl("tcp", address, raw); err != nil {
			t.Fatal(err)
		}
		if raw.called {
			t.Fatalf("loopback %s unexpectedly marked", address)
		}
	}
}

func TestWANControlFailsClosed(t *testing.T) {
	raw := &refusedRawConn{}
	if err := wanSocketControl("udp", "192.0.2.1:3478", raw); err == nil {
		t.Fatal("unmarked socket accepted")
	}
	if !raw.called {
		t.Fatal("socket control not attempted")
	}
}

func TestWANResolverAndDialerAreMarked(t *testing.T) {
	d := getCustomNetDialer()
	if d.Control == nil || d.Resolver == nil || !d.Resolver.PreferGo || d.Resolver.Dial == nil {
		t.Fatal("dialer can bypass marked socket control")
	}
	if vokopWANMark != 0x08000000 {
		t.Fatal("Forkop/Vokop outbound mark mismatch")
	}
}
