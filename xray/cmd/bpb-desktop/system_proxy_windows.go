//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/windows/registry"
)

const (
	internetOptionSettingsChanged = 39
	internetOptionRefresh         = 37
)

var (
	internetSetOption = syscall.NewLazyDLL("wininet.dll").NewProc("InternetSetOptionW")
	proxySnapshot    *systemProxySnapshot
)

type systemProxySnapshot struct {
	enable uint32
	server string
	auto   string
}

func proxySnapshotPath() (string, error) {
	root, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(root, "BPB")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	return filepath.Join(dir, "system-proxy.json"), nil
}

func saveProxySnapshot(s *systemProxySnapshot) error {
	path, err := proxySnapshotPath()
	if err != nil {
		return err
	}
	data, err := json.Marshal(s)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func loadProxySnapshot() (*systemProxySnapshot, error) {
	path, err := proxySnapshotPath()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var s systemProxySnapshot
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("read saved Windows proxy settings: %w", err)
	}
	return &s, nil
}

func notifyInternetSettings() {
	internetSetOption.Call(0, internetOptionSettingsChanged, 0, 0)
	internetSetOption.Call(0, internetOptionRefresh, 0, 0)
}

func readStringValue(k registry.Key, name string) string {
	v, _, err := k.GetStringValue(name)
	if err != nil {
		return ""
	}
	return v
}

// applySystemProxy stores the user's previous settings before enabling BPB's local proxy.
// It does not require administrator privileges and never overwrites the saved snapshot.
func applySystemProxy(address string) error {
	if proxySnapshot != nil {
		return fmt.Errorf("system proxy is already managed by BPB")
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Internet Settings`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()

	enable, _, err := k.GetIntegerValue("ProxyEnable")
	if err != nil && err != registry.ErrNotExist {
		return err
	}
	snapshot := &systemProxySnapshot{
		enable: uint32(enable),
		server: readStringValue(k, "ProxyServer"),
		auto:   readStringValue(k, "AutoConfigURL"),
	}
	if err := saveProxySnapshot(snapshot); err != nil {
		return fmt.Errorf("save previous Windows proxy settings: %w", err)
	}
	proxySnapshot = snapshot
	if err := k.SetStringValue("ProxyServer", address); err != nil {
		_ = restoreSystemProxy()
		return err
	}
	if err := k.SetDWordValue("ProxyEnable", 1); err != nil {
		_ = restoreSystemProxy()
		return err
	}
	notifyInternetSettings()
	return nil
}

// restoreSystemProxy puts the exact previous per-user proxy values back.
func restoreSystemProxy() error {
	s := proxySnapshot
	if s == nil {
		var err error
		s, err = loadProxySnapshot()
		if err != nil || s == nil {
			return err
		}
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Internet Settings`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if s.server == "" {
		_ = k.DeleteValue("ProxyServer")
	} else if err := k.SetStringValue("ProxyServer", s.server); err != nil {
		return err
	}
	if err := k.SetDWordValue("ProxyEnable", s.enable); err != nil {
		return err
	}
	if s.auto == "" {
		_ = k.DeleteValue("AutoConfigURL")
	} else if err := k.SetStringValue("AutoConfigURL", s.auto); err != nil {
		return err
	}
	path, err := proxySnapshotPath()
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	proxySnapshot = nil
	notifyInternetSettings()
	return nil
}
