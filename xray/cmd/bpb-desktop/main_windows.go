//go:build windows

// bpb-desktop is the Windows process host for BPB's existing Xray configuration.
// It has no Firefox VPN integration. Xray-core owns the Wintun adapter and route lifecycle.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"path/filepath"
	"sync"

	"bpb/xray"
)

type request struct {
	Command string `json:"command"`
	Config  string `json:"config,omitempty"`
	Mode    string `json:"mode,omitempty"`
	DNS     string `json:"dns,omitempty"`
	VerifyConnection bool `json:"verifyConnection,omitempty"`
	BrowserDialer bool `json:"browserDialer,omitempty"`
	Exit string `json:"exit,omitempty"`
	ExitDirect bool `json:"exitDirect,omitempty"`
	ExitRegion string `json:"exitRegion,omitempty"`
	PsiphonConfig string `json:"psiphonConfig,omitempty"`
	TorBridge string `json:"torBridge,omitempty"`
	TorCustomBridges []string `json:"torCustomBridges,omitempty"`
}

type response struct {
	OK      bool   `json:"ok"`
	Event   string `json:"event,omitempty"`
	Detail  string `json:"detail,omitempty"`
	Error   string `json:"error,omitempty"`
	Running bool   `json:"running,omitempty"`
	Delay   int64  `json:"delay,omitempty"`
	Traffic string `json:"traffic,omitempty"`
	Xray    string `json:"xray,omitempty"`
	DNS     string `json:"dns,omitempty"`
	Psiphon string `json:"psiphon,omitempty"`
	Tor     string `json:"tor,omitempty"`
}

func startController(controller *xray.Controller, req request) error {
	address := ""
	if req.BrowserDialer {
		address = "127.0.0.1:10832"
	}
	xray.SetBrowserDialer(address)
	if err := controller.Start(req.Config, 0); err != nil {
		xray.SetBrowserDialer("")
		return err
	}
	return nil
}

var protocolMu sync.Mutex

func writeResponse(res response) {
	protocolMu.Lock()
	defer protocolMu.Unlock()
	encoded, err := json.Marshal(res)
	if err != nil {
		return
	}
	fmt.Fprintln(os.Stdout, "BPB:"+string(encoded))
}

func writeState(detail string) {
	writeResponse(response{Event: "state", Detail: detail})
}

func binaryVersion(path string, args ...string) string {
	if _, err := os.Stat(path); err != nil { return "" }
	output, err := exec.Command(path, args...).CombinedOutput()
	if err != nil { return "" }
	return strings.TrimSpace(string(output))
}

func main() {
	executable, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "locate BPB core executable:", err)
		os.Exit(1)
	}
	if err := restoreSystemProxy(); err != nil {
		fmt.Fprintln(os.Stderr, "restore previous Windows proxy settings:", err)
	}
	xray.InitEnv(filepath.Join(filepath.Dir(executable), "assets"))
	controller := xray.NewController()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 16*1024*1024)
	defer func() {
		stopPsiphonWindows()
		stopTorWindows()
		_ = controller.Stop()
		xray.SetBrowserDialer("")
		_ = restoreSystemProxy()
	}()

	for scanner.Scan() {
		var req request
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			writeResponse(response{Error: "invalid request: " + err.Error()})
			continue
		}
		res := response{OK: true}
		switch req.Command {
		case "start":
			mode := req.Mode
			if mode == "" {
				mode = "proxy"
			}
			if mode != "proxy" && mode != "systemProxy" && mode != "vpn" {
				res = response{Error: "unsupported connection mode"}
			} else if req.Config == "" {
				res = response{Error: "Xray config is required"}
			} else {
				stopPsiphonWindows()
				stopTorWindows()
				stopErr := controller.Stop()
				proxyErr := restoreSystemProxy()
				if stopErr != nil {
					res = response{Error: "stop previous Xray session: " + stopErr.Error()}
				} else if proxyErr != nil {
					res = response{Error: "restore previous Windows proxy settings: " + proxyErr.Error()}
				} else if err := startController(controller, req); err != nil {
					res = response{Error: err.Error()}
				} else if req.Exit == "tor" {
					if err := startTorWindows(filepath.Dir(executable), req); err != nil {
						_ = controller.Stop()
						res = response{Error: "start Tor: " + err.Error()}
					} else if mode == "systemProxy" {
						if err := applySystemProxy("127.0.0.1:10880"); err != nil {
							stopTorWindows()
							_ = controller.Stop()
							res = response{Error: "could not enable Windows system proxy: " + err.Error()}
						}
					}
				} else if req.Exit != "" && req.Exit != "psiphon" {
					_ = controller.Stop()
					res = response{Error: "unsupported exit process"}
				} else if req.Exit == "psiphon" {
					if err := startPsiphonWindows(filepath.Dir(executable), req); err != nil {
						_ = controller.Stop()
						res = response{Error: "start Psiphon: " + err.Error()}
					} else if mode == "systemProxy" {
						if err := applySystemProxy("127.0.0.1:10880"); err != nil {
							stopPsiphonWindows()
							_ = controller.Stop()
							res = response{Error: "could not enable Windows system proxy: " + err.Error()}
						}
					}
				} else if mode == "systemProxy" {
					if err := applySystemProxy("127.0.0.1:10880"); err != nil {
						_ = controller.Stop()
						xray.SetBrowserDialer("")
						_ = restoreSystemProxy()
						res = response{Error: "could not enable Windows system proxy: " + err.Error()}
					}
				}
			}
		case "stop":
			stopPsiphonWindows()
			stopTorWindows()
			stopErr := controller.Stop()
			xray.SetBrowserDialer("")
			proxyErr := restoreSystemProxy()
			if stopErr != nil {
				res = response{Error: stopErr.Error()}
			} else if proxyErr != nil {
				res = response{Error: proxyErr.Error()}
			}
		case "status":
			res.Running = controller.IsRunning()
		case "traffic":
			res.Traffic = controller.OutboundTraffic()
		case "delay":
			ms, err := controller.MeasureDelay("https://www.gstatic.com/generate_204")
			if err != nil {
				res = response{Error: err.Error(), Delay: -1}
			} else {
				res.Delay = ms
			}
		case "checkDns":
			if req.DNS == "" {
				res = response{Error: "DNS test request is required"}
			} else {
				res.DNS = xray.CheckDNSJSON(req.DNS)
			}
		case "versions":
			root := filepath.Dir(executable)
			res.Xray = xray.Version()
			res.Psiphon = binaryVersion(filepath.Join(root, "bpb_psiphon.exe"), "-version")
			res.Tor = binaryVersion(filepath.Join(root, "tor", "tor.exe"), "--version")
		case "shutdown":
			stopPsiphonWindows()
			stopTorWindows()
			_ = controller.Stop()
			_ = restoreSystemProxy()
			writeResponse(res)
			return
		default:
			res = response{Error: "unknown command"}
		}
		writeResponse(res)
	}
}
