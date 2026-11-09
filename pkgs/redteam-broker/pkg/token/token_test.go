package token

import (
	"crypto/ed25519"
	"crypto/rand"
	"testing"
	"time"
)

func fixture(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey, AuthorizationDetail) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return pub, priv, AuthorizationDetail{
		Type:         "redteam_action",
		EngagementID: "stage1-demo",
		ScopeVersion: 1,
		Phase:        "recon",
		Target:       "10.99.0.2",
		TechniqueID:  "http.get",
		Parameters:   map[string]string{"path": "/ftp/"},
	}
}

func tokenFor(detail AuthorizationDetail) Token {
	return Token{
		AuthorizationDetails: []AuthorizationDetail{detail},
		Nonce:                "nonce-1",
		IssuedAt:             time.Now().Unix(),
		ExpiresAt:            time.Now().Add(10 * time.Minute).Unix(),
		Rationale:            "operator approved the directory-listing probe",
	}
}

func TestSignVerifyReplay(t *testing.T) {
	pub, priv, detail := fixture(t)
	encoded, err := tokenFor(detail).Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	used := map[string]bool{}
	if _, err := Verify(encoded, pub, detail, time.Now(), used); err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(encoded, pub, detail, time.Now(), used); err == nil {
		t.Fatal("expected replay rejection")
	}
}

func TestExpired(t *testing.T) {
	pub, priv, detail := fixture(t)
	value := tokenFor(detail)
	value.ExpiresAt = time.Now().Add(-time.Minute).Unix()
	encoded, err := value.Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(encoded, pub, detail, time.Now(), map[string]bool{}); err == nil {
		t.Fatal("expected expiry rejection")
	}
}

func TestBindingMismatch(t *testing.T) {
	pub, priv, detail := fixture(t)
	encoded, err := tokenFor(detail).Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	other := detail
	other.TechniqueID = "http.head"
	if _, err := Verify(encoded, pub, other, time.Now(), map[string]bool{}); err == nil {
		t.Fatal("expected binding rejection")
	}
}

func TestMissingRationale(t *testing.T) {
	pub, priv, detail := fixture(t)
	value := tokenFor(detail)
	value.Rationale = ""
	encoded, err := value.Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(encoded, pub, detail, time.Now(), map[string]bool{}); err == nil {
		t.Fatal("expected rationale rejection")
	}
}
