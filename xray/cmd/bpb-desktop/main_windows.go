//go:build windows

// bpb-desktop is the Windows process host for BPB's existing Xray configuration.
// It has no Firefox VPN integration. Xray-core owns the Wintun adapter and route lifecycle.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"bpb/xray"
)

type request struct {
	Command string `json:"command"`
	Config  string `json:"config,omitempty"`
	Mode    string `json:"mode,omitempty"`
	DNS     string `json:"dns,omitempty"`
	VerifyConnection bool `json:"verifyConnection,omitempty"`
	BrowserDialer bool `json:"browserDialer,omitempty"`
}

type response struct {
	OK      bool   `json:"ok"`
	Error   string `json:"error,omitempty"`
	Running bool   `json:"running,omitempty"`
	Delay   int64  `json:"delay,omitempty"`
	Traffic string `json:"traffic,omitempty"`
	Xray    string `json:"xray,omitempty"`
	DNS     string `json:"dns,omitempty"`
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

func writeResponse(res response) {
	encoded, err := json.Marshal(res)
	if err != nil {
		return
	}
	fmt.Fprintln(os.Stdout, "BPB:"+string(encoded))
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
				stopErr := controller.Stop()
				proxyErr := restoreSystemProxy()
				if stopErr != nil {
					res = response{Error: "stop previous Xray session: " + stopErr.Error()}
				} else if proxyErr != nil {
					res = response{Error: "restore previous Windows proxy settings: " + proxyErr.Error()}
				} else if err := startController(controller, req); err != nil {
					res = response{Error: err.Error()}
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
			res.Xray = xray.Version()
		case "shutdown":
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
