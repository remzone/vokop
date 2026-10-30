package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStatusFileEnumModeAndCaptchaLatch(t *testing.T) {
	previousPath, previousLatch := statusPath, captchaStatusLatched
	defer func() { statusPath, captchaStatusLatched = previousPath, previousLatch }()
	statusPath = filepath.Join(t.TempDir(), "profile.status")
	captchaStatusLatched = false
	if err := writeTransportStatus("starting"); err != nil {
		t.Fatal(err)
	}
	if err := writeTransportStatus("captcha_required"); err != nil {
		t.Fatal(err)
	}
	if err := writeTransportStatus("ready"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(statusPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "captcha_required\n" {
		t.Fatalf("unexpected status: %q", data)
	}
	info, err := os.Stat(statusPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("status mode: %v", info.Mode())
	}
	if writeTransportStatus("token=secret") == nil {
		t.Fatal("arbitrary status accepted")
	}
}
