package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/xml"
	"io"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

// TV is a television found on the network.
type TV struct {
	Address      string `json:"address"`
	Name         string `json:"name"`
	Model        string `json:"model"`
	Manufacturer string `json:"manufacturer"`
	Server       string `json:"server"` // SSDP SERVER header, names the webOS version on LG sets
	SSH          bool   `json:"ssh"`    // port 22 answers: rooted, with the Homebrew Channel's SSH
	SSHBanner    string `json:"sshBanner,omitempty"`
}

// LG's webOS sets answer this search target (the one LG's own phone apps use).
const lgSearchTarget = "urn:lge-com:service:webos-second-screen:1"

var ssdpAddress = &net.UDPAddr{IP: net.IPv4(239, 255, 255, 250), Port: 1900}

type ssdpAnswer struct {
	address  string
	location string
	server   string
}

// Discover asks the network for LG TVs over SSDP and fills in name, model and SSH.
func Discover(ctx context.Context, wait time.Duration) ([]TV, error) {
	answers, err := search(ctx, wait)
	if err != nil {
		return nil, err
	}
	var (
		tvs   []TV
		mutex sync.Mutex
		group sync.WaitGroup
	)
	for _, answer := range answers {
		group.Add(1)
		go func(answer ssdpAnswer) {
			defer group.Done()
			tv := TV{Address: answer.address, Server: answer.server}
			describe(ctx, answer.location, &tv)
			tv.SSH, tv.SSHBanner = probeSSH(answer.address)
			mutex.Lock()
			tvs = append(tvs, tv)
			mutex.Unlock()
		}(answer)
	}
	group.Wait()
	sort.Slice(tvs, func(i, j int) bool {
		if tvs[i].SSH != tvs[j].SSH {
			return tvs[i].SSH
		}
		return tvs[i].Name < tvs[j].Name
	})
	return tvs, nil
}

func search(ctx context.Context, wait time.Duration) ([]ssdpAnswer, error) {
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero})
	if err != nil {
		return nil, err
	}
	defer connection.Close()
	request := []byte("M-SEARCH * HTTP/1.1\r\n" +
		"HOST: 239.255.255.250:1900\r\n" +
		"MAN: \"ssdp:discover\"\r\n" +
		"MX: 2\r\n" +
		"ST: " + lgSearchTarget + "\r\n\r\n")
	// UDP gets lost now and then: ask three times.
	for i := 0; i < 3; i++ {
		if _, err := connection.WriteToUDP(request, ssdpAddress); err != nil {
			return nil, err
		}
		time.Sleep(100 * time.Millisecond)
	}
	deadline := time.Now().Add(wait)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	_ = connection.SetReadDeadline(deadline)
	seen := map[string]ssdpAnswer{}
	buffer := make([]byte, 4096)
	for {
		n, from, err := connection.ReadFromUDP(buffer)
		if err != nil {
			break // the deadline ends the search
		}
		answer, ok := parseSSDP(buffer[:n])
		if !ok {
			continue
		}
		answer.address = from.IP.String()
		if _, known := seen[answer.address]; !known {
			seen[answer.address] = answer
		}
	}
	answers := make([]ssdpAnswer, 0, len(seen))
	for _, answer := range seen {
		answers = append(answers, answer)
	}
	return answers, nil
}

// parseSSDP reads an SSDP answer; ok only for answers to the LG search target.
func parseSSDP(packet []byte) (ssdpAnswer, bool) {
	reader := bufio.NewReader(bytes.NewReader(packet))
	status, err := reader.ReadString('\n')
	if err != nil || !strings.HasPrefix(status, "HTTP/1.1 200") {
		return ssdpAnswer{}, false
	}
	var answer ssdpAnswer
	matches := false
	for {
		line, err := reader.ReadString('\n')
		line = strings.TrimSpace(line)
		if name, value, found := strings.Cut(line, ":"); found {
			value = strings.TrimSpace(value)
			switch strings.ToUpper(strings.TrimSpace(name)) {
			case "LOCATION":
				answer.location = value
			case "SERVER":
				answer.server = value
			case "ST":
				matches = value == lgSearchTarget
			}
		}
		if err != nil {
			break
		}
	}
	return answer, matches
}

type deviceDescription struct {
	Device struct {
		FriendlyName string `xml:"friendlyName"`
		Manufacturer string `xml:"manufacturer"`
		ModelName    string `xml:"modelName"`
		ModelNumber  string `xml:"modelNumber"`
	} `xml:"device"`
}

func describe(ctx context.Context, location string, tv *TV) {
	if location == "" {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, location, nil)
	if err != nil {
		return
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return
	}
	defer response.Body.Close()
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return
	}
	var description deviceDescription
	if xml.Unmarshal(data, &description) != nil {
		return
	}
	tv.Name = description.Device.FriendlyName
	tv.Manufacturer = description.Device.Manufacturer
	tv.Model = description.Device.ModelName
	if description.Device.ModelNumber != "" && !strings.Contains(tv.Model, description.Device.ModelNumber) {
		tv.Model = strings.TrimSpace(tv.Model + " " + description.Device.ModelNumber)
	}
}

func probeSSH(address string) (bool, string) {
	connection, err := net.DialTimeout("tcp", net.JoinHostPort(address, "22"), 1500*time.Millisecond)
	if err != nil {
		return false, ""
	}
	defer connection.Close()
	_ = connection.SetReadDeadline(time.Now().Add(1500 * time.Millisecond))
	banner, _ := bufio.NewReader(connection).ReadString('\n')
	return true, strings.TrimSpace(banner)
}
