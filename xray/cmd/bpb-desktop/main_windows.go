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
	AetherConfigDir string `json:"aetherConfigDir,omitempty"`
	AetherProtocol string `json:"aetherProtocol,omitempty"`
	AetherEnvironment map[string]string `json:"aetherEnvironment,omitempty"`
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
	AetherEndpoints []string `json:"aetherEndpoints,omitempty"`
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

// Stop both optional exit helpers concurrently; their process waits are bounded.
func stopExitProcesses() {
	var wg sync.WaitGroup
	wg.Add(3)
	go func() { defer wg.Done(); stopPsiphonWindows() }()
	go func() { defer wg.Done(); stopTorWindows() }()
	go func() { defer wg.Done(); stopAetherWindows() }()
	wg.Wait()
}

var (
	startControlMu sync.Mutex
	activeStartCancel chan struct{}
	activeStartDone chan struct{}
)

func cancelActiveStart() {
	startControlMu.Lock()
	cancel := activeStartCancel
	startControlMu.Unlock()
	if cancel == nil { return }
	select { case <-cancel: default: close(cancel) }
}

func waitForActiveStart() {
	startControlMu.Lock()
	done := activeStartDone
	startControlMu.Unlock()
	if done != nil { <-done }
}

func isStartCanceled(cancel <-chan struct{}) bool {
	select { case <-cancel: return true; default: return false }
}

func runStart(controller *xray.Controller, root string, req request, cancel <-chan struct{}) response {
	mode := req.Mode
	if mode == "" { mode = "proxy" }
	if mode != "proxy" && mode != "systemProxy" && mode != "vpn" {
		return response{Error: "unsupported connection mode"}
	}
	if req.Config == "" { return response{Error: "Xray config is required"} }
	stopExitProcesses()
	if err := controller.Stop(); err != nil { return response{Error: "stop previous Xray session: " + err.Error()} }
	if err := restoreSystemProxy(); err != nil { return response{Error: "restore previous Windows proxy settings: " + err.Error()} }
	if isStartCanceled(cancel) { return response{Error: "Connection attempt canceled."} }
	// Xray starts first only to expose a dedicated DIRECT bootstrap SOCKS listener
	// for Aether's own control-plane. User traffic still follows Aether -> Chain -> destination.
	if err := startController(controller, req); err != nil {
		return response{Error: err.Error()}
	}
	cleanup := func() {
		stopExitProcesses()
		_ = controller.Stop()
		xray.SetBrowserDialer("")
		_ = restoreSystemProxy()
	}
	if req.AetherProtocol != "" {
		if err := startAetherWindows(root, req, cancel); err != nil {
			cleanup()
			return response{Error: "start Aether: " + err.Error()}
		}
	}
	if req.Exit == "tor" {
		if err := startTorWindows(root, req, cancel); err != nil {
			cleanup()
			return response{Error: "start Tor: " + err.Error()}
		}
	} else if req.Exit == "psiphon" {
		if err := startPsiphonWindows(root, req, cancel); err != nil {
			cleanup()
			return response{Error: "start Psiphon: " + err.Error()}
		}
	} else if req.Exit == "aether" {
		if err := startAetherWindows(root, req, cancel); err != nil {
			cleanup()
			return response{Error: "start Aether: " + err.Error()}
		}
	} else if req.Exit != "" {
		cleanup()
		return response{Error: "unsupported exit process"}
	}
	if isStartCanceled(cancel) { cleanup(); return response{Error: "Connection attempt canceled."} }
	if mode == "systemProxy" {
		if err := applySystemProxy("127.0.0.1:10880"); err != nil {
			cleanup()
			return response{Error: "could not enable Windows system proxy: " + err.Error()}
		}
	}
	return response{OK: true}
}


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
	root := filepath.Dir(executable)
	xray.InitEnv(filepath.Join(root, "assets"))
	xray.InitCertDir(root)
	controller := xray.NewController()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 16*1024*1024)
	defer func() {
		cancelActiveStart()
		waitForActiveStart()
		stopExitProcesses()
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
			startControlMu.Lock()
			if activeStartDone != nil {
				startControlMu.Unlock()
				writeResponse(response{Error: "A connection attempt is already running."})
				continue
			}
			cancel := make(chan struct{})
			done := make(chan struct{})
			activeStartCancel, activeStartDone = cancel, done
			startControlMu.Unlock()
			go func() {
				writeResponse(runStart(controller, filepath.Dir(executable), req, cancel))
				close(done)
				startControlMu.Lock()
				if activeStartDone == done { activeStartCancel, activeStartDone = nil, nil }
				startControlMu.Unlock()
			}()
			continue
		case "cancel":
			cancelActiveStart()
			continue
		case "stop":
			cancelActiveStart()
			waitForActiveStart()
			stopExitProcesses()
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
		case "provisionAether":
			root := filepath.Dir(executable)
			exe := filepath.Join(root, "aether", "aether.exe")
			if err := ensureAetherIdentities(exe, req.AetherConfigDir, nil, ""); err != nil {
				res = response{Error: err.Error()}
			} else {
				res = response{OK: true}
			}
		case "renewAetherMasque":
			if controller.IsRunning() {
				res = response{Error: "Disconnect before renewing the Aether MASQUE identity."}
			} else {
				root := filepath.Dir(executable)
				exe := filepath.Join(root, "aether", "aether.exe")
				if err := renewAetherMasqueIdentity(exe, req.AetherConfigDir); err != nil {
					res = response{Error: err.Error()}
				} else {
					res = response{OK: true}
				}
			}
		case "scanAether":
			if controller.IsRunning() {
				res = response{Error: "Disconnect before scanning Aether endpoints."}
			} else {
				endpoints, err := scanAetherWindows(filepath.Dir(executable), req)
				if err != nil {
					res = response{Error: err.Error()}
				} else {
					res = response{OK: true, AetherEndpoints: endpoints}
				}
			}
		case "versions":
			root := filepath.Dir(executable)
			res.Xray = xray.Version()
			res.Psiphon = binaryVersion(filepath.Join(root, "bpb_psiphon.exe"), "-version")
			res.Tor = binaryVersion(filepath.Join(root, "tor", "tor.exe"), "--version")
		case "shutdown":
			cancelActiveStart()
			waitForActiveStart()
			stopExitProcesses()
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
