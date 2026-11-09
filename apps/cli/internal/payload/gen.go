//go:build ignore

// Copies novos-setupd and lib/release into files/ before a build: go generate ./...
package main

import (
	"log"
	"os"
	"path/filepath"
)

func main() {
	sources := map[string]string{
		"novos-setupd.py":   "../../../setup/tv/novos-setupd.py",
		"release.py":        "../../../../lib/release/release.py",
		"ed25519.py":        "../../../../lib/release/ed25519.py",
		"trusted-keys.json": "../../../../lib/release/trusted-keys.json",
	}
	if err := os.MkdirAll("files", 0o755); err != nil {
		log.Fatal(err)
	}
	for name, source := range sources {
		data, err := os.ReadFile(source)
		if err != nil {
			log.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join("files", name), data, 0o644); err != nil {
			log.Fatal(err)
		}
	}
}
