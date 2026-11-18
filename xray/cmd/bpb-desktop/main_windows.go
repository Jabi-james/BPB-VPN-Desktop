//go:build windows

// bpb-desktop is the Windows process host for BPB's existing Xray configuration.
// It has no Firefox VPN integration. TUN is intentionally rejected until the
// Windows Wintun/service backend is implemented and tested.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"

	"bpb/xray"
)

type request struct {
	Command string `json:"command"`
	Config  string `json:"config,omitempty"`
	Mode    string `json:"mode,omitempty"`
}

type response struct {
	OK      bool   `json:"ok"`
	Error   string `json:"error,omitempty"`
	Running bool   `json:"running,omitempty"`
	Delay   int64  `json:"delay,omitempty"`
	Traffic string `json:"traffic,omitempty"`
}

func writeResponse(res response) {
	encoded, err := json.Marshal(res)
	if err != nil {
		return
	}
	fmt.Printf("BPB:%s\\n", encoded)
}

func main() {
	controller := xray.NewController()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 16*1024*1024)
	defer func() {
		_ = controller.Stop()
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
			if mode == "vpn" {
				res = response{Error: "Windows TUN mode is not available yet; use Proxy or System Proxy."}
			} else if mode != "proxy" && mode != "systemProxy" {
				res = response{Error: "unsupported connection mode"}
			} else if req.Config == "" {
				res = response{Error: "Xray config is required"}
			} else if err := controller.Start(req.Config, 0); err != nil {
				res = response{Error: err.Error()}
			} else if mode == "systemProxy" {
				if err := applySystemProxy("127.0.0.1:10880"); err != nil {
					_ = controller.Stop()
					res = response{Error: "could not enable Windows system proxy: " + err.Error()}
				}
			}
		case "stop":
			stopErr := controller.Stop()
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
		case "shutdown":
			_ = controller.Stop()
			_ = restoreSystemProxy()
			writeResponse(res)
			return
		default:
			res = response{Error: "unknown command"}
		}
		_ = enc.Encode(res)
	}
}
