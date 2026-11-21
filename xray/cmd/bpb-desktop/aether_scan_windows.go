//go:build windows

package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var aetherCandidateLine = regexp.MustCompile(`(?:wg )?candidate ok\s+(\S+)\s+rtt=(\S+)`)

type aetherScanHit struct {
	endpoint string
	rttMs    float64
}

// scanAetherWindows asks the official Aether core to verify endpoints with its own
// MASQUE / WireGuard data-plane probes, then keeps the ten fastest successful results.
func scanAetherWindows(root string, req request) ([]string, error) {
	protocol := strings.ToLower(strings.TrimSpace(req.AetherProtocol))
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
	if err := ensureAetherIdentities(exe, absoluteDir, req.AetherEnvironment); err != nil {
		return nil, err
	}

	protocolFlag := "--masque"
	if protocol == "wg" {
		protocolFlag = "--wg"
	}
	args := []string{protocolFlag, "--scan", "thorough", "--bind", "127.0.0.1:0"}
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, exe, args...)
	cmd.Dir = absoluteDir
	settings := make(map[string]string, len(req.AetherEnvironment)+1)
	for key, value := range req.AetherEnvironment {
		settings[key] = value
	}
	settings["AETHER_SCAN"] = "thorough"
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

	found := make(map[string]float64)
	var waitErr error
	finished := false
	for !finished && len(found) < 10 {
		select {
		case line, ok := <-lines:
			if !ok {
				lines = nil
				continue
			}
			match := aetherCandidateLine.FindStringSubmatch(line)
			if len(match) != 3 {
				continue
			}
			endpoint := normalizeAetherEndpoint(match[1])
			rtt, ok := parseAetherRttMs(match[2])
			if !ok || endpoint == "" {
				continue
			}
			if previous, exists := found[endpoint]; !exists || rtt < previous {
				found[endpoint] = rtt
			}
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

	if len(found) >= 10 && !finished {
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
	_ = reader.Close()

	hits := make([]aetherScanHit, 0, len(found))
	for endpoint, rtt := range found {
		hits = append(hits, aetherScanHit{endpoint: endpoint, rttMs: rtt})
	}
	sort.Slice(hits, func(i, j int) bool { return hits[i].rttMs < hits[j].rttMs })

	if len(hits) == 0 {
		if waitErr != nil {
			return nil, fmt.Errorf("Aether found no healthy %s endpoints: %w", protocol, waitErr)
		}
		return nil, fmt.Errorf("Aether found no healthy %s endpoints", protocol)
	}
	if len(hits) > 10 {
		hits = hits[:10]
	}
	endpoints := make([]string, len(hits))
	for i, hit := range hits {
		endpoints[i] = hit.endpoint
	}
	return endpoints, nil
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
