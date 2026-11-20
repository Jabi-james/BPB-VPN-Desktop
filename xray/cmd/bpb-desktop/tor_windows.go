//go:build windows

package main

import (
	"bufio"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const torControlPort = "127.0.0.1:10831"

type torRuntime struct {
	cmd *exec.Cmd
	done chan struct{}
	waitErr error
	log *os.File
	mu sync.Mutex
}

var (
	torMu sync.Mutex
	torProc *torRuntime
	bootstrapPattern = regexp.MustCompile(`PROGRESS=(\d+)`)
)

func startTorWindows(root string, req request) error {
	stopTorWindows()
	torDir := filepath.Join(root, "tor")
	for _, name := range []string{"tor.exe", "lyrebird.exe", "geoip", "geoip6", "pt_config.json"} {
		if _, err := os.Stat(filepath.Join(torDir, name)); err != nil {
			if name == "pt_config.json" && req.TorBridge == "direct" { continue }
			return fmt.Errorf("Tor bundle file %s missing: %w", name, err)
		}
	}
	dataDir := filepath.Join(root, "data", "tor")
	if err := os.MkdirAll(dataDir, 0700); err != nil { return err }
	cookie := filepath.Join(dataDir, "control_auth_cookie")
	_ = os.Remove(cookie)
	bridges, err := torBridgesWindows(torDir, req)
	if err != nil { return err }

	quote := func(s string) string { return strconv.Quote(s) }
	lines := []string{
		"DataDirectory " + quote(dataDir),
		"SocksPort 127.0.0.1:10829",
		"DNSPort 127.0.0.1:10830",
		"GeoIPFile " + quote(filepath.Join(torDir, "geoip")),
		"GeoIPv6File " + quote(filepath.Join(torDir, "geoip6")),
		"ControlPort " + torControlPort,
		"CookieAuthentication 1",
		"Log notice file " + quote(filepath.Join(root, "tor.log")),
		"ClientOnly 1",
		"AvoidDiskWrites 1",
	}
	if req.ExitRegion != "" {
		lines = append(lines, "ExitNodes {"+strings.ToLower(req.ExitRegion)+"}", "StrictNodes 1")
	}
	if !req.ExitDirect { lines = append(lines, "Socks5Proxy 127.0.0.1:10828") }
	if len(bridges) > 0 {
		lyrebird := quote(filepath.Join(torDir, "lyrebird.exe"))
		lines = append(lines,
			"UseBridges 1",
			"ClientTransportPlugin meek_lite,obfs4,webtunnel exec "+lyrebird,
			"ClientTransportPlugin snowflake exec "+lyrebird,
		)
		for _, bridge := range bridges { lines = append(lines, "Bridge "+bridge) }
	}
	torrc := filepath.Join(dataDir, "torrc")
	if err := os.WriteFile(torrc, []byte(strings.Join(lines, "\r\n")+"\r\n"), 0600); err != nil { return err }
	logFile, err := os.OpenFile(filepath.Join(root, "tor.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil { return err }
	cmd := exec.Command(filepath.Join(torDir, "tor.exe"), "-f", torrc)
	cmd.Dir = torDir
	stdout, err := cmd.StdoutPipe()
	if err != nil { logFile.Close(); return err }
	stderr, err := cmd.StderrPipe()
	if err != nil { logFile.Close(); return err }
	if err := cmd.Start(); err != nil { logFile.Close(); return fmt.Errorf("launch Tor: %w", err) }
	runtime := &torRuntime{cmd:cmd, done:make(chan struct{}), log:logFile}
	torMu.Lock(); torProc=runtime; torMu.Unlock()
	stdoutDone, stderrDone := make(chan struct{}), make(chan struct{})
	for _, item := range []struct{pipe interface{Read([]byte)(int,error)}; done chan struct{}; prefix string}{{stdout,stdoutDone,""},{stderr,stderrDone,"[stderr] "}} {
		go func(p interface{Read([]byte)(int,error)}, done chan struct{}, prefix string) {
			defer close(done)
			scanner:=bufio.NewScanner(p)
			scanner.Buffer(make([]byte,4096),4*1024*1024)
			for scanner.Scan() { runtime.mu.Lock(); _,_=fmt.Fprintln(runtime.log,prefix+scanner.Text()); runtime.mu.Unlock() }
		}(item.pipe,item.done,item.prefix)
	}
	go func(){ <-stdoutDone; <-stderrDone; runtime.waitErr=cmd.Wait(); close(runtime.done) }()

	conn, err := waitTorControl(cookie, runtime.done, 15*time.Minute)
	if err != nil { stopTorWindows(); return err }
	defer conn.Close()
	if err := torAuthenticate(conn, cookie); err != nil { stopTorWindows(); return err }
	_ = conn.SetDeadline(time.Now().Add(2*time.Second))
	if _, err := fmt.Fprint(conn, "SETEVENTS STATUS_CLIENT CIRC\r\n"); err != nil { stopTorWindows(); return err }
	reader := bufio.NewReader(conn)
	if err := torReadOK(reader); err != nil { stopTorWindows(); return fmt.Errorf("Tor control events: %w",err) }
	if _, err := fmt.Fprint(conn, "GETINFO status/bootstrap-phase\r\n"); err != nil { stopTorWindows(); return err }
	if progress, err := torReadBootstrap(reader); err == nil && progress >= 100 { return nil }
	_ = conn.SetReadDeadline(time.Now().Add(1500*time.Millisecond))
	deadline := time.Now().Add(15*time.Minute)
	for time.Now().Before(deadline) {
		select {
		case <-runtime.done:
			clearTorRuntime(runtime); runtime.log.Close()
			err:=runtime.waitErr
			if err == nil { err=errors.New("Tor exited before bootstrap completed") }
			return fmt.Errorf("Tor exited before ready: %w",err)
		default:
		}
		line, readErr := reader.ReadString('\n')
		if readErr != nil {
			if ne, ok := readErr.(net.Error); ok && ne.Timeout() { continue }
			stopTorWindows()
			return fmt.Errorf("Tor control connection closed: %w",readErr)
		}
		if progress, ok := parseTorProgress(line); ok && progress >= 100 { return nil }
	}
	stopTorWindows()
	return errors.New("Tor did not finish bootstrapping within 15 minutes")
}

func torBridgesWindows(torDir string, req request) ([]string,error) {
	if !req.ExitDirect || req.TorBridge=="" || req.TorBridge=="direct" { return nil,nil }
	if req.TorBridge=="custom" {
		if len(req.TorCustomBridges)==0 { return nil,errors.New("no custom Tor bridges are configured") }
		return req.TorCustomBridges,nil
	}
	raw,err:=os.ReadFile(filepath.Join(torDir,"pt_config.json")); if err!=nil{return nil,err}
	var cfg struct{ Bridges map[string][]string `json:"bridges"` }
	if err:=json.Unmarshal(raw,&cfg);err!=nil{return nil,err}
	key:=req.TorBridge
	if key=="snowflake-amp" { key="snowflake" }
	list:=cfg.Bridges[key]
	if len(list)==0{return nil,fmt.Errorf("no built-in %s bridges in Tor bundle",key)}
	if req.TorBridge=="snowflake-amp" {
		for i,line:=range list {
			fields:=strings.Fields(line); kept:=fields[:0]
			for _,field:=range fields { k:=strings.SplitN(field,"=",2)[0]; if k!="url"&&k!="front"&&k!="fronts"&&k!="ampcache" {kept=append(kept,field)} }
			list[i]=strings.Join(kept," ")+" url=https://snowflake-broker.torproject.net/ ampcache=https://cdn.ampproject.org/ front=www.google.com"
		}
	}
	return list,nil
}

func waitTorControl(cookie string, exited <-chan struct{}, timeout time.Duration)(net.Conn,error){
	deadline:=time.Now().Add(timeout)
	for time.Now().Before(deadline){
		select { case <-exited: return nil,errors.New("Tor exited before control port opened"); default: }
		if info,err:=os.Stat(cookie);err==nil&&info.Size()==32 {
			if conn,err:=net.DialTimeout("tcp",torControlPort,700*time.Millisecond);err==nil{return conn,nil}
		}
		time.Sleep(200*time.Millisecond)
	}
	return nil,errors.New("Tor control port did not open")
}

func torAuthenticate(conn net.Conn,cookie string)error{
	raw,err:=os.ReadFile(cookie);if err!=nil{return err}
	if _, err = fmt.Fprintf(conn, "AUTHENTICATE %s\r\n", hex.EncodeToString(raw)); err != nil { return err }
	return torReadOK(bufio.NewReader(conn))
}

func torReadOK(reader *bufio.Reader)error{
	for i:=0;i<100;i++{
		line, err := reader.ReadString('\n'); if err != nil { return err }
		line=strings.TrimSpace(line)
		if strings.HasPrefix(line,"250 OK"){return nil}
		if strings.HasPrefix(line,"4")||strings.HasPrefix(line,"5"){return errors.New(line)}
	}
	return errors.New("unexpected Tor control response")
}

func torReadBootstrap(reader *bufio.Reader)(int,error){
	progress:=-1
	for i:=0;i<100;i++{
		line, err := reader.ReadString('\n'); if err != nil { return progress, err }
		if n,ok:=parseTorProgress(line);ok{progress=n}
		if strings.HasPrefix(strings.TrimSpace(line),"250 OK"){return progress,nil}
	}
	return progress,errors.New("unexpected Tor bootstrap response")
}

func parseTorProgress(line string)(int,bool){
	m:=bootstrapPattern.FindStringSubmatch(line);if len(m)!=2{return 0,false}
	n,err:=strconv.Atoi(m[1]);return n,err==nil
}

func clearTorRuntime(p *torRuntime){
	torMu.Lock();if torProc==p{torProc=nil};torMu.Unlock()
}

func stopTorWindows(){
	torMu.Lock();p:=torProc;torProc=nil;torMu.Unlock()
	if p==nil{return}
	_ = exec.Command("taskkill.exe","/T","/F","/PID",strconv.Itoa(p.cmd.Process.Pid)).Run()
	select{case <-p.done:case <-time.After(3*time.Second):_ = p.cmd.Process.Kill();<-p.done}
	p.mu.Lock();_ = p.log.Close();p.mu.Unlock()
}
