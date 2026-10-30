//go:build linux

package main

import (
	"context"
	"net"
	"sync/atomic"
	"syscall"
	"time"
)

const bypassMark = 0x08000000

func markedControl(network, address string, c syscall.RawConn) error {
	var sockErr error
	e := c.Control(func(fd uintptr) {
		sockErr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_MARK, bypassMark)
	})
	if e != nil {
		return e
	}
	return sockErr
}

var resolverIndex atomic.Uint32
var bootstrapResolvers = []string{"77.88.8.8:53", "77.88.8.1:53", "1.1.1.1:53"}

func nextBootstrapResolver() string {
	return bootstrapResolvers[(resolverIndex.Add(1)-1)%uint32(len(bootstrapResolvers))]
}
func directDialer() *net.Dialer {
	resolver := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{Timeout: 10 * time.Second, Control: markedControl}
		// Never use resolv.conf: dnsmasq may forward to stopped sing-box or return FakeIP.
		return d.DialContext(ctx, network, nextBootstrapResolver())
	}}
	return &net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second, Control: markedControl, Resolver: resolver}
}
