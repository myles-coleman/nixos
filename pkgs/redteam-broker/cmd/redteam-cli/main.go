package main

import (
	"bufio"
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/action"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/evidence"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/token"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "action":
		actionCmd(os.Args[2:])
	case "verify":
		verifyCmd(os.Args[2:])
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: redteam-cli <action|verify> [flags]")
	os.Exit(2)
}

func actionCmd(args []string) {
	flags := flag.NewFlagSet("action", flag.ExitOnError)
	broker := flags.String("broker", "https://10.0.0.151:8443", "broker base URL")
	engagement := flags.String("engagement", "stage1-demo", "engagement ID")
	scopeVersion := flags.Int("scope-version", 1, "scope version")
	phase := flags.String("phase", "recon", "engagement phase")
	target := flags.String("target", "10.99.0.2", "target address")
	technique := flags.String("technique", "http.get", "technique ID")
	path := flags.String("path", "/", "target-relative path")
	keyPath := flags.String("key", filepath.Join(os.Getenv("HOME"), ".config/redteam/approval.key"), "approval Ed25519 private key")
	serverCert := flags.String("server-cert", filepath.Join(os.Getenv("HOME"), ".config/redteam/server.crt"), "pinned broker certificate")
	clientCert := flags.String("client-cert", filepath.Join(os.Getenv("HOME"), ".config/redteam/client.crt"), "client certificate")
	clientKey := flags.String("client-key", filepath.Join(os.Getenv("HOME"), ".config/redteam/client.key"), "client key")
	decision := flags.String("decision", "", "approve, deny, or defer (prompts when empty)")
	rationale := flags.String("rationale", "", "approval rationale")
	nonce := flags.String("nonce", "", "single-use nonce (defaults to a timestamp)")
	ttl := flags.Int("ttl", 600, "token lifetime in seconds")
	insecure := flags.Bool("insecure", false, "skip server certificate verification (local tests only)")
	flags.Parse(args)

	act := action.Action{
		EngagementID: *engagement,
		ScopeVersion: *scopeVersion,
		TechniqueID:  *technique,
		Target:       *target,
		Parameters:   map[string]string{"path": *path},
	}
	canonical, err := act.Canonical()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("Canonical action:\n%s\n\n", canonical)

	choice := *decision
	reason := *rationale
	if choice == "" {
		reader := bufio.NewReader(os.Stdin)
		fmt.Print("approve/deny/defer [approve]: ")
		line, _ := reader.ReadString('\n')
		choice = strings.TrimSpace(line)
		if choice == "" {
			choice = "approve"
		}
		fmt.Print("rationale: ")
		line, _ = reader.ReadString('\n')
		reason = strings.TrimSpace(line)
	}

	if choice != "approve" {
		fmt.Printf("decision=%s (no token issued)\n", choice)
		return
	}
	if reason == "" {
		fmt.Fprintln(os.Stderr, "approve requires a rationale")
		os.Exit(1)
	}
	if *nonce == "" {
		*nonce = fmt.Sprintf("nonce-%d", time.Now().UnixNano())
	}

	priv, err := token.LoadPrivateKey(*keyPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	value := token.Token{
		AuthorizationDetails: []token.AuthorizationDetail{{
			Type:         "redteam_action",
			EngagementID: *engagement,
			ScopeVersion: *scopeVersion,
			Phase:        *phase,
			Target:       *target,
			TechniqueID:  *technique,
			Parameters:   map[string]string{"path": *path},
		}},
		Nonce:     *nonce,
		IssuedAt:  time.Now().Unix(),
		ExpiresAt: time.Now().Add(time.Duration(*ttl) * time.Second).Unix(),
		Rationale: reason,
	}
	encoded, err := value.Sign(priv)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	client, err := httpClient(*serverCert, *clientCert, *clientKey, *insecure)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	body, err := json.Marshal(map[string]any{
		"technique_id": *technique,
		"parameters":   map[string]string{"path": *path},
		"approval":     encoded,
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	request, err := http.NewRequest(http.MethodPost, strings.TrimRight(*broker, "/")+"/v1/actions", bytes.NewReader(body))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := client.Do(request)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer response.Body.Close()
	if _, err := io.Copy(os.Stdout, response.Body); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println()
}

func verifyCmd(args []string) {
	flags := flag.NewFlagSet("verify", flag.ExitOnError)
	file := flags.String("file", "/var/lib/redteam-broker/events.jsonl", "evidence JSONL file")
	head := flags.String("head", "", "head sidecar (defaults to head.json beside the file)")
	flags.Parse(args)

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

func httpClient(serverCert, clientCert, clientKey string, insecure bool) (*http.Client, error) {
	config := &tls.Config{
		MinVersion:         tls.VersionTLS13,
		InsecureSkipVerify: insecure,
	}
	if serverCert != "" {
		data, err := os.ReadFile(serverCert)
		if err != nil {
			return nil, err
		}
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM(data) {
			return nil, fmt.Errorf("server certificate is not PEM")
		}
		config.RootCAs = pool
	}
	if clientCert != "" && clientKey != "" {
		certificate, err := tls.LoadX509KeyPair(clientCert, clientKey)
		if err != nil {
			return nil, err
		}
		config.Certificates = []tls.Certificate{certificate}
	}
	return &http.Client{
		Transport: &http.Transport{TLSClientConfig: config},
		Timeout:   30 * time.Second,
	}, nil
}
