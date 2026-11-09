package main

import (
	"flag"
	"io"
	"reflect"
	"strings"
	"testing"
)

func TestParseSSDP(t *testing.T) {
	answer, ok := parseSSDP([]byte("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\n" +
		"LOCATION: http://192.168.1.20:1798/\r\nSERVER: WebOS/4.1.0 UPnP/1.0\r\n" +
		"ST: urn:lge-com:service:webos-second-screen:1\r\nUSN: uuid:x\r\n\r\n"))
	if !ok || answer.location != "http://192.168.1.20:1798/" || answer.server != "WebOS/4.1.0 UPnP/1.0" {
		t.Fatalf("got %+v %v", answer, ok)
	}
	if _, ok := parseSSDP([]byte("HTTP/1.1 200 OK\r\nST: upnp:rootdevice\r\n\r\n")); ok {
		t.Fatal("a non-LG answer was taken")
	}
	if _, ok := parseSSDP([]byte("NOTIFY * HTTP/1.1\r\n\r\n")); ok {
		t.Fatal("a NOTIFY was taken")
	}
}

func TestParseEvent(t *testing.T) {
	event, fields, ok := ParseEvent(`{"event": "progress", "message": "download", "percent": 42, "done": 1, "total": 2}`)
	if !ok || event.Event != "progress" || event.Percent != 42 || fields["total"].(float64) != 2 {
		t.Fatalf("got %+v %v %v", event, fields, ok)
	}
	if _, _, ok := ParseEvent("novos-uninstall: proof of LG's originals"); ok {
		t.Fatal("a plain line was taken as an event")
	}
}

func TestParseInterleaved(t *testing.T) {
	flags := flag.NewFlagSet("t", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	tv := flags.String("tv", "", "")
	yes := flags.Bool("yes", false, "")
	positional, err := parseInterleaved(flags, []string{"beta", "--tv", "10.0.0.2", "--yes"})
	if err != nil || !reflect.DeepEqual(positional, []string{"beta"}) || *tv != "10.0.0.2" || !*yes {
		t.Fatalf("got %v %v %q %v", positional, err, *tv, *yes)
	}
}

func TestRemoteDirIsStable(t *testing.T) {
	first, files, err := remoteDir()
	if err != nil {
		t.Fatal(err)
	}
	second, _, _ := remoteDir()
	if first != second || !strings.HasPrefix(first, "/tmp/novos-setupd-") {
		t.Fatalf("%s %s", first, second)
	}
	if !strings.Contains(string(files["novos-setupd.py"]), "novos-setupd") {
		t.Fatal("the payload does not hold novos-setupd")
	}
}

func TestQuote(t *testing.T) {
	if got := quote("it's"); got != `'it'\''s'` {
		t.Fatal(got)
	}
}
