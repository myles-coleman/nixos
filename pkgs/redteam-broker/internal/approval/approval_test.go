package approval

import (
	"crypto/ed25519"
	"crypto/rand"
	"testing"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/action"
)

func fixture(t *testing.T) (ed25519.PublicKey, ed25519.PrivateKey, action.Action) {
	t.Helper()
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	act := action.Action{
		EngagementID: "stage1-demo",
		ScopeVersion: 1,
		TechniqueID:  "http.get",
		Target:       "10.99.0.2",
		Parameters:   map[string]string{"path": "/ftp/"},
	}
	return pub, priv, act
}

func claimsFor(act action.Action) Claims {
	return Claims{
		EngagementID: act.EngagementID,
		ScopeVersion: act.ScopeVersion,
		TechniqueID:  act.TechniqueID,
		Target:       act.Target,
		Parameters:   act.Parameters,
		Nonce:        "nonce-1",
		ExpiresAt:    time.Now().Add(10 * time.Minute).Unix(),
	}
}

func TestVerifyAndReplay(t *testing.T) {
	pub, priv, act := fixture(t)
	token, err := claimsFor(act).Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	used := map[string]bool{}
	if err := Verify(token, pub, act, time.Now(), used); err != nil {
		t.Fatal(err)
	}
	if err := Verify(token, pub, act, time.Now(), used); err == nil {
		t.Fatal("expected replay rejection")
	}
}

func TestExpired(t *testing.T) {
	pub, priv, act := fixture(t)
	claims := claimsFor(act)
	claims.ExpiresAt = time.Now().Add(-time.Minute).Unix()
	token, err := claims.Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	if err := Verify(token, pub, act, time.Now(), map[string]bool{}); err == nil {
		t.Fatal("expected expiry rejection")
	}
}

func TestBindingMismatch(t *testing.T) {
	pub, priv, act := fixture(t)
	token, err := claimsFor(act).Sign(priv)
	if err != nil {
		t.Fatal(err)
	}
	act.TechniqueID = "http.head"
	if err := Verify(token, pub, act, time.Now(), map[string]bool{}); err == nil {
		t.Fatal("expected binding rejection")
	}
}
