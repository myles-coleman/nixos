package catalog

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/scope"
)

// Technique is one entry in the signed technique catalog.
type Technique struct {
	ID          string `json:"id"`
	Class       string `json:"class"`
	Method      string `json:"method"`
	Description string `json:"description"`
}

// Catalog is the signed set of techniques the broker may execute.
type Catalog struct {
	Version    int         `json:"version"`
	Techniques []Technique `json:"techniques"`
}

// Load verifies the detached signature, then parses the catalog.
func Load(path, sigPath, pubPath string) (*Catalog, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read catalog: %w", err)
	}
	if err := scope.Verify(data, sigPath, pubPath); err != nil {
		return nil, err
	}

	var c Catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parse catalog: %w", err)
	}
	if c.Version == 0 || len(c.Techniques) == 0 {
		return nil, fmt.Errorf("catalog is empty or unversioned")
	}
	return &c, nil
}

// Find returns a technique by ID. An unknown technique is a deny, not a default.
func (c *Catalog) Find(id string) (Technique, bool) {
	for _, technique := range c.Techniques {
		if technique.ID == id {
			return technique, true
		}
	}
	return Technique{}, false
}
