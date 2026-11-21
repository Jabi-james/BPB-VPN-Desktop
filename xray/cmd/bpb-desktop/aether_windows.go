package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	aetherSocksAddress = "127.0.0.1:1819"
	aetherUpstreamURL  = "socks5://127.0.0.1:10833"
)

type aetherRuntime struct {
	cmd     *exec.Cmd
	done    chan struct{}
	waitErr error
	log     *os.File
}

var (
	aetherMu   sync.Mutex
	aetherProc *aetherRuntime
)

func startAetherWindows(root string, req request, cancel <-chan struct{}) error {
	stopAetherWindows()

	exe := filepath.Join(root, "aether", "aether.exe")
	if _, err := os.Stat(exe); err != nil {
		return fmt.Errorf("Aether executable missing: %w", err)
	}
	// Never mistake another app's listener (or another Aether instance) for ours.
	if conn, err := net.DialTimeout("tcp", aetherSocksAddress, 250*time.Millisecond); err == nil {
		_ = conn.Close()
		return fmt.Errorf("Aether SOCKS port %s is already in use", aetherSocksAddress)
	}
	configDir := strings.TrimSpace(req.AetherConfigDir)
	if configDir == "" {
		return errors.New("Aether data directory was not provided")
	}
	absoluteDir, err := filepath.Abs(configDir)
	if err != nil {
		return fmt.Errorf("resolve Aether data directory: %w", err)
	}
	if err := os.MkdirAll(absoluteDir, 0700); err != nil {
		return fmt.Errorf("create Aether data directory: %w", err)
	}

	logPath := filepath.Join(absoluteDir, "aether.log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("open Aether log: %w", err)
	}

	args := []string{
		"--masque",
		"--scan", "balanced",
		"-4",
		"--bind", aetherSocksAddress,
		"--upstream", aetherUpstreamURL,
		"--stats",
	}
	cmd := exec.Command(exe, args...)
	cmd.Dir = absoluteDir
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.Env = aetherEnvironment(os.Environ(), absoluteDir)
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		return fmt.Errorf("launch Aether: %w", err)
	}

	runtime := &aetherRuntime{cmd: cmd, done: make(chan struct{}), log: logFile}
	aetherMu.Lock()
	aetherProc = runtime
	aetherMu.Unlock()
	go func() {
		runtime.waitErr = cmd.Wait()
		close(runtime.done)
	}()

	writeState("Aether · Connecting to WARP…")
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	timeout := time.NewTimer(15 * time.Minute)
	defer timeout.Stop()

	for {
		select {
		case <-cancel:
			stopAetherWindows()
			return errors.New("connection attempt canceled")
		case <-runtime.done:
			clearAetherRuntime(runtime)
			_ = runtime.log.Close()
			if runtime.waitErr == nil {
				runtime.waitErr = errors.New("process exited before its SOCKS5 listener was ready")
			}
			return fmt.Errorf("Aether exited before ready: %w; log: %s", runtime.waitErr, aetherLogTail(logPath))
		case <-timeout.C:
			stopAetherWindows()
			return fmt.Errorf("Aether did not establish its tunnel within 15 minutes; log: %s", aetherLogTail(logPath))
		case <-ticker.C:
			conn, dialErr := net.DialTimeout("tcp", aetherSocksAddress, 350*time.Millisecond)
			if dialErr == nil {
				_ = conn.Close()
				select {
				case <-runtime.done:
					clearAetherRuntime(runtime)
					_ = runtime.log.Close()
					return fmt.Errorf("Aether exited while its SOCKS listener was starting; log: %s", aetherLogTail(logPath))
				default:
				}
				writeState("Aether · Connected")
				return nil
			}
		}
	}
}

func aetherEnvironment(inherited []string, configDir string) []string {
	env := make([]string, 0, len(inherited)+6)
	for _, entry := range inherited {
		name, _, _ := strings.Cut(entry, "=")
		upper := strings.ToUpper(name)
		if strings.HasPrefix(upper, "AETHER_") || upper == "RUST_LOG" || upper == "NO_COLOR" {
			continue
		}
		env = append(env, entry)
	}
	env = append(env,
		"AETHER_CONFIG="+filepath.Join(configDir, "aether.toml"),
		"AETHER_MASQUE_CONFIG="+filepath.Join(configDir, "aether-masque.toml"),
		"AETHER_WG_CONFIG="+filepath.Join(configDir, "aether-wg.toml"),
		"AETHER_LOG_LEVEL=info",
		"NO_COLOR=1",
	)
	return env
}

func clearAetherRuntime(runtime *aetherRuntime) {
	aetherMu.Lock()
	if aetherProc == runtime {
		aetherProc = nil
	}
	aetherMu.Unlock()
}

func stopAetherWindows() {
	aetherMu.Lock()
	runtime := aetherProc
	aetherProc = nil
	aetherMu.Unlock()
	if runtime == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	_ = exec.CommandContext(ctx, "taskkill.exe", "/T", "/F", "/PID", strconv.Itoa(runtime.cmd.Process.Pid)).Run()
	cancel()
	select {
	case <-runtime.done:
	case <-time.After(1500 * time.Millisecond):
		_ = runtime.cmd.Process.Kill()
		select {
		case <-runtime.done:
		case <-time.After(1500 * time.Millisecond):
		}
	}
	_ = runtime.log.Close()
}

func aetherLogTail(path string) string {
	file, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer file.Close()

	lines := make([]string, 0, 35)
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
		if len(lines) > 35 {
			lines = lines[1:]
		}
	}
	return strings.TrimSpace(strings.Join(lines, " | "))
}
