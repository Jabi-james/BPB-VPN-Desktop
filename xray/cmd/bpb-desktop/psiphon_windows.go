//go:build windows

package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type psiphonRuntime struct {
	cmd *exec.Cmd
	stdin io.WriteCloser
	wait chan error
	log *os.File
	mu sync.Mutex
}

var (
	psiphonMu sync.Mutex
	psiphonProc *psiphonRuntime
)

func startPsiphonWindows(root string, req request) error {
	stopPsiphonWindows()
	exe := filepath.Join(root, "bpb_psiphon.exe")
	if _, err := os.Stat(exe); err != nil { return fmt.Errorf("Psiphon executable missing: %w", err) }
	raw, err := os.ReadFile(filepath.Join(root, "psiphon_config.json"))
	if err != nil { return fmt.Errorf("read Psiphon config: %w", err) }
	var config map[string]any
	if err := json.Unmarshal(raw, &config); err != nil { return fmt.Errorf("parse Psiphon config: %w", err) }

	dataDir := filepath.Join(root, "data", "psiphon")
	if err := os.MkdirAll(dataDir, 0700); err != nil { return fmt.Errorf("create Psiphon data directory: %w", err) }
	config["DataRootDirectory"] = dataDir
	config["EgressRegion"] = req.ExitRegion
	if !req.ExitDirect { config["UpstreamProxyURL"] = "socks5://127.0.0.1:10828" }
	config["BpbSocksListen"] = "127.0.0.1:10829"
	config["BpbDnsListen"] = "127.0.0.1:10830"
	if strings.TrimSpace(req.PsiphonConfig) != "" {
		var extra map[string]any
		if err := json.Unmarshal([]byte(req.PsiphonConfig), &extra); err != nil { return fmt.Errorf("parse Psiphon mode settings: %w", err) }
		for k, v := range extra { config[k] = v }
	}
	encoded, err := json.Marshal(config)
	if err != nil { return err }
	configFile := filepath.Join(dataDir, "config.json")
	if err := os.WriteFile(configFile, encoded, 0600); err != nil { return fmt.Errorf("write Psiphon config: %w", err) }

	logFile, err := os.OpenFile(filepath.Join(root, "psiphon.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil { return fmt.Errorf("open Psiphon log: %w", err) }
	cmd := exec.Command(exe, "-config", configFile)
	cmd.Dir = dataDir
	stdin, err := cmd.StdinPipe()
	if err != nil { logFile.Close(); return err }
	stdout, err := cmd.StdoutPipe()
	if err != nil { logFile.Close(); return err }
	stderr, err := cmd.StderrPipe()
	if err != nil { logFile.Close(); return err }
	if err := cmd.Start(); err != nil { logFile.Close(); return fmt.Errorf("launch Psiphon: %w", err) }

	runtime := &psiphonRuntime{cmd: cmd, stdin: stdin, wait: make(chan error, 1), log: logFile}
	psiphonMu.Lock()
	psiphonProc = runtime
	psiphonMu.Unlock()

	ready := make(chan error, 1)
	var readyOnce sync.Once
	signalReady := func(err error) { readyOnce.Do(func(){ ready <- err }) }
	stdoutDone := make(chan struct{})
	stderrDone := make(chan struct{})
	go func() {
		defer close(stdoutDone)
		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 4096), 4*1024*1024)
		for scanner.Scan() {
			line := scanner.Text()
			runtime.mu.Lock(); _, _ = fmt.Fprintln(runtime.log, line); runtime.mu.Unlock()
			var event struct { Event string `json:"event"`; Message string `json:"message"` }
			if json.Unmarshal([]byte(line), &event) == nil {
				switch event.Event {
				case "ready": signalReady(nil)
				case "error": signalReady(errors.New(event.Message))
				}
			}
		}
		if err := scanner.Err(); err != nil { signalReady(fmt.Errorf("read Psiphon output: %w", err)) }
	}()
	go func() {
		defer close(stderrDone)
		scanner := bufio.NewScanner(stderr)
		scanner.Buffer(make([]byte, 4096), 4*1024*1024)
		for scanner.Scan() {
			runtime.mu.Lock(); _, _ = fmt.Fprintln(runtime.log, "[stderr] "+scanner.Text()); runtime.mu.Unlock()
		}
	}()
	go func() {
		<-stdoutDone
		<-stderrDone
		runtime.wait <- cmd.Wait()
	}()

	select {
	case err := <-ready:
		if err != nil { stopPsiphonWindows(); return err }
		return nil
	case err := <-runtime.wait:
		clearPsiphonRuntime(runtime)
		runtime.log.Close()
		if err == nil { err = errors.New("process exited before the first tunnel was ready") }
		return fmt.Errorf("Psiphon exited before ready: %w", err)
	case <-time.After(15*time.Minute):
		stopPsiphonWindows()
		return errors.New("Psiphon did not establish a tunnel within 15 minutes")
	}
}

func clearPsiphonRuntime(p *psiphonRuntime) {
	psiphonMu.Lock()
	if psiphonProc == p { psiphonProc = nil }
	psiphonMu.Unlock()
}

func stopPsiphonWindows() {
	psiphonMu.Lock()
	p := psiphonProc
	psiphonProc = nil
	psiphonMu.Unlock()
	if p == nil { return }
	_ = p.stdin.Close()
	select {
	case <-p.wait:
	case <-time.After(2*time.Second):
		_ = p.cmd.Process.Kill()
		<-p.wait
	}
	p.mu.Lock(); _ = p.log.Close(); p.mu.Unlock()
}
