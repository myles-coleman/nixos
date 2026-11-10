package action

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
)

// Action is the typed unit of consent. It never carries a free-form command or
// URL: the technique ID and the target come from the signed catalog and scope.
type Action struct {
	EngagementID string            `json:"engagement_id"`
	ScopeVersion int               `json:"scope_version"`
	TechniqueID  string            `json:"technique_id"`
	Target       string            `json:"target"`
	Parameters   map[string]string `json:"parameters"`
}

// Canonical returns RFC 8785-compatible bytes for this fixed schema. All values
// are strings, integers, or maps of strings, and encoding/json sorts map keys,
// so the output matches JCS for this shape (no floats, no HTML escaping).
func (a Action) Canonical() ([]byte, error) {
	value := map[string]any{
		"engagement_id": a.EngagementID,
		"parameters":    a.Parameters,
		"scope_version": a.ScopeVersion,
		"target":        a.Target,
		"technique_id":  a.TechniqueID,
	}

	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte("\n")), nil
}

// Hash returns the SHA-256 of the canonical bytes.
func (a Action) Hash() (string, error) {
	canonical, err := a.Canonical()
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(canonical)
	return hex.EncodeToString(sum[:]), nil
}
