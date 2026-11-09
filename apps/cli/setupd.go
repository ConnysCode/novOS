package main

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/ConnysCode/novOS/apps/cli/internal/payload"
)

// Event is one line of novos-setupd --json.
type Event struct {
	Event   string                 `json:"event"` // step, progress, result, error
	Message string                 `json:"message"`
	Percent int                    `json:"percent"`
	Fields  map[string]interface{} `json:"-"`
}

// remoteDir is where this program's copy of novos-setupd lives on the TV: in /tmp, named
// after its content, so that every version of the program brings and finds its own.
func remoteDir() (string, map[string][]byte, error) {
	files := map[string][]byte{}
	digest := sha256.New()
	for _, name := range payload.Names {
		data, err := payload.Files.ReadFile("files/" + name)
		if err != nil {
			return "", nil, fmt.Errorf("payload %s: %w (run go generate)", name, err)
		}
		files[name] = data
		digest.Write([]byte(name))
		digest.Write(data)
	}
	return "/tmp/novos-setupd-" + hex.EncodeToString(digest.Sum(nil))[:12], files, nil
}

// Deploy copies novos-setupd to the TV unless the same copy is there already.
func (r *Remote) Deploy() (string, error) {
	dir, files, err := remoteDir()
	if err != nil {
		return "", err
	}
	if _, code, err := r.Output("test -f " + quote(dir+"/.complete")); err == nil && code == 0 {
		return dir, nil
	}
	if out, code, err := r.Output("rm -rf " + quote(dir) + " && mkdir -p " + quote(dir)); err != nil || code != 0 {
		return "", fmt.Errorf("preparing %s on the TV: %v %s", dir, err, strings.TrimSpace(out))
	}
	for _, name := range payload.Names {
		mode := os.FileMode(0o644)
		if strings.HasSuffix(name, ".py") {
			mode = 0o755
		}
		if err := r.WriteFile(dir+"/"+name, files[name], mode); err != nil {
			return "", err
		}
	}
	if _, code, err := r.Output("touch " + quote(dir+"/.complete")); err != nil || code != 0 {
		return "", fmt.Errorf("marking %s complete: %v", dir, err)
	}
	return dir, nil
}

// Setupd runs novos-setupd on the TV with args, hands every event to handle and returns the
// exit code. With pty the service gets a terminal (needed by uninstall).
func (r *Remote) Setupd(args []string, pty bool, handle func(Event, map[string]interface{})) (int, error) {
	dir, err := r.Deploy()
	if err != nil {
		return -1, err
	}
	quoted := make([]string, 0, len(args)+3)
	quoted = append(quoted, "python3", quote(dir+"/novos-setupd.py"), "--json")
	for _, arg := range args {
		quoted = append(quoted, quote(arg))
	}
	reader, writer := io.Pipe()
	var errOut bytes.Buffer
	done := make(chan struct{})
	go func() {
		defer close(done)
		scanner := bufio.NewScanner(reader)
		scanner.Buffer(make([]byte, 64*1024), 1<<20)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" {
				continue
			}
			event, fields, ok := ParseEvent(line)
			if !ok {
				// Lines of the release's scripts (uninstall) are passed on as steps.
				handle(Event{Event: "step", Message: line}, nil)
				continue
			}
			handle(event, fields)
		}
	}()
	code, err := r.Run(strings.Join(quoted, " "), nil, writer, &errOut, pty)
	writer.Close()
	<-done
	if err == nil && code != 0 && errOut.Len() > 0 {
		handle(Event{Event: "error", Message: strings.TrimSpace(errOut.String())}, nil)
	}
	return code, err
}

// ParseEvent reads one JSON line of novos-setupd.
func ParseEvent(line string) (Event, map[string]interface{}, bool) {
	if !strings.HasPrefix(line, "{") {
		return Event{}, nil, false
	}
	var fields map[string]interface{}
	if json.Unmarshal([]byte(line), &fields) != nil {
		return Event{}, nil, false
	}
	var event Event
	if json.Unmarshal([]byte(line), &event) != nil || event.Event == "" {
		return Event{}, nil, false
	}
	return event, fields, true
}
