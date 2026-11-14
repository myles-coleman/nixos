package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/evidence"
)

func main() {
	file := flag.String("file", "", "evidence JSONL file")
	head := flag.String("head", "", "head sidecar (defaults to head.json beside the file)")
	flag.Parse()

	if *file == "" {
		fmt.Fprintln(os.Stderr, "usage: redteam-evidence-verify --file <events.jsonl> [--head <head.json>]")
		os.Exit(2)
	}
	if *head == "" {
		*head = filepath.Join(filepath.Dir(*file), "head.json")
	}

	report, err := evidence.Verify(*file, *head)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	data, _ := json.MarshalIndent(report, "", "  ")
	fmt.Println(string(data))
	if !report.OK {
		os.Exit(1)
	}
}
