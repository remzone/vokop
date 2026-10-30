// SPDX-License-Identifier: GPL-3.0-or-later
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

var statusMu sync.Mutex
var statusPath string
var captchaStatusLatched bool

// This is local supervisory data only. Never write API responses or credentials.
func writeTransportStatus(state string) error {
	statusMu.Lock()
	defer statusMu.Unlock()
	switch state {
	case "starting", "ready", "captcha_required", "error":
	default:
		return fmt.Errorf("invalid transport status")
	}
	if state == "captcha_required" {
		captchaStatusLatched = true
	}
	if captchaStatusLatched {
		state = "captcha_required"
	}
	if statusPath == "" {
		return nil
	}
	f, err := os.CreateTemp(filepath.Dir(statusPath), ".vk-status-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if err = f.Chmod(0600); err == nil {
		_, err = f.WriteString(state + "\n")
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), statusPath)
}
