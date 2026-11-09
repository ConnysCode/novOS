package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"

	"golang.org/x/term"
)

var errCancelled = errors.New("cancelled")

func interactive() bool {
	return term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd()))
}

// confirm asks a yes/no question on the terminal; no terminal means no.
func confirm(question string) bool {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return false
	}
	fmt.Fprintf(os.Stderr, "%s [y/N] ", question)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	answer := strings.ToLower(strings.TrimSpace(line))
	return answer == "y" || answer == "yes" || answer == "j" || answer == "ja"
}

func ask(question string) string {
	fmt.Fprintf(os.Stderr, "%s ", question)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	return strings.TrimSpace(line)
}

// pick lets the user choose one line with the arrow keys and Enter; q or Ctrl-C cancels.
func pick(title string, items []string) (int, error) {
	if len(items) == 0 {
		return -1, errors.New("nothing to choose from")
	}
	fd := int(os.Stdin.Fd())
	state, err := term.MakeRaw(fd)
	if err != nil {
		return -1, err
	}
	restore := enableVirtualTerminal()
	defer func() {
		term.Restore(fd, state)
		restore()
	}()
	selected := 0
	draw := func(first bool) {
		if !first {
			fmt.Printf("\x1b[%dA", len(items))
		}
		for i, item := range items {
			marker := "  "
			style := ""
			if i == selected {
				marker = "› "
				style = "\x1b[1m"
			}
			fmt.Printf("\r\x1b[2K%s%s%s\x1b[0m\r\n", marker, style, item)
		}
	}
	fmt.Printf("%s\r\n", title)
	draw(true)
	buffer := make([]byte, 8)
	for {
		n, err := os.Stdin.Read(buffer)
		if err != nil {
			return -1, err
		}
		input := string(buffer[:n])
		switch {
		case input == "\x1b[A" || input == "k":
			selected = (selected + len(items) - 1) % len(items)
		case input == "\x1b[B" || input == "j":
			selected = (selected + 1) % len(items)
		case input == "\r" || input == "\n":
			return selected, nil
		case input == "q" || input == "\x03" || input == "\x1b":
			return -1, errCancelled
		}
		draw(false)
	}
}

// Renderer prints the events of novos-setupd for a person, or passes them on as JSON.
type Renderer struct {
	JSON        bool
	inProgress  bool
	lastPercent int
}

func (r *Renderer) Handle(event Event, fields map[string]interface{}) {
	if r.JSON {
		if fields == nil {
			fields = map[string]interface{}{"event": event.Event, "message": event.Message}
		}
		printJSON(fields)
		return
	}
	switch event.Event {
	case "progress":
		if event.Percent == r.lastPercent && r.inProgress {
			return
		}
		r.lastPercent = event.Percent
		r.inProgress = true
		width := 30
		filled := event.Percent * width / 100
		fmt.Printf("\r    %s %s %3d %%", event.Message, strings.Repeat("█", filled)+strings.Repeat("·", width-filled), event.Percent)
	default:
		if r.inProgress {
			fmt.Println()
			r.inProgress = false
		}
		switch event.Event {
		case "step":
			fmt.Printf("  · %s\n", event.Message)
		case "result":
			fmt.Println(event.Message)
		case "error":
			fmt.Fprintf(os.Stderr, "✗ %s\n", strings.TrimPrefix(event.Message, "novos-setupd: "))
		}
	}
}
