//go:build windows

// bpb-desktop is the Windows process host for BPB's existing Xray configuration.
// It deliberately has no Firefox VPN integration and starts Xray in proxy-only mode.
package main

import (
	"bufio"
	"encoding/json"
	"os"

	"bpb/xray"
)

type request struct {
	Command string `json:"command"`
	Config  string `json:"config,omitempty"`
}

type response struct {
	OK      bool   `json:"ok"`
	Error   string `json:"error,omitempty"`
	Running bool   `json:"running,omitempty"`
	Delay   int64  `json:"delay,omitempty"`
	Traffic string `json:"traffic,omitempty"`
}

func main() {
	controller := xray.NewController()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 16*1024*1024)
	enc := json.NewEncoder(os.Stdout)
	defer func() {
		_ = controller.Stop()
		_ = restoreSystemProxy()
	}()

	for scanner.Scan() {
		var req request
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			_ = enc.Encode(response{Error: "invalid request: " + err.Error()})
			continue
		}
		res := response{OK: true}
		switch req.Command {
		case "start":
			if req.Config == "" {
				res = response{Error: "Xray config is required"}
			} else if err := controller.Start(req.Config, 0); err != nil {
				res = response{Error: err.Error()}
			} else if err := applySystemProxy("127.0.0.1:10808"); err != nil {
				_ = controller.Stop()
				res = response{Error: "could not enable Windows system proxy: " + err.Error()}
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
			_ = enc.Encode(res)
			return
		default:
			res = response{Error: "unknown command"}
		}
		_ = enc.Encode(res)
	}
}
