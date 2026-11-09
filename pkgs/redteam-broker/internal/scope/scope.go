package scope

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// Scope is the signed, immutable engagement scope. The signature is detached
// and covers the exact file bytes, so the compiler cannot accept a re-serialized
// copy with different semantics.
type Scope struct {
	EngagementID   string   `yaml:"engagement_id" json:"engagement_id"`
	Version        int      `yaml:"version" json:"version"`
	NotBefore      string   `yaml:"not_before" json:"not_before"`
	NotAfter       string   `yaml:"not_after" json:"not_after"`
	Target         string   `yaml:"target" json:"target"`
	LabCIDRs       []string `yaml:"lab_cidrs" json:"lab_cidrs"`
	AllowedClasses []string `yaml:"allowed_classes" json:"allowed_classes"`
	CatalogVersion int      `yaml:"catalog_version" json:"catalog_version"`
	HardDeny       []string `yaml:"hard_deny" json:"hard_deny"`
}

// Load verifies the detached signature, then parses the scope.
func Load(path, sigPath, pubPath string) (*Scope, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read scope: %w", err)
	}
	if err := Verify(data, sigPath, pubPath); err != nil {
		return nil, err
	}

	var s Scope
	if err := yaml.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("parse scope: %w", err)
	}
	return &s, nil
}

// Verify checks a detached Ed25519 signature over data.
func Verify(data []byte, sigPath, pubPath string) error {
	sig, err := os.ReadFile(sigPath)
	if err != nil {
		return fmt.Errorf("read signature: %w", err)
	}
	pub, err := LoadPublicKey(pubPath)
	if err != nil {
		return err
	}
	if !ed25519.Verify(pub, data, sig) {
		return fmt.Errorf("signature verification failed")
	}
	return nil
}

// LoadPublicKey reads a PKIX PEM-encoded Ed25519 public key.
func LoadPublicKey(path string) (ed25519.PublicKey, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read public key: %w", err)
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("public key is not PEM")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}
	pub, ok := key.(ed25519.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public key is not Ed25519")
	}
	return pub, nil
}

// Validate rejects a scope that is outside its window or not newer than the
// last accepted version. Rollback is a rejection, not a warning.
func (s *Scope) Validate(now time.Time, lastVersion int) error {
	if s.Version < lastVersion {
		return fmt.Errorf("scope rollback rejected: version %d < last accepted %d", s.Version, lastVersion)
	}
	notBefore, err := time.Parse(time.RFC3339, s.NotBefore)
	if err != nil {
		return fmt.Errorf("parse not_before: %w", err)
	}
	notAfter, err := time.Parse(time.RFC3339, s.NotAfter)
	if err != nil {
		return fmt.Errorf("parse not_after: %w", err)
	}
	if now.Before(notBefore) || now.After(notAfter) {
		return fmt.Errorf("scope outside its window")
	}
	if s.Target == "" {
		return fmt.Errorf("scope has no target")
	}
	if len(s.LabCIDRs) == 0 {
		return fmt.Errorf("scope has no lab CIDRs")
	}
	return nil
}
