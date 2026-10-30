//go:build linux

// SPDX-License-Identifier: GPL-3.0-or-later
// Vokop: every transport/credential/bootstrap socket must bypass the tunnel.
package main

import (
	"context"
	"fmt"
	"net"
	"syscall"
	"time"
)

const vokopWANMark = 0x08000000

type contextDialer interface {
	DialContext(context.Context, string, string) (net.Conn, error)
}

// A failed setsockopt aborts the socket, rather than silently recursing into Vokop.
// Root or CAP_NET_ADMIN/CAP_NET_RAW (kernel dependent) is required on OpenWrt.
func wanSocketControl(network, address string, raw syscall.RawConn) error {
	host, _, _ := net.SplitHostPort(address)
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		return nil
	}
	var sockErr error
	if err := raw.Control(func(fd uintptr) {
		sockErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_MARK, vokopWANMark)
	}); err != nil {
		return fmt.Errorf("WAN socket control: %w", err)
	}
	if sockErr != nil {
		return fmt.Errorf("WAN mark required: %w", sockErr)
	}
	return nil
}

func wanResolver() *net.Resolver {
	return &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{Timeout: 5 * time.Second, Control: wanSocketControl}
		// Direct IP resolvers avoid FakeIP and router DNS recursion. Keep TCP for
		// truncated replies; unlike upstream this does not force all queries UDP.
		var last error
		for _, server := range []string{"77.88.8.8:53", "77.88.8.1:53", "1.1.1.1:53"} {
			c, err := d.DialContext(ctx, network, server)
			if err == nil {
				return c, nil
			}
			last = err
		}
		return nil, last
	}}
}

func init() {
	// Covers net.ResolveUDPAddr/ResolveTCPAddr used for peer and dynamic relays.
	net.DefaultResolver = wanResolver()
}

func markedDialUDP(network string, local, remote *net.UDPAddr) (*net.UDPConn, error) {
	d := getCustomNetDialer()
	if local != nil {
		d.LocalAddr = local
	}
	c, err := d.Dial(network, remote.String())
	if err != nil {
		return nil, err
	}
	return c.(*net.UDPConn), nil
}

func markedDialTCP(network string, local, remote *net.TCPAddr) (*net.TCPConn, error) {
	d := getCustomNetDialer()
	if local != nil {
		d.LocalAddr = local
	}
	c, err := d.Dial(network, remote.String())
	if err != nil {
		return nil, err
	}
	return c.(*net.TCPConn), nil
}

func markedListenPacket(network, address string) (net.PacketConn, error) {
	lc := net.ListenConfig{Control: wanSocketControl}
	return lc.ListenPacket(context.Background(), network, address)
}
func markedListenUDP(network string, local *net.UDPAddr) (*net.UDPConn, error) {
	address := ":0"
	if local != nil {
		address = local.String()
	}
	c, err := markedListenPacket(network, address)
	if err != nil {
		return nil, err
	}
	return c.(*net.UDPConn), nil
}
func markedListenTCP(network string, local *net.TCPAddr) (*net.TCPListener, error) {
	address := ":0"
	if local != nil {
		address = local.String()
	}
	lc := net.ListenConfig{Control: wanSocketControl}
	c, err := lc.Listen(context.Background(), network, address)
	if err != nil {
		return nil, err
	}
	return c.(*net.TCPListener), nil
}
