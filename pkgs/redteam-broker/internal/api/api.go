package api

import (
	"crypto/ed25519"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/action"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/catalog"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/policy"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/proxy"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/internal/scope"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/evidence"
	"github.com/myles-coleman/nixos/pkgs/redteam-broker/pkg/token"
)

// Server is the broker's control plane. It holds the signed scope and catalog,
// verifies approvals, evaluates policy, and calls the lab proxy.
type Server struct {
	Scope        *scope.Scope
	Catalog      *catalog.Catalog
	ApprovalPub  ed25519.PublicKey
	ProxySocket  string
	TargetScheme string
	TargetPort   int
	Emitter      evidence.Emitter
	Now          func() time.Time

	used map[string]bool
	mu   sync.Mutex
}

type request struct {
	TechniqueID string            `json:"technique_id"`
	Parameters  map[string]string `json:"parameters"`
	Approval    string            `json:"approval"`
}

type response struct {
	Decision   policy.Decision `json:"decision"`
	ActionHash string          `json:"action_hash,omitempty"`
	Result     *proxy.Response `json:"result,omitempty"`
}

// New creates a server with the Stage 1 defaults.
func New(s *scope.Scope, c *catalog.Catalog, approvalPub ed25519.PublicKey, proxySocket string, emitter evidence.Emitter) *Server {
	return &Server{
		Scope:        s,
		Catalog:      c,
		ApprovalPub:  approvalPub,
		ProxySocket:  proxySocket,
		TargetScheme: "http",
		TargetPort:   3000,
		Emitter:      emitter,
		Now:          time.Now,
		used:         map[string]bool{},
	}
}

// Handler returns the HTTP handler. It is mounted behind TLS in production.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/actions", s.handleAction)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})
	return mux
}

func (s *Server) handleAction(w http.ResponseWriter, r *http.Request) {
	var req request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, response{Decision: policy.Decision{Reason: "bad_request"}})
		return
	}

	technique, known := s.Catalog.Find(req.TechniqueID)
	if !known {
		s.record("", req, policy.Decision{Reason: "unknown_technique"}, "", "")
		writeJSON(w, http.StatusForbidden, response{Decision: policy.Decision{Reason: "unknown_technique"}})
		return
	}

	if req.Parameters == nil {
		req.Parameters = map[string]string{}
	}
	path, ok := req.Parameters["path"]
	if !ok || !strings.HasPrefix(path, "/") || strings.Contains(path, "://") {
		writeJSON(w, http.StatusBadRequest, response{Decision: policy.Decision{Reason: "bad_parameters"}})
		return
	}

	act := action.Action{
		EngagementID: s.Scope.EngagementID,
		ScopeVersion: s.Scope.Version,
		TechniqueID:  req.TechniqueID,
		Target:       s.Scope.Target,
		Parameters:   req.Parameters,
	}
	hash, err := act.Hash()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, response{Decision: policy.Decision{Reason: "hash_error"}})
		return
	}

	detail := token.AuthorizationDetail{
		Type:         "redteam_action",
		EngagementID: s.Scope.EngagementID,
		ScopeVersion: s.Scope.Version,
		Phase:        "recon",
		Target:       s.Scope.Target,
		TechniqueID:  req.TechniqueID,
		Parameters:   req.Parameters,
	}
	s.mu.Lock()
	approved, approvalErr := token.Verify(req.Approval, s.ApprovalPub, detail, s.Now(), s.used)
	s.mu.Unlock()

	input := policy.Input{
		Action:      toMap(act),
		Scope:       toMap(s.Scope),
		Catalog:     toMap(s.Catalog),
		Destination: s.Scope.Target,
		NowNS:       s.Now().UnixNano(),
		Approval:    map[string]any{"valid": approvalErr == nil},
	}
	decision, err := policy.Evaluate(r.Context(), input)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, response{Decision: policy.Decision{Reason: "policy_error"}})
		return
	}

	nonce := ""
	rationale := ""
	if approvalErr == nil {
		nonce = approved.Nonce
		rationale = approved.Rationale
	}
	s.record(hash, req, decision, nonce, rationale)

	if !decision.Allow {
		writeJSON(w, http.StatusForbidden, response{Decision: decision, ActionHash: hash})
		return
	}

	result, err := proxy.Do(s.ProxySocket, proxy.Request{
		Scheme:       s.TargetScheme,
		Host:         s.Scope.Target,
		Port:         s.TargetPort,
		Method:       technique.Method,
		Path:         path,
		AllowedCIDRs: s.Scope.LabCIDRs,
		MaxBytes:     1 << 20,
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, response{Decision: decision, ActionHash: hash})
		return
	}
	writeJSON(w, http.StatusOK, response{Decision: decision, ActionHash: hash, Result: &result})
}

func (s *Server) record(hash string, req request, decision policy.Decision, nonce, rationale string) {
	if s.Emitter == nil {
		return
	}
	_ = s.Emitter.Emit(evidence.Event{
		ActionHash:   hash,
		ScopeVersion: s.Scope.Version,
		TechniqueID:  req.TechniqueID,
		Decision:     map[bool]string{true: "allow", false: "deny"}[decision.Allow],
		Reason:       decision.Reason,
		Destination:  s.Scope.Target,
		Nonce:        nonce,
		Rationale:    rationale,
	})
}

func toMap(value any) map[string]any {
	data, err := json.Marshal(value)
	if err != nil {
		return map[string]any{}
	}
	var result map[string]any
	if err := json.Unmarshal(data, &result); err != nil {
		return map[string]any{}
	}
	return result
}

func writeJSON(w http.ResponseWriter, status int, value response) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

// Decode is a small helper for the CLI and tests; it lives here so the token
// shape has one definition.
func Decode(encoded string) (token.Token, error) {
	return token.Decode(encoded)
}
