//go:build windows

package main

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/windows"
)

var aetherCandidateLine = regexp.MustCompile(`(?:wg )?candidate ok\s+(\S+)\s+rtt=(\S+)`)

type aetherScanHit struct {
	Endpoint string  `json:"endpoint"`
	PingMs   float64 `json:"pingMs"`
}

const processSuspendResumeAccess = 0x0800

var (
	aetherNTDLL          = windows.NewLazySystemDLL("ntdll.dll")
	aetherNtSuspendProc  = aetherNTDLL.NewProc("NtSuspendProcess")
	aetherNtResumeProc   = aetherNTDLL.NewProc("NtResumeProcess")
)

func setAetherProcessPaused(pid int, paused bool) error {
	handle, err := windows.OpenProcess(processSuspendResumeAccess, false, uint32(pid))
	if err != nil {
		return fmt.Errorf("open Aether scanner process: %w", err)
	}
	defer windows.CloseHandle(handle)

	proc := aetherNtResumeProc
	action := "resume"
	if paused {
		proc = aetherNtSuspendProc
		action = "pause"
	}
	status, _, _ := proc.Call(uintptr(handle))
	if status != 0 {
		return fmt.Errorf("could not %s Aether scanner (NTSTATUS 0x%08x)", action, uint32(status))
	}
	return nil
}

// scanAetherWindows asks the official Aether core to verify endpoints with its own
// MASQUE / WireGuard data-plane probes, then keeps the requested number of fastest results.
func scanAetherWindows(root string, req request, parent context.Context, controls <-chan string) ([]aetherScanHit, error) {
	protocol := strings.ToLower(strings.TrimSpace(req.AetherProtocol))
	outputCount := req.AetherOutputCount
	if outputCount < 1 || outputCount > 10 {
		outputCount = 10
	}
	if protocol != "masque" && protocol != "wg" {
		return nil, fmt.Errorf("unsupported Aether scan protocol %q", protocol)
	}

	configDir := strings.TrimSpace(req.AetherConfigDir)
	if configDir == "" {
		return nil, fmt.Errorf("Aether data directory was not provided")
	}
	absoluteDir, err := filepath.Abs(configDir)
	if err != nil {
		return nil, fmt.Errorf("resolve Aether data directory: %w", err)
	}
	if err := os.MkdirAll(absoluteDir, 0700); err != nil {
		return nil, fmt.Errorf("create Aether data directory: %w", err)
	}

	exe := filepath.Join(root, "aether", "aether.exe")
	if _, err := os.Stat(exe); err != nil {
		return nil, fmt.Errorf("Aether executable missing: %w", err)
	}
	if err := ensureAetherIdentities(exe, absoluteDir, req.AetherEnvironment, ""); err != nil {
		return nil, err
	}

	protocolFlag := "--masque"
	if protocol == "wg" {
		protocolFlag = "--wg"
	}
	scanMode := strings.TrimSpace(req.AetherEnvironment["AETHER_SCAN"])
	if scanMode == "" {
		scanMode = "balanced"
	}
	args := []string{protocolFlag, "--scan", scanMode, "--bind", "127.0.0.1:0"}
	ctx, cancel := context.WithTimeout(parent, 150*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, exe, args...)
	cmd.Dir = absoluteDir
	settings := make(map[string]string, len(req.AetherEnvironment)+1)
	for key, value := range req.AetherEnvironment {
		settings[key] = value
	}
	settings["AETHER_SCAN"] = scanMode
	cmd.Env = append(aetherEnvironment(os.Environ(), absoluteDir, settings), "AETHER_PROTOCOL="+protocol)

	reader, writer, err := os.Pipe()
	if err != nil {
		return nil, fmt.Errorf("create Aether scanner output pipe: %w", err)
	}
	cmd.Stdout = writer
	cmd.Stderr = writer
	if err := cmd.Start(); err != nil {
		_ = reader.Close()
		_ = writer.Close()
		return nil, fmt.Errorf("start Aether endpoint scanner: %w", err)
	}
	_ = writer.Close()

	lines := make(chan string, 512)
	go func() {
		defer close(lines)
		scanner := bufio.NewScanner(reader)
		scanner.Buffer(make([]byte, 4096), 1024*1024)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		_ = reader.Close()
	}()

	wait := make(chan error, 1)
	go func() { wait <- cmd.Wait() }()

	found := make(map[string]aetherScanHit)
	addCandidate := func(line string) {
		match := aetherCandidateLine.FindStringSubmatch(line)
		if len(match) != 3 {
			return
		}
		endpoint := normalizeAetherEndpoint(match[1])
		rtt, ok := parseAetherRttMs(match[2])
		if !ok || endpoint == "" {
			return
		}
		key := endpoint
		if host, _, err := net.SplitHostPort(endpoint); err == nil {
			key = host // keep only the fastest verified port for each distinct IP
		}
		if previous, exists := found[key]; !exists || rtt < previous.PingMs {
			found[key] = aetherScanHit{Endpoint: endpoint, PingMs: rtt}
		}
	}
	var waitErr error
	finished := false
	paused := false
	for !finished && len(found) < outputCount {
		select {
		case action := <-controls:
			switch action {
			case "pause":
				if !paused && cmd.Process != nil {
					if err := setAetherProcessPaused(cmd.Process.Pid, true); err != nil {
						_ = cmd.Process.Kill()
						waitErr = <-wait
						finished = true
						waitErr = fmt.Errorf("pause Aether scan: %w", err)
					} else {
						paused = true
					}
				}
			case "resume":
				if paused && cmd.Process != nil {
					if err := setAetherProcessPaused(cmd.Process.Pid, false); err != nil {
						_ = cmd.Process.Kill()
						waitErr = <-wait
						finished = true
						waitErr = fmt.Errorf("resume Aether scan: %w", err)
					} else {
						paused = false
					}
				}
			}
		case line, ok := <-lines:
			if !ok {
				lines = nil
				continue
			}
			addCandidate(line)
		case waitErr = <-wait:
			finished = true
		case <-ctx.Done():
			if cmd.Process != nil {
				_ = cmd.Process.Kill()
			}
			waitErr = <-wait
			finished = true
		}
	}

	if len(found) >= outputCount && !finished {
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		waitErr = <-wait
		finished = true
	}
	if !finished && cmd.Process != nil {
		_ = cmd.Process.Kill()
		waitErr = <-wait
	}
	// Drain lines already written before the process exited or was stopped at the requested count.
	for line := range lines {
		addCandidate(line)
	}
	_ = reader.Close()

	hits := make([]aetherScanHit, 0, len(found))
	for _, hit := range found {
		hits = append(hits, hit)
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].PingMs < hits[j].PingMs })

	if len(hits) == 0 {
		if waitErr != nil {
			return nil, fmt.Errorf("Aether found no healthy %s endpoints: %w", protocol, waitErr)
		}
		return nil, fmt.Errorf("Aether found no healthy %s endpoints", protocol)
	}
	if len(hits) > outputCount {
		hits = hits[:outputCount]
	}
	return hits, nil
}

func parseAetherRttMs(value string) (float64, bool) {
	value = strings.TrimSpace(value)
	multiplier := 1.0
	switch {
	case strings.HasSuffix(value, "ms"):
		value = strings.TrimSuffix(value, "ms")
	case strings.HasSuffix(value, "µs"):
		value = strings.TrimSuffix(value, "µs")
		multiplier = 0.001
	case strings.HasSuffix(value, "μs"):
		value = strings.TrimSuffix(value, "μs")
		multiplier = 0.001
	case strings.HasSuffix(value, "us"):
		value = strings.TrimSuffix(value, "us")
		multiplier = 0.001
	case strings.HasSuffix(value, "s"):
		value = strings.TrimSuffix(value, "s")
		multiplier = 1000
	default:
		return 0, false
	}
	n, err := strconv.ParseFloat(value, 64)
	return n * multiplier, err == nil
}

func normalizeAetherEndpoint(value string) string {
	if strings.Count(value, ":") > 1 && !strings.HasPrefix(value, "[") {
		last := strings.LastIndex(value, ":")
		return "[" + value[:last] + "]" + value[last:]
	}
	return value
}
