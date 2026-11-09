package approval

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/action"
)

// Claims is the Stage 1 approval token. It binds the exact action, a nonce, and
// an expiry. Stage 3 reuses this shape in the host approval service.
type Claims struct {
	EngagementID string            `json:"engagement_id"`
	ScopeVersion int               `json:"scope_version"`
	TechniqueID  string            `json:"technique_id"`
	Target       string            `json:"target"`
	Parameters   map[string]string `json:"parameters"`
	Nonce        string            `json:"nonce"`
	ExpiresAt    int64             `json:"expires_at"`
	Signature    string            `json:"signature,omitempty"`
}

func (c Claims) canonical() ([]byte, error) {
	value := map[string]any{
		"engagement_id": c.EngagementID,
		"expires_at":    c.ExpiresAt,
		"nonce":         c.Nonce,
		"parameters":    c.Parameters,
		"scope_version": c.ScopeVersion,
		"target":        c.Target,
		"technique_id":  c.TechniqueID,
	}
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// Sign returns a base64 token carrying the claims and a detached signature over
// the canonical claims.
func (c Claims) Sign(priv ed25519.PrivateKey) (string, error) {
	canonical, err := c.canonical()
	if err != nil {
		return "", err
	}
	c.Signature = base64.StdEncoding.EncodeToString(ed25519.Sign(priv, canonical))
	raw, err := json.Marshal(c)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(raw), nil
}

// Decode parses a token without verifying it. Callers must verify separately.
func Decode(token string) (Claims, error) {
	raw, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return Claims{}, fmt.Errorf("decode token: %w", err)
	}
	var claims Claims
	if err := json.Unmarshal(raw, &claims); err != nil {
		return Claims{}, fmt.Errorf("parse token: %w", err)
	}
	return claims, nil
}

// Verify checks the signature, expiry, binding, and replay, and records the
// nonce. The caller owns the used-nonce map and must serialize access to it.
func Verify(token string, pub ed25519.PublicKey, act action.Action, now time.Time, used map[string]bool) error {
	raw, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return fmt.Errorf("decode token: %w", err)
	}
	var c Claims
	if err := json.Unmarshal(raw, &c); err != nil {
		return fmt.Errorf("parse token: %w", err)
	}
	sig, err := base64.StdEncoding.DecodeString(c.Signature)
	if err != nil {
		return fmt.Errorf("decode signature: %w", err)
	}
	canonical, err := c.canonical()
	if err != nil {
		return fmt.Errorf("canonicalize claims: %w", err)
	}
	if !ed25519.Verify(pub, canonical, sig) {
		return fmt.Errorf("approval signature is invalid")
	}
	if c.ExpiresAt <= now.Unix() {
		return fmt.Errorf("approval is expired")
	}
	if c.EngagementID != act.EngagementID ||
		c.ScopeVersion != act.ScopeVersion ||
		c.TechniqueID != act.TechniqueID ||
		c.Target != act.Target {
		return fmt.Errorf("approval is bound to a different action")
	}
	if len(c.Parameters) != len(act.Parameters) {
		return fmt.Errorf("approval parameters do not match")
	}
	for key, value := range act.Parameters {
		if c.Parameters[key] != value {
			return fmt.Errorf("approval parameters do not match")
		}
	}
	if c.Nonce == "" {
		return fmt.Errorf("approval has no nonce")
	}
	if used[c.Nonce] {
		return fmt.Errorf("approval replay rejected")
	}
	used[c.Nonce] = true
	return nil
}
