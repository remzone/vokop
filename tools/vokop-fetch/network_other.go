//go:build !linux

package main

import (
	"errors"
	"net"
	"syscall"
)

func directDialer() *net.Dialer {
	return &net.Dialer{Control: func(string, string, syscall.RawConn) error { return errors.New("linux required") }}
}
