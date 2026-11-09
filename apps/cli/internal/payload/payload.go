// Package payload holds novos-setupd and the release tools it needs, copied in from
// apps/setup/tv and lib/release by "go generate", so that the program brings the
// service that matches it to every TV.
package payload

import "embed"

//go:generate go run gen.go

//go:embed files/*
var Files embed.FS

// Names are the files below files/, in the order they go to the TV.
var Names = []string{"novos-setupd.py", "release.py", "ed25519.py", "trusted-keys.json"}
