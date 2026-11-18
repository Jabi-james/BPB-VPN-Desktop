//go:build windows

package main

import (
	"fmt"
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
	proxySnapshot = &systemProxySnapshot{
		enable: uint32(enable),
		server: readStringValue(k, "ProxyServer"),
		auto:   readStringValue(k, "AutoConfigURL"),
	}
	if err := k.SetStringValue("ProxyServer", address); err != nil {
		proxySnapshot = nil
		return err
	}
	if err := k.SetDWordValue("ProxyEnable", 1); err != nil {
		proxySnapshot = nil
		return err
	}
	notifyInternetSettings()
	return nil
}

// restoreSystemProxy puts the exact previous per-user proxy values back.
func restoreSystemProxy() error {
	if proxySnapshot == nil {
		return nil
	}
	s := proxySnapshot
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
	proxySnapshot = nil
	notifyInternetSettings()
	return nil
}
