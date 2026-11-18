// Command bpb_scanner exposes BPB's existing Go/Xray scanner to desktop Flutter.
// The line-delimited JSON protocol keeps the scanner algorithm and result format identical
// to Android's gomobile ScannerBridge.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"bpb/xray"
)

type command struct {
	ID      string          `json:"id"`
	Action  string          `json:"action"`
	Options json.RawMessage `json:"options"`
}

type response struct {
	ID      string `json:"id,omitempty"`
	Type    string `json:"type"`
	Message string `json:"message,omitempty"`
}

func main() {
	log.SetOutput(os.Stderr)
	bridge := xray.NewScannerBridge()
	defer bridge.CloseScan()

	commands := make(chan command, 16)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		scanner.Buffer(make([]byte, 4096), 4<<20)
		for scanner.Scan() {
			var cmd command
			if err := json.Unmarshal(scanner.Bytes(), &cmd); err != nil {
				write(response{Type: "error", Message: "invalid command: " + err.Error()})
				continue
			}
			commands <- cmd
		}
		close(commands)
	}()

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case cmd, ok := <-commands:
			if !ok {
				return
			}
			var err string
			switch strings.ToLower(cmd.Action) {
			case "start":
				if len(cmd.Options) == 0 {
					err = "scanner options are required"
				} else {
					err = bridge.StartScan(string(cmd.Options))
				}
			case "pause":
				err = bridge.PauseScan()
			case "resume":
				err = bridge.ResumeScan()
			case "stop":
				err = bridge.StopScan()
			case "close":
				bridge.CloseScan()
				write(response{ID: cmd.ID, Type: "ack"})
				return
			default:
				err = "unknown scanner action: " + cmd.Action
			}
			if err != "" {
				write(response{ID: cmd.ID, Type: "error", Message: err})
			} else {
				write(response{ID: cmd.ID, Type: "ack"})
			}
		case <-ticker.C:
			if bridge.IsRunning() {
				raw := bridge.PollEvent(20)
				if raw != "" {
					fmt.Println(raw)
				}
			}
		}
	}
}

func write(value response) {
	encoded, err := json.Marshal(value)
	if err == nil {
		fmt.Println(string(encoded))
	}
}
