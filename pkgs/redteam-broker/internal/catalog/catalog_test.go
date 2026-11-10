package catalog

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
)

func writeSignedCatalog(t *testing.T, body string) (string, string, string) {
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
	pubPath := filepath.Join(dir, "catalog.pub")
	if err := os.WriteFile(pubPath, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}), 0o644); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "techniques.json")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	sigPath := filepath.Join(dir, "techniques.json.sig")
	if err := os.WriteFile(sigPath, ed25519.Sign(priv, []byte(body)), 0o644); err != nil {
		t.Fatal(err)
	}
	return path, sigPath, pubPath
}

const validCatalog = `{"version":1,"techniques":[{"id":"http.get","class":"recon","method":"GET","description":"GET a path"}]}`

func TestLoadAndFind(t *testing.T) {
	path, sigPath, pubPath := writeSignedCatalog(t, validCatalog)
	c, err := Load(path, sigPath, pubPath)
	if err != nil {
		t.Fatal(err)
	}
	technique, ok := c.Find("http.get")
	if !ok || technique.Class != "recon" {
		t.Fatalf("unexpected technique: %+v ok=%v", technique, ok)

	}
	if _, ok := c.Find("shell.exec"); ok {
		t.Fatal("unknown technique was found")
	}
}

func TestTamperedCatalogRejected(t *testing.T) {
	path, sigPath, pubPath := writeSignedCatalog(t, validCatalog)
	if err := os.WriteFile(path, []byte(validCatalog+" "), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path, sigPath, pubPath); err == nil {
		t.Fatal("expected signature rejection")
	}
}
