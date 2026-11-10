package token

import (
	"bytes"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"time"
)

// AuthorizationDetail follows RFC 9396's typed `authorization_details` shape.
// Stage 1 has one detail per token; Stage 3 can carry several.
type AuthorizationDetail struct {
	Type         string            `json:"type"`
	EngagementID string            `json:"engagement_id"`
	ScopeVersion int               `json:"scope_version"`
	Phase        string            `json:"phase"`
	Target       string            `json:"target"`
	TechniqueID  string            `json:"technique_id"`
	Parameters   map[string]string `json:"parameters"`
}

// Token is the single-use approval. The signature covers the canonical token
// without the signature field.
type Token struct {
	AuthorizationDetails []AuthorizationDetail `json:"authorization_details"`
	Nonce                string                `json:"nonce"`
	IssuedAt             int64                 `json:"issued_at"`
	ExpiresAt            int64                 `json:"expires_at"`
	Rationale            string                `json:"rationale"`
	Signature            string                `json:"signature,omitempty"`
}

func detailMap(detail AuthorizationDetail) map[string]any {
	return map[string]any{
		"engagement_id": detail.EngagementID,
		"parameters":    detail.Parameters,
		"phase":         detail.Phase,
		"scope_version": detail.ScopeVersion,
		"target":        detail.Target,
		"technique_id":  detail.TechniqueID,
		"type":          detail.Type,
	}
}

func (t Token) canonical() ([]byte, error) {
	details := make([]any, len(t.AuthorizationDetails))
	for index, detail := range t.AuthorizationDetails {
		details[index] = detailMap(detail)
	}
	value := map[string]any{
		"authorization_details": details,
		"expires_at":            t.ExpiresAt,
		"issued_at":             t.IssuedAt,
		"nonce":                 t.Nonce,
		"rationale":             t.Rationale,
	}

	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// Sign returns the base64 token. The caller sets the detail, nonce, and expiry.
func (t Token) Sign(priv ed25519.PrivateKey) (string, error) {
	canonical, err := t.canonical()
	if err != nil {
		return "", err
	}
	t.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(priv, canonical))
	raw, err := json.Marshal(t)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(raw), nil
}

// Decode parses a token without verifying it.
func Decode(encoded string) (Token, error) {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return Token{}, fmt.Errorf("decode token: %w", err)
	}
	var value Token
	if err := json.Unmarshal(raw, &value); err != nil {
		return Token{}, fmt.Errorf("parse token: %w", err)
	}
	return value, nil
}

// Verify checks the signature, expiry, rationale, binding, and replay. The
// caller owns the used-nonce map and must serialize access to it.
func Verify(encoded string, pub ed25519.PublicKey, want AuthorizationDetail, now time.Time, used map[string]bool) (Token, error) {
	value, err := Decode(encoded)
	if err != nil {
		return Token{}, err
	}
	signature, err := base64.StdEncoding.DecodeString(value.Signature)
	if err != nil {
		return Token{}, fmt.Errorf("decode signature: %w", err)
	}
	canonical, err := value.canonical()
	if err != nil {
		return Token{}, fmt.Errorf("canonicalize token: %w", err)
	}
	if !ed25519.Verify(pub, canonical, signature) {
		return Token{}, fmt.Errorf("approval signature is invalid")
	}
	if value.ExpiresAt <= now.Unix() {
		return Token{}, fmt.Errorf("approval is expired")
	}
	if value.Rationale == "" {
		return Token{}, fmt.Errorf("approval has no rationale")
	}
	if len(value.AuthorizationDetails) != 1 {
		return Token{}, fmt.Errorf("approval must carry exactly one authorization detail")
	}
	got := value.AuthorizationDetails[0]
	if got.Type != want.Type ||
		got.EngagementID != want.EngagementID ||
		got.ScopeVersion != want.ScopeVersion ||
		got.Target != want.Target ||
		got.TechniqueID != want.TechniqueID {
		return Token{}, fmt.Errorf("approval is bound to a different action")
	}
	if got.Phase == "" {
		return Token{}, fmt.Errorf("approval has no phase")
	}
	if len(got.Parameters) != len(want.Parameters) {
		return Token{}, fmt.Errorf("approval parameters do not match")
	}
	for key, parameter := range want.Parameters {
		if got.Parameters[key] != parameter {
			return Token{}, fmt.Errorf("approval parameters do not match")
		}
	}
	if value.Nonce == "" {
		return Token{}, fmt.Errorf("approval has no nonce")
	}
	if used[value.Nonce] {
		return Token{}, fmt.Errorf("approval replay rejected")
	}
	used[value.Nonce] = true
	return value, nil
}

// LoadPrivateKey reads a PKCS8 PEM-encoded Ed25519 private key.
func LoadPrivateKey(path string) (ed25519.PrivateKey, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read private key: %w", err)
	}
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, fmt.Errorf("private key is not PEM")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse private key: %w", err)
	}
	priv, ok := key.(ed25519.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("private key is not Ed25519")
	}
	return priv, nil
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
