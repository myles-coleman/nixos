package main

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/api"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/catalog"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/proxy"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/scope"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/evidence"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/token"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "serve":
		serve(os.Args[2:])
	case "proxy":
		proxyCmd(os.Args[2:])
	default:
		usage()
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: redteam-broker <serve|proxy> [flags]")
	os.Exit(2)
}

func serve(args []string) {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	scopePath := flags.String("scope", "/etc/redteam/scope.yaml", "signed scope file")
	scopeSig := flags.String("scope-sig", "/etc/redteam/scope.yaml.sig", "detached scope signature")
	catalogPath := flags.String("catalog", "/etc/redteam/techniques.json", "signed technique catalog")
	catalogSig := flags.String("catalog-sig", "/etc/redteam/techniques.json.sig", "detached catalog signature")
	scopePub := flags.String("scope-pub", "/etc/redteam/scope.pub", "scope/catalog Ed25519 public key")
	approvalPub := flags.String("approval-pub", "/etc/redteam/approval.pub", "approval Ed25519 public key")
	proxySocket := flags.String("proxy-socket", "/run/redteam/proxy.sock", "lab proxy Unix socket")
	addr := flags.String("addr", "10.0.0.151:8443", "control listen address")
	stateDir := flags.String("state-dir", "/var/lib/redteam-broker", "state directory")
	tlsCert := flags.String("tls-cert", "", "server certificate (optional)")
	tlsKey := flags.String("tls-key", "", "server key (optional)")
	clientCA := flags.String("client-ca", "", "client CA bundle (optional, enables mTLS)")
	flags.Parse(args)

	s, err := scope.Load(*scopePath, *scopeSig, *scopePub)
	if err != nil {
		log.Fatalf("load scope: %v", err)
	}
	if err := os.MkdirAll(*stateDir, 0o755); err != nil {
		log.Fatalf("state dir: %v", err)
	}
	last := readVersion(*stateDir)
	if err := s.Validate(time.Now(), last); err != nil {
		log.Fatalf("validate scope: %v", err)
	}
	if err := writeVersion(*stateDir, s.Version); err != nil {
		log.Fatalf("record scope version: %v", err)
	}

	c, err := catalog.Load(*catalogPath, *catalogSig, *scopePub)
	if err != nil {
		log.Fatalf("load catalog: %v", err)
	}
	approvalKey, err := token.LoadPublicKey(*approvalPub)
	if err != nil {
		log.Fatalf("load approval key: %v", err)
	}

	emitter, err := evidence.Open(
		filepath.Join(*stateDir, "events.jsonl"),
		filepath.Join(*stateDir, "head.json"),
	)
	if err != nil {
		log.Fatalf("open evidence chain: %v", err)
	}
	server := api.New(s, c, approvalKey, *proxySocket, emitter)
	server.ScopeDigest, err = sha256File(*scopePath)
	if err != nil {
		log.Fatalf("hash scope: %v", err)
	}
	server.CatalogDigest, err = sha256File(*catalogPath)
	if err != nil {
		log.Fatalf("hash catalog: %v", err)
	}

	httpServer := &http.Server{
		Addr:              *addr,
		Handler:           server.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	if *tlsCert != "" && *tlsKey != "" {
		config := &tls.Config{MinVersion: tls.VersionTLS13}
		if *clientCA != "" {
			caData, err := os.ReadFile(*clientCA)
			if err != nil {
				log.Fatalf("read client CA: %v", err)
			}
			pool := x509.NewCertPool()
			if !pool.AppendCertsFromPEM(caData) {
				log.Fatal("client CA bundle is empty")
			}
			config.ClientCAs = pool
			config.ClientAuth = tls.RequireAndVerifyClientCert
		}
		httpServer.TLSConfig = config
		log.Printf("redteam-broker listening on %s (TLS)", *addr)
		log.Fatal(httpServer.ListenAndServeTLS(*tlsCert, *tlsKey))
	}

	log.Printf("redteam-broker listening on %s", *addr)
	log.Fatal(httpServer.ListenAndServe())
}

func proxyCmd(args []string) {
	flags := flag.NewFlagSet("proxy", flag.ExitOnError)
	socket := flags.String("socket", "/run/redteam/proxy.sock", "Unix socket to listen on")
	flags.Parse(args)
	log.Printf("redteam-proxy listening on %s", *socket)
	log.Fatal(proxy.Serve(*socket))
}

func readVersion(dir string) int {
	data, err := os.ReadFile(filepath.Join(dir, "scope.version"))
	if err != nil {
		return 0
	}
	version, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0
	}
	return version
}

func writeVersion(dir string, version int) error {
	return os.WriteFile(filepath.Join(dir, "scope.version"), []byte(strconv.Itoa(version)), 0o644)
}

func sha256File(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}
