//go:build windows

package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// testTorBridgeWindows launches a fully separate Tor process with its own data directory,
// SOCKS/control ports and cookie. It never touches the active Tor runtime or its torrc.
func testTorBridgeWindows(root, bridge string) (retErr error) {
	bridge = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(bridge), "Bridge "))
	fields := strings.Fields(bridge)
	if len(fields) < 2 || !map[string]bool{"obfs4":true,"webtunnel":true,"snowflake":true,"meek_lite":true}[fields[0]] {
		return errors.New("unsupported or malformed Tor bridge line")
	}
	torDir := filepath.Join(root, "tor")
	for _, name := range []string{"tor.exe", "lyrebird.exe", "geoip", "geoip6"} {
		if _, err := os.Stat(filepath.Join(torDir, name)); err != nil { return fmt.Errorf("Tor bundle file %s missing: %w", name, err) }
	}
	allocPort := func() (int, error) {
		l, err := net.Listen("tcp", "127.0.0.1:0"); if err != nil { return 0, err }
		p := l.Addr().(*net.TCPAddr).Port; _ = l.Close(); return p, nil
	}
	socksPort, err := allocPort(); if err != nil { return err }
	controlPort, err := allocPort(); if err != nil { return err }
	tmp, err := os.MkdirTemp("", "bpb-tor-bridge-test-"); if err != nil { return err }
	defer os.RemoveAll(tmp)
	cookie := filepath.Join(tmp, "control_auth_cookie")
	q := strconv.Quote
	lines := []string{
		"DataDirectory " + q(tmp),
		fmt.Sprintf("SocksPort 127.0.0.1:%d", socksPort),
		fmt.Sprintf("ControlPort 127.0.0.1:%d", controlPort),
		"CookieAuthentication 1",
		"GeoIPFile " + q(filepath.Join(torDir,"geoip")),
		"GeoIPv6File " + q(filepath.Join(torDir,"geoip6")),
		"ClientOnly 1", "AvoidDiskWrites 1", "UseBridges 1",
		"ClientTransportPlugin meek_lite,obfs4,webtunnel exec " + q(filepath.Join(torDir,"lyrebird.exe")),
		"ClientTransportPlugin snowflake exec " + q(filepath.Join(torDir,"lyrebird.exe")),
		"Bridge " + bridge,
		"Log notice file " + q(filepath.Join(tmp,"tor.log")),
	}
	torrc := filepath.Join(tmp,"torrc")
	if err := os.WriteFile(torrc, []byte(strings.Join(lines,"\r\n")+"\r\n"), 0600); err != nil { return err }
	log, err := os.OpenFile(filepath.Join(tmp,"tor.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600); if err != nil { return err }
	defer log.Close()
	cmd := exec.Command(filepath.Join(torDir,"tor.exe"), "-f", torrc)
	cmd.Dir = torDir; cmd.Stdout = log; cmd.Stderr = log
	if err := cmd.Start(); err != nil { return fmt.Errorf("start isolated Tor: %w",err) }
	done := make(chan struct{})
	var waitErr error
	go func(){ waitErr = cmd.Wait(); close(done) }()
	defer func(){
		if cmd.Process != nil {
			ctx,cancel:=contextWithTimeout(2*time.Second); _=exec.CommandContext(ctx,"taskkill.exe","/T","/F","/PID",strconv.Itoa(cmd.Process.Pid)).Run(); cancel()
			select { case <-done: case <-time.After(2*time.Second): _=cmd.Process.Kill(); <-done }
		}
	}()
	deadline := time.Now().Add(3*time.Minute)
	for time.Now().Before(deadline) {
		select { case <-done: if waitErr==nil {return errors.New("isolated Tor exited before bootstrap")}; return fmt.Errorf("isolated Tor exited: %w",waitErr); default: }
		if _,e:=os.Stat(cookie); e==nil {
			conn,e:=net.DialTimeout("tcp",fmt.Sprintf("127.0.0.1:%d",controlPort),500*time.Millisecond)
			if e==nil {
				_ = conn.SetDeadline(time.Now().Add(2*time.Second))
				if e=authenticateTorTest(conn,cookie); e==nil {
					phase,pe:=torTestCommand(conn,"GETINFO status/bootstrap-phase")
					conn.Close()
					if pe==nil {
						progress:=-1
						if m:=bootstrapPattern.FindStringSubmatch(phase); len(m)==2 {progress,_=strconv.Atoi(m[1])}
						if progress>=100 { return testTorSOCKS(socksPort) }
					}
				} else {conn.Close()}
			}
		}
		time.Sleep(1500*time.Millisecond)
	}
	data,_:=os.ReadFile(filepath.Join(tmp,"tor.log")); tail:=string(data); if len(tail)>1800 {tail=tail[len(tail)-1800:]}
	return fmt.Errorf("bridge did not bootstrap within 3 minutes: %s",strings.TrimSpace(tail))
}

func contextWithTimeout(d time.Duration) (context.Context, context.CancelFunc) { return context.WithTimeout(context.Background(),d) }

func authenticateTorTest(conn net.Conn, cookiePath string) error {
	cookie,err:=os.ReadFile(cookiePath); if err!=nil{return err}
	if _,err=fmt.Fprintf(conn,"AUTHENTICATE %s\r\n",hex.EncodeToString(cookie));err!=nil{return err}
	return torReadOK(bufio.NewReader(conn))
}

func torTestCommand(conn net.Conn, command string) (string,error) {
	if _,err:=fmt.Fprintf(conn,"%s\r\n",command);err!=nil{return "",err}
	r:=bufio.NewReader(conn); var b strings.Builder
	for i:=0;i<100;i++ { line,err:=r.ReadString('\n'); if err!=nil{return "",err}; b.WriteString(line); if strings.HasPrefix(strings.TrimSpace(line),"250 OK"){return b.String(),nil}; if strings.HasPrefix(strings.TrimSpace(line),"5"){return "",errors.New(strings.TrimSpace(line))} }
	return "",errors.New("unexpected Tor control response")
}

func testTorSOCKS(port int) error {
	conn,err:=net.DialTimeout("tcp",fmt.Sprintf("127.0.0.1:%d",port),5*time.Second); if err!=nil{return err}; defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(25*time.Second))
	if _,err=conn.Write([]byte{5,1,0});err!=nil{return err}
	g:=make([]byte,2);if _,err=io.ReadFull(conn,g);err!=nil{return err};if g[0]!=5||g[1]!=0{return errors.New("Tor SOCKS authentication negotiation failed")}
	host:="check.torproject.org"; req:=[]byte{5,1,0,3,byte(len(host))};req=append(req,[]byte(host)...);req=append(req,1,187)
	if _,err=conn.Write(req);err!=nil{return err}
	h:=make([]byte,4);if _,err=io.ReadFull(conn,h);err!=nil{return err};if h[1]!=0{return fmt.Errorf("Tor SOCKS connection failed (code %d)",h[1])}
	var skip int
	switch h[3] {case 1:skip=4;case 4:skip=16;case 3:var n [1]byte;if _,err=io.ReadFull(conn,n[:]);err!=nil{return err};skip=int(n[0]);default:return errors.New("invalid Tor SOCKS response")}
	if _,err=io.CopyN(io.Discard,conn,int64(skip+2));err!=nil{return err}
	tlsConn:=tls.Client(conn,&tls.Config{ServerName:host,MinVersion:tls.VersionTLS12}); if err:=tlsConn.Handshake();err!=nil{return fmt.Errorf("TLS through Tor failed: %w",err)}
	if _,err=fmt.Fprintf(tlsConn,"GET /api/ip HTTP/1.1\r\nHost: %s\r\nConnection: close\r\nAccept: application/json\r\n\r\n",host);err!=nil{return err}
	body,err:=io.ReadAll(tlsConn);if err!=nil{return err};text:=string(body)
	i:=strings.Index(text,"\r\n\r\n");if i<0{return errors.New("Tor test site returned an invalid HTTP response")}
	if !strings.Contains(text[:i],"200 OK"){return errors.New("Tor test site returned a non-200 response")}
	var result struct{ IsTor bool }
	if err:=json.Unmarshal([]byte(text[i+4:]),&result);err!=nil||!result.IsTor{return errors.New("Tor reached the test site but it did not confirm a Tor exit")}
	return nil
}
