package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"golang.org/x/crypto/ssh/knownhosts"
	"golang.org/x/term"
)

// Remote is an SSH connection to a TV as root.
type Remote struct {
	client *ssh.Client
	Host   string
}

// ConnectOptions say how to log in.
type ConnectOptions struct {
	User     string
	Identity string // a private key file, before the usual ones
	Yes      bool   // accept a new host key without asking
}

func configDir() string {
	base, err := os.UserConfigDir()
	if err != nil {
		base = os.TempDir()
	}
	return filepath.Join(base, "novos")
}

func ownKeyPath() string { return filepath.Join(configDir(), "id_ed25519") }

func withPort(host string) string {
	if _, _, err := net.SplitHostPort(host); err == nil {
		return host
	}
	return net.JoinHostPort(host, "22")
}

// Connect logs in to host: first with keys (agent, novos' own key, the usual ones in ~/.ssh),
// then with a password typed in the terminal or taken from NOVOS_PASSWORD.
func Connect(host string, options ConnectOptions) (*Remote, error) {
	if options.User == "" {
		options.User = "root"
	}
	address := withPort(host)
	callback, err := hostKeyCallback(options.Yes)
	if err != nil {
		return nil, err
	}
	config := &ssh.ClientConfig{
		User:            options.User,
		Auth:            authMethods(options),
		HostKeyCallback: callback,
		// Ed25519 first, the key type ~/.ssh/known_hosts usually holds for the TV.
		HostKeyAlgorithms: []string{ssh.KeyAlgoED25519, ssh.KeyAlgoECDSA256, ssh.KeyAlgoECDSA384,
			ssh.KeyAlgoECDSA521, ssh.KeyAlgoRSASHA512, ssh.KeyAlgoRSASHA256},
		Timeout: 10e9,
	}
	client, err := ssh.Dial("tcp", address, config)
	if err != nil {
		return nil, fmt.Errorf("SSH to %s: %w", address, err)
	}
	return &Remote{client: client, Host: host}, nil
}

func (r *Remote) Close() error { return r.client.Close() }

func authMethods(options ConnectOptions) []ssh.AuthMethod {
	var signers []ssh.Signer
	if socket := os.Getenv("SSH_AUTH_SOCK"); socket != "" && runtime.GOOS != "windows" {
		if connection, err := net.Dial("unix", socket); err == nil {
			if agentSigners, err := agent.NewClient(connection).Signers(); err == nil {
				signers = append(signers, agentSigners...)
			}
		}
	}
	home, _ := os.UserHomeDir()
	paths := []string{options.Identity, ownKeyPath()}
	for _, name := range []string{"id_ed25519", "id_ecdsa", "id_rsa"} {
		paths = append(paths, filepath.Join(home, ".ssh", name))
	}
	for _, path := range paths {
		if path == "" {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		signer, err := ssh.ParsePrivateKey(data)
		if err != nil {
			continue // a key with a passphrase is the agent's job
		}
		signers = append(signers, signer)
	}
	methods := []ssh.AuthMethod{}
	if len(signers) > 0 {
		methods = append(methods, ssh.PublicKeys(signers...))
	}
	password := func() (string, error) {
		if value := os.Getenv("NOVOS_PASSWORD"); value != "" {
			return value, nil
		}
		if !term.IsTerminal(int(os.Stdin.Fd())) {
			return "", errors.New("no key accepted and no terminal for a password")
		}
		fmt.Fprint(os.Stderr, "Password for root on the TV: ")
		value, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		return string(value), err
	}
	methods = append(methods, ssh.PasswordCallback(password))
	methods = append(methods, ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
		answers := make([]string, len(questions))
		for i := range questions {
			value, err := password()
			if err != nil {
				return nil, err
			}
			answers[i] = value
		}
		return answers, nil
	}))
	return methods
}

// hostKeyCallback trusts a TV that ~/.ssh/known_hosts or novos' own list knows, else on first
// use after showing its fingerprint, and refuses a TV whose key changed since.
func hostKeyCallback(yes bool) (ssh.HostKeyCallback, error) {
	path := filepath.Join(configDir(), "known_hosts")
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		if err := os.WriteFile(path, nil, 0o600); err != nil {
			return nil, err
		}
	}
	files := []string{path}
	if home, err := os.UserHomeDir(); err == nil {
		if _, err := os.Stat(filepath.Join(home, ".ssh", "known_hosts")); err == nil {
			files = append(files, filepath.Join(home, ".ssh", "known_hosts"))
		}
	}
	known, err := knownhosts.New(files...)
	if err != nil {
		return nil, err
	}
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		err := known(hostname, remote, key)
		var keyError *knownhosts.KeyError
		if err == nil || !errors.As(err, &keyError) {
			return err
		}
		if len(keyError.Want) > 0 {
			return fmt.Errorf("the TV's host key changed since the last time (%s); "+
				"if the TV was reset, remove its line from %s", ssh.FingerprintSHA256(key), path)
		}
		fmt.Fprintf(os.Stderr, "First connection to %s. Its key: %s\n", hostname, ssh.FingerprintSHA256(key))
		if !yes && !confirm("Trust this TV?") {
			return errors.New("host key not trusted")
		}
		line := knownhosts.Line([]string{knownhosts.Normalize(hostname)}, key)
		file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o600)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = fmt.Fprintln(file, line)
		return err
	}, nil
}

// Run runs a shell command on the TV and returns its exit code. With pty the command gets
// a terminal, which novos-uninstall.sh uses to read and restore the foreground app.
func (r *Remote) Run(command string, stdin io.Reader, stdout, stderr io.Writer, pty bool) (int, error) {
	session, err := r.client.NewSession()
	if err != nil {
		return -1, err
	}
	defer session.Close()
	if pty {
		if err := session.RequestPty("xterm", 40, 120, ssh.TerminalModes{ssh.ECHO: 0}); err != nil {
			return -1, err
		}
	}
	session.Stdin = stdin
	session.Stdout = stdout
	session.Stderr = stderr
	err = session.Run(command)
	var exitError *ssh.ExitError
	if errors.As(err, &exitError) {
		return exitError.ExitStatus(), nil
	}
	if err != nil {
		return -1, err
	}
	return 0, nil
}

// Output runs a command and returns what it printed.
func (r *Remote) Output(command string) (string, int, error) {
	var out bytes.Buffer
	code, err := r.Run(command, nil, &out, &out, false)
	return out.String(), code, err
}

// WriteFile puts data into path on the TV.
func (r *Remote) WriteFile(path string, data []byte, mode os.FileMode) error {
	command := fmt.Sprintf("cat > %s.new && chmod %o %s.new && mv %s.new %s", quote(path), mode, quote(path), quote(path), quote(path))
	var errOut bytes.Buffer
	code, err := r.Run(command, bytes.NewReader(data), io.Discard, &errOut, false)
	if err == nil && code != 0 {
		err = fmt.Errorf("writing %s: %s", path, strings.TrimSpace(errOut.String()))
	}
	return err
}

func quote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", `'\''`) + "'"
}

// EnsureOwnKey creates novos' own key on this computer once and returns its public line.
func EnsureOwnKey() (string, error) {
	path := ownKeyPath()
	if data, err := os.ReadFile(path); err == nil {
		signer, err := ssh.ParsePrivateKey(data)
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(ssh.MarshalAuthorizedKey(signer.PublicKey()))), nil
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return "", err
	}
	block, err := ssh.MarshalPrivateKey(private, "novos")
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(path, pem.EncodeToMemory(block), 0o600); err != nil {
		return "", err
	}
	sshPublic, err := ssh.NewPublicKey(public)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(ssh.MarshalAuthorizedKey(sshPublic))) + " novos", nil
}

// InstallKey adds a public key line to root's authorized_keys on the TV, once.
func (r *Remote) InstallKey(line string) (bool, error) {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return false, errors.New("not a public key")
	}
	command := fmt.Sprintf(`mkdir -p /home/root/.ssh && chmod 700 /home/root/.ssh && touch /home/root/.ssh/authorized_keys &&
chmod 600 /home/root/.ssh/authorized_keys && if grep -qF %s /home/root/.ssh/authorized_keys; then echo present; else
echo %s >> /home/root/.ssh/authorized_keys && echo added; fi`, quote(fields[1]), quote(line))
	out, code, err := r.Output(command)
	if err == nil && code != 0 {
		err = fmt.Errorf("authorized_keys: %s", strings.TrimSpace(out))
	}
	return strings.TrimSpace(out) == "added", err
}
