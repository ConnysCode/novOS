// novos installs, updates and removes novOS on an LG TV from a computer on the same
// network. It finds the TVs over SSDP, logs in over SSH as root and drives novos-setupd,
// which it carries itself and copies to /tmp on the TV for every run.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"
)

var version = "dev"

const usage = `novos installs, updates and removes novOS on an LG TV.

  novos                      find TVs, choose one, then install or update
  novos scan                 list the TVs on this network
  novos status               what is installed on the TV
  novos check [channel]      whether a release can be installed (stable, beta or a manifest URL)
  novos install [channel]    install novOS; the picture goes dark for a moment
  novos update               install what is newer in the TV's channel
  novos rollback             go back to the release before
  novos channel [stable|beta]
  novos uninstall [--keep-state]
                             remove novOS and bring back LG's interface
  novos key                  let this computer log in without a password
  novos version

Options, also after the command:
  --tv <address>     the TV (otherwise: NOVOS_TV, or the TV chosen from a list)
  --yes              no questions; for scripts
  --json             one JSON object per line
  --identity <file>  an SSH key to try first
Without a key that the TV accepts, the password comes from the terminal or NOVOS_PASSWORD.
`

type options struct {
	TV        string
	Yes       bool
	JSON      bool
	Identity  string
	KeepState bool
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	command := ""
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		command, args = args[0], args[1:]
	}
	var opts options
	flags := flag.NewFlagSet("novos", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	flags.Usage = func() { fmt.Fprint(os.Stderr, usage) }
	flags.StringVar(&opts.TV, "tv", os.Getenv("NOVOS_TV"), "")
	flags.BoolVar(&opts.Yes, "yes", false, "")
	flags.BoolVar(&opts.JSON, "json", false, "")
	flags.StringVar(&opts.Identity, "identity", "", "")
	flags.BoolVar(&opts.KeepState, "keep-state", false, "")
	positional, err := parseInterleaved(flags, args)
	if err != nil {
		return 2
	}
	switch command {
	case "", "start":
		return guided(opts)
	case "scan":
		return scan(opts)
	case "status", "check", "install", "update", "rollback", "channel", "uninstall":
		return remoteCommand(opts, command, positional)
	case "key":
		return installKey(opts)
	case "version":
		fmt.Println("novos", version)
		return 0
	case "help":
		fmt.Print(usage)
		return 0
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n%s", command, usage)
		return 2
	}
}

// parseInterleaved accepts options before and after the positional arguments.
func parseInterleaved(flags *flag.FlagSet, args []string) ([]string, error) {
	var positional []string
	for {
		if err := flags.Parse(args); err != nil {
			return nil, err
		}
		args = flags.Args()
		if len(args) == 0 {
			return positional, nil
		}
		positional = append(positional, args[0])
		args = args[1:]
	}
}

func printJSON(value interface{}) {
	data, _ := json.Marshal(value)
	fmt.Println(string(data))
}

func scan(opts options) int {
	if !opts.JSON {
		fmt.Fprintln(os.Stderr, "Looking for LG TVs on this network …")
	}
	tvs, err := Discover(context.Background(), 4*time.Second)
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	if opts.JSON {
		printJSON(tvs)
		return 0
	}
	if len(tvs) == 0 {
		fmt.Println("No LG TV answered. Is it on and in the same network? Otherwise use --tv <address>.")
		return 1
	}
	for _, tv := range tvs {
		fmt.Println(describeTV(tv))
	}
	return 0
}

func describeTV(tv TV) string {
	name := tv.Name
	if name == "" {
		name = "LG TV"
	}
	state := "no SSH: needs root and the Homebrew Channel"
	if tv.SSH {
		state = "ready (SSH)"
	}
	return fmt.Sprintf("%-22s %-22s %-15s %s", name, tv.Model, tv.Address, state)
}

// chooseTV returns --tv, or lets the user pick one of the TVs found.
func chooseTV(opts options) (string, error) {
	if opts.TV != "" {
		return opts.TV, nil
	}
	if !interactive() {
		return "", fmt.Errorf("no TV given: use --tv <address> or NOVOS_TV")
	}
	fmt.Println("Looking for LG TVs on this network …")
	tvs, err := Discover(context.Background(), 4*time.Second)
	if err != nil {
		return "", err
	}
	items := make([]string, 0, len(tvs)+1)
	for _, tv := range tvs {
		items = append(items, describeTV(tv))
	}
	items = append(items, "Enter an address …")
	title := "Choose the TV (arrow keys, Enter):"
	if len(tvs) == 0 {
		title = "No LG TV answered. Enter its address:"
	}
	index := len(items) - 1
	if len(tvs) > 0 {
		if index, err = pick(title, items); err != nil {
			return "", err
		}
	}
	if index == len(tvs) {
		address := ask("Address of the TV:")
		if address == "" {
			return "", errCancelled
		}
		return address, nil
	}
	if !tvs[index].SSH {
		return "", fmt.Errorf("%s does not answer on SSH. novOS needs a rooted TV with the Homebrew Channel", tvs[index].Address)
	}
	return tvs[index].Address, nil
}

func connect(opts options) (*Remote, error) {
	host, err := chooseTV(opts)
	if err != nil {
		return nil, err
	}
	if !opts.JSON {
		fmt.Fprintf(os.Stderr, "Connecting to %s …\n", host)
	}
	return Connect(host, ConnectOptions{Identity: opts.Identity, Yes: opts.Yes})
}

// What a command does to the TV, asked before it runs unless --yes.
var warnings = map[string]string{
	"install":   "This replaces what runs on the TV; the picture goes dark for a moment.",
	"update":    "This replaces what runs on the TV; the picture goes dark for a moment.",
	"rollback":  "This goes back to the release before; the picture goes dark for a moment.",
	"uninstall": "This removes novOS and brings back LG's interface.",
}

func remoteCommand(opts options, command string, positional []string) int {
	remote, err := connect(opts)
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	defer remote.Close()
	renderer := &Renderer{JSON: opts.JSON}
	if warning, ok := warnings[command]; ok && !opts.Yes {
		if command == "install" || command == "update" {
			source := firstOr(positional, "")
			checkArgs := []string{"check"}
			if source != "" {
				checkArgs = append(checkArgs, source)
			}
			if code, err := remote.Setupd(checkArgs, false, renderer.Handle); err != nil || code != 0 {
				return failed(err, code)
			}
		}
		fmt.Fprintln(os.Stderr, warning)
		if !confirm("Go ahead?") {
			fmt.Fprintln(os.Stderr, "Nothing changed.")
			return 1
		}
	}
	args := append([]string{command}, positional...)
	if command == "uninstall" && opts.KeepState {
		args = append(args, "--keep-state")
	}
	code, err := remote.Setupd(args, command == "uninstall", renderer.Handle)
	return failed(err, code)
}

func failed(err error, code int) int {
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	return code
}

func firstOr(values []string, fallback string) string {
	if len(values) > 0 {
		return values[0]
	}
	return fallback
}

// guided is novos without a command: choose a TV, see its state, install or update.
func guided(opts options) int {
	remote, err := connect(opts)
	if err != nil {
		if err == errCancelled {
			return 1
		}
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	defer remote.Close()
	renderer := &Renderer{JSON: opts.JSON}
	if code, err := remote.Setupd([]string{"status"}, false, renderer.Handle); err != nil || code != 0 {
		return failed(err, code)
	}
	fmt.Println()
	var available string
	check := func(event Event, fields map[string]interface{}) {
		if result, ok := fields["check"].(map[string]interface{}); ok {
			if newer, _ := result["newer"].(bool); newer {
				if problems, _ := result["problems"].([]interface{}); len(problems) == 0 {
					available, _ = result["available"].(string)
				}
			}
		}
		renderer.Handle(event, fields)
	}
	if _, err := remote.Setupd([]string{"check"}, false, check); err != nil {
		return failed(err, 1)
	}
	if available == "" {
		return 0
	}
	fmt.Println()
	fmt.Println(warnings["install"])
	if !opts.Yes && !confirm(fmt.Sprintf("Install novOS %s now?", available)) {
		fmt.Println("Nothing changed.")
		return 0
	}
	code, err := remote.Setupd([]string{"install"}, false, renderer.Handle)
	return failed(err, code)
}

func installKey(opts options) int {
	remote, err := connect(opts)
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	defer remote.Close()
	line, err := EnsureOwnKey()
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	added, err := remote.InstallKey(line)
	if err != nil {
		fmt.Fprintln(os.Stderr, "✗", err)
		return 1
	}
	if added {
		fmt.Printf("The TV now accepts this computer's novos key (%s).\n", ownKeyPath())
	} else {
		fmt.Println("The TV accepts this computer's novos key already.")
	}
	return 0
}
