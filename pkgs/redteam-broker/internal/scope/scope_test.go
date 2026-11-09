package scope

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeSignedScope(t *testing.T, body string) (string, string, string) {
	t.Helper()
	dir := t.TempDir()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}

	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		t.Fatal(err)
	}
	pubPath := filepath.Join(dir, "scope.pub")
	if err := os.WriteFile(pubPath, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}), 0o644); err != nil {
		t.Fatal(err)
	}

	scopePath := filepath.Join(dir, "scope.yaml")
	if err := os.WriteFile(scopePath, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	sigPath := filepath.Join(dir, "scope.yaml.sig")
	if err := os.WriteFile(sigPath, ed25519.Sign(priv, []byte(body)), 0o644); err != nil {
		t.Fatal(err)
	}
	return scopePath, sigPath, pubPath
}

const validScope = `engagement_id: stage1-demo
version: 2
not_before: 2026-01-01T00:00:00Z
not_after: 2027-01-01T00:00:00Z
target: 10.99.0.2
lab_cidrs:
  - 10.99.0.0/24
allowed_classes:
  - recon
  - scan
catalog_version: 1
hard_deny:
  - 10.0.0.0/24
  - 10.43.0.0/16
  - 10.42.0.0/16
  - 169.254.169.254/32
  - 127.0.0.0/8
  - 10.99.0.1/32
`

func TestLoadAndValidate(t *testing.T) {
	scopePath, sigPath, pubPath := writeSignedScope(t, validScope)
	s, err := Load(scopePath, sigPath, pubPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Validate(time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC), 1); err != nil {
		t.Fatal(err)
	}
}

func TestRollbackRejected(t *testing.T) {
	scopePath, sigPath, pubPath := writeSignedScope(t, validScope)
	s, err := Load(scopePath, sigPath, pubPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Validate(time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC), 3); err == nil {
		t.Fatal("expected rollback rejection")
	}
	// Re-accepting the same signed version on a restart is idempotent.
	if err := s.Validate(time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC), 2); err != nil {
		t.Fatalf("same version should be accepted: %v", err)
	}
}

func TestTamperedScopeRejected(t *testing.T) {
	scopePath, sigPath, pubPath := writeSignedScope(t, validScope)
	if err := os.WriteFile(scopePath, []byte(validScope+"# tampered\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(scopePath, sigPath, pubPath); err == nil {
		t.Fatal("expected signature rejection")
	}
}
