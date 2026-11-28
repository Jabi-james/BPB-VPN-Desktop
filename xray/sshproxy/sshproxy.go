// Package sshproxy runs an SSH session and exposes it as a local SOCKS5 proxy.
// It is owned by the VPN controller and runs in-process; it is not a daemon.
package sshproxy

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
)

type config struct {
	Server, User, Password, PrivateKey, Passphrase, HostKey, Upstream, Listen string
	KeepAliveInterval, TCPKeepAliveInterval                                   int
}

const socksListenAddress = "127.0.0.1:1080"

// Config is the SSH settings passed from the app to the VPN core.
type Config struct {
	Host                 string `json:"host"`
	Port                 int    `json:"port"`
	User                 string `json:"user"`
	Password             string `json:"password"`
	PrivateKey           string `json:"privateKey"`
	Passphrase           string `json:"passphrase"`
	HostKey              string `json:"hostKey"`
	KeepAliveInterval    int    `json:"keepAliveInterval"`
	TCPKeepAliveInterval int    `json:"tcpKeepAliveInterval"`
}

// validHostKeyFingerprint accepts the unpadded SHA256 fingerprint format emitted by
// golang.org/x/crypto/ssh.FingerprintSHA256.
func validHostKeyFingerprint(value string) bool {
	if !strings.HasPrefix(value, "SHA256:") || len(value) != len("SHA256:")+43 {
		return false
	}
	for _, r := range value[len("SHA256:"):] {
		if !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' ||
			r >= '0' && r <= '9' || r == '+' || r == '/') {
			return false
		}
	}
	return true
}

// Server owns the SSH connection, SOCKS listener, and reconnect loop.
type Server struct {
	listener net.Listener
	session  *session
	cancel   context.CancelFunc
	done     chan struct{}
	once     sync.Once
}

// Start opens the local SOCKS listener and establishes the first SSH session.
func Start(c Config) (*Server, error) {
	if c.Host == "" || c.User == "" || c.Port < 1 || c.Port > 65535 {
		return nil, errors.New("SSH host, valid port and username are required")
	}
	if c.Password == "" && c.PrivateKey == "" {
		return nil, errors.New("SSH password or private key is required")
	}
	if !validHostKeyFingerprint(strings.TrimSpace(c.HostKey)) {
		return nil, errors.New("a valid SHA256 SSH host key fingerprint is required; verify it from a trusted server console")
	}
	server := net.JoinHostPort(c.Host, strconv.Itoa(c.Port))
	socks, err := net.Listen("tcp", socksListenAddress)
	if err != nil {
		return nil, fmt.Errorf("listen for SSH SOCKS: %w", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	s, err := newSession(config{
		Server: server, User: c.User, Password: c.Password,
		PrivateKey: c.PrivateKey, Passphrase: c.Passphrase, HostKey: strings.TrimSpace(c.HostKey),
		KeepAliveInterval:    c.KeepAliveInterval,
		TCPKeepAliveInterval: c.TCPKeepAliveInterval,
	})
	if err != nil {
		cancel()
		socks.Close()
		return nil, err
	}
	s.ctx = ctx

	// Connect asynchronously so Start() returns immediately. The SOCKS listener
	// is already open; dials through the session wait on its ready channel until
	// the first connection is established or the session fails permanently.
	go func() {
		startCtx, startCancel := context.WithTimeout(ctx, time.Minute)
		defer startCancel()
		if err := s.connectFirstContext(startCtx); err != nil {
			log.Printf("[SSH] SSH initial connection to %s: %v", s.cfg.Server, err)
			var auth errAuth
			if errors.As(err, &auth) {
				s.fatal(err)
			}
		}
	}()

	proxy := &Server{listener: socks, session: s, cancel: cancel, done: make(chan struct{})}
	go func() {
		defer close(proxy.done)
		if err := serveSocks(socks, s); err != nil && ctx.Err() == nil {
			log.Printf("[SSH] SSH SOCKS listener stopped: %v", err)
		}
	}()
	return proxy, nil
}

// StartJSON validates a JSON settings object and starts the SOCKS service.
func StartJSON(configJSON string) (*Server, error) {
	var c Config
	if err := json.Unmarshal([]byte(configJSON), &c); err != nil {
		return nil, fmt.Errorf("SSH settings: %w", err)
	}
	return Start(c)
}

// Stop closes the listener and SSH session. It is safe to call more than once.
func (s *Server) Stop() {
	if s == nil {
		return
	}
	s.once.Do(func() {
		s.cancel()
		s.listener.Close()
		s.session.close()
		<-s.done
	})
}