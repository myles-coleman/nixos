package api

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/action"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/approval"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/catalog"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/evidence"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/proxy"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/scope"
)

type fixture struct {
	server *Server
	pub    ed25519.PublicKey
	priv   ed25519.PrivateKey
	host   string
	port   int
}

func newFixture(t *testing.T, target string, hardDeny []string) fixture {
	t.Helper()
	targetServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("target-ok"))
	}))
	t.Cleanup(targetServer.Close)
	host, portText, _ := net.SplitHostPort(targetServer.Listener.Addr().String())
	port, _ := strconv.Atoi(portText)

	socket := filepath.Join(t.TempDir(), "proxy.sock")
	go func() { _ = proxy.Serve(socket) }()
	for i := 0; i < 50; i++ {
		if _, err := net.Dial("unix", socket); err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}

	sc := &scope.Scope{
		EngagementID:   "stage1-demo",
		Version:        1,
		NotBefore:      "2026-01-01T00:00:00Z",
		NotAfter:       "2027-01-01T00:00:00Z",
		Target:         target,
		LabCIDRs:       []string{"127.0.0.0/8"},
		AllowedClasses: []string{"recon"},
		CatalogVersion: 1,
		HardDeny:       hardDeny,
	}
	cat := &catalog.Catalog{
		Version: 1,
		Techniques: []catalog.Technique{
			{ID: "http.get", Class: "recon", Method: "GET"},
		},
	}
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	server := New(sc, cat, pub, socket, evidence.Noop{})
	server.TargetPort = port
	server.Now = func() time.Time { return time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC) }
	return fixture{server: server, pub: pub, priv: priv, host: host, port: port}
}

func (f fixture) token(t *testing.T, technique string, parameters map[string]string, nonce string, expires time.Time) string {
	t.Helper()
	claims := approval.Claims{
		EngagementID: "stage1-demo",
		ScopeVersion: 1,
		TechniqueID:  technique,
		Target:       f.server.Scope.Target,
		Parameters:   parameters,
		Nonce:        nonce,
		ExpiresAt:    expires.Unix(),
	}
	token, err := claims.Sign(f.priv)
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func (f fixture) post(t *testing.T, technique string, parameters map[string]string, token string) *httptest.ResponseRecorder {
	t.Helper()
	body := fmt.Sprintf(`{"technique_id":%q,"parameters":{"path":%q},"approval":%q}`, technique, parameters["path"], token)
	request := httptest.NewRequest(http.MethodPost, "/v1/actions", strings.NewReader(body))
	recorder := httptest.NewRecorder()
	f.server.Handler().ServeHTTP(recorder, request)
	return recorder
}

func TestAllow(t *testing.T) {
	f := newFixture(t, "127.0.0.1", []string{"10.0.0.0/24"})
	token := f.token(t, "http.get", map[string]string{"path": "/"}, "nonce-allow", time.Now().Add(time.Minute))
	recorder := f.post(t, "http.get", map[string]string{"path": "/"}, token)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	if !strings.Contains(recorder.Body.String(), "target-ok") {
		t.Fatalf("unexpected body: %s", recorder.Body.String())
	}
}

func TestReplayRejected(t *testing.T) {
	f := newFixture(t, "127.0.0.1", []string{"10.0.0.0/24"})
	token := f.token(t, "http.get", map[string]string{"path": "/"}, "nonce-replay", time.Now().Add(time.Minute))
	if recorder := f.post(t, "http.get", map[string]string{"path": "/"}, token); recorder.Code != http.StatusOK {
		t.Fatalf("first request failed: %d", recorder.Code)
	}
	recorder := f.post(t, "http.get", map[string]string{"path": "/"}, token)
	if recorder.Code != http.StatusForbidden || !strings.Contains(recorder.Body.String(), "approval_required") {
		t.Fatalf("replay was not rejected: %d %s", recorder.Code, recorder.Body.String())
	}
}

func TestUnknownTechniqueRejected(t *testing.T) {
	f := newFixture(t, "127.0.0.1", []string{"10.0.0.0/24"})
	token := f.token(t, "shell.exec", map[string]string{"path": "/"}, "nonce-unknown", time.Now().Add(time.Minute))
	recorder := f.post(t, "shell.exec", map[string]string{"path": "/"}, token)
	if recorder.Code != http.StatusForbidden || !strings.Contains(recorder.Body.String(), "unknown_technique") {
		t.Fatalf("unknown technique was not rejected: %d %s", recorder.Code, recorder.Body.String())
	}
}

func TestHardDenyRejected(t *testing.T) {
	f := newFixture(t, "10.0.0.5", []string{"10.0.0.0/24"})
	token := f.token(t, "http.get", map[string]string{"path": "/"}, "nonce-hard", time.Now().Add(time.Minute))
	recorder := f.post(t, "http.get", map[string]string{"path": "/"}, token)
	if recorder.Code != http.StatusForbidden || !strings.Contains(recorder.Body.String(), "hard_deny") {
		t.Fatalf("hard deny was not applied: %d %s", recorder.Code, recorder.Body.String())
	}
}

func TestFreeFormRejected(t *testing.T) {
	f := newFixture(t, "127.0.0.1", []string{"10.0.0.0/24"})
	token := f.token(t, "http.get", map[string]string{"path": "http://evil.example/"}, "nonce-free", time.Now().Add(time.Minute))
	recorder := f.post(t, "http.get", map[string]string{"path": "http://evil.example/"}, token)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("free-form path was not rejected: %d %s", recorder.Code, recorder.Body.String())
	}
}

var _ = action.Action{}
