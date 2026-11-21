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
	aetherSocksAddress  = "127.0.0.1:1819"
	aetherUpstreamURL   = "socks5://127.0.0.1:10833"
)

type aetherRuntime struct {
	cmd     *exec.Cmd
	done    chan struct{}
	waitErr error
	log     *os.File
}

var (
	aetherMu          sync.Mutex
	aetherProvisionMu sync.Mutex
	aetherProc        *aetherRuntime
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

	if err := ensureAetherIdentities(exe, absoluteDir, req.AetherEnvironment, aetherUpstreamURL); err != nil {
		return err
	}

	logPath := filepath.Join(absoluteDir, "aether.log")
	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return fmt.Errorf("open Aether log: %w", err)
	}

	protocol := strings.ToLower(strings.TrimSpace(req.AetherProtocol))
	if protocol == "" { protocol = "masque" }
	if protocol != "masque" && protocol != "wg" {
		_ = logFile.Close()
		return fmt.Errorf("unsupported Aether protocol %q", protocol)
	}
	protocolFlag := "--masque"
	if protocol == "wg" { protocolFlag = "--wg" }
	scanMode := strings.TrimSpace(req.AetherEnvironment["AETHER_SCAN"])
	if scanMode == "" { scanMode = "balanced" }
	args := []string{
		protocolFlag,
		"--scan", scanMode,
		"--bind", aetherSocksAddress,
		"--upstream", aetherUpstreamURL,
		"--stats",
	}
	cmd := exec.Command(exe, args...)
	cmd.Dir = absoluteDir
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	cmd.Env = append(aetherEnvironment(os.Environ(), absoluteDir, req.AetherEnvironment), "AETHER_PROTOCOL="+protocol)
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

func ensureAetherIdentities(exe, configDir string, settings map[string]string, upstream string) error {
	aetherProvisionMu.Lock()
	defer aetherProvisionMu.Unlock()
	identities := []struct{ name, file string }{
		{name: "masque", file: "aether-masque.toml"},
		{name: "wg", file: "aether-wg.toml"},
	}
	for _, identity := range identities {
		path := filepath.Join(configDir, identity.file)
		if info, err := os.Stat(path); err == nil && info.Size() > 0 { continue }
		env := append(aetherEnvironment(os.Environ(), configDir, settings), "AETHER_REGISTER="+identity.name)
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		args := []string{}
		if upstream != "" {
			args = append(args, "--upstream", upstream)
		}
		cmd := exec.CommandContext(ctx, exe, args...)
		cmd.Dir = configDir
		cmd.Env = env
		output, err := cmd.CombinedOutput()
		cancel()
		if err != nil {
			return fmt.Errorf("register Aether %s identity: %w; %s", identity.name, err, strings.TrimSpace(string(output)))
		}
		info, err := os.Stat(path)
		if err != nil || info.Size() == 0 {
			return fmt.Errorf("Aether %s registration completed without creating %s: %s", identity.name, path, strings.TrimSpace(string(output)))
		}
	}
	return nil
}

// renewAetherMasqueIdentity registers a fresh MASQUE identity in a temporary file first.
 // The existing identity remains intact unless registration and file validation both succeed.
func renewAetherMasqueIdentity(exe, configDir string) error {
	aetherProvisionMu.Lock()
	defer aetherProvisionMu.Unlock()
	if strings.TrimSpace(configDir) == "" {
		return errors.New("Aether data directory was not provided")
	}
	if err := os.MkdirAll(configDir, 0700); err != nil {
		return fmt.Errorf("create Aether data directory: %w", err)
	}
	original := filepath.Join(configDir, "aether-masque.toml")
	temp := filepath.Join(configDir, fmt.Sprintf("aether-masque-renew-%d.toml", time.Now().UnixNano()))
	defer os.Remove(temp)

	env := aetherEnvironment(os.Environ(), configDir, nil)
	filtered := env[:0]
	for _, entry := range env {
		name, _, _ := strings.Cut(entry, "=")
		if !strings.EqualFold(name, "AETHER_MASQUE_CONFIG") {
			filtered = append(filtered, entry)
		}
	}
	env = append(filtered, "AETHER_MASQUE_CONFIG="+temp)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, exe, "--register", "masque")
	cmd.Dir = configDir
	cmd.Env = env
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("register fresh Aether MASQUE identity: %w; %s", err, strings.TrimSpace(string(output)))
	}
	info, err := os.Stat(temp)
	if err != nil || info.Size() == 0 {
		return fmt.Errorf("Aether MASQUE registration did not create a valid identity: %s", strings.TrimSpace(string(output)))
	}

	backup := original + ".renew-backup"
	_ = os.Remove(backup)
	hadOriginal := false
	if _, err := os.Stat(original); err == nil {
		if err := os.Rename(original, backup); err != nil {
			return fmt.Errorf("preserve current Aether MASQUE identity: %w", err)
		}
		hadOriginal = true
	}
	if err := os.Rename(temp, original); err != nil {
		if hadOriginal {
			_ = os.Rename(backup, original)
		}
		return fmt.Errorf("activate renewed Aether MASQUE identity: %w", err)
	}
	if hadOriginal {
		_ = os.Remove(backup)
	}
	_ = os.Remove(filepath.Join(configDir, "aether-masque-lastconn.toml"))
	return nil
}

func aetherEnvironment(inherited []string, configDir string, settings map[string]string) []string {
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
	allowed := map[string]bool{
		"AETHER_SCAN": true, "AETHER_IP": true, "AETHER_NOIZE": true, "AETHER_DNS": true,
		"AETHER_PEER": true, "AETHER_WG_PEER": true,
		"AETHER_MASQUE_HTTP2": true, "AETHER_MASQUE_SNI": true,
		"AETHER_QUIC_V2": true, "AETHER_MASQUE_H2_FRAGMENT": true,
		"AETHER_MASQUE_H2_FRAGMENT_SIZE": true, "AETHER_MASQUE_H2_FRAGMENT_DELAY": true,
		"AETHER_WG_KEEPALIVE": true, "AETHER_WG_NO_PROFILE_RETRY": true,
	}
	for key, value := range settings {
		if allowed[key] && strings.TrimSpace(value) != "" {
			env = append(env, key+"="+value)
		}
	}
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
