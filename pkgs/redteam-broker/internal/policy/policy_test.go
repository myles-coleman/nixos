package policy

import (
	"context"
	"testing"
	"time"
)

func baseInput() Input {
	return Input{
		Action: map[string]any{
			"engagement_id": "stage1-demo",
			"scope_version": 1,
			"technique_id":  "http.get",
			"target":        "10.99.0.2",
			"parameters":    map[string]any{"path": "/ftp/"},
		},
		Scope: map[string]any{
			"engagement_id":   "stage1-demo",
			"version":         1,
			"not_before":      "2026-01-01T00:00:00Z",
			"not_after":       "2027-01-01T00:00:00Z",
			"target":             "10.99.0.2",
			"target_criticality": "high",
			"target_digest":      "sha256:test",
			"lab_cidrs":          []any{"10.99.0.0/24"},
			"allowed_classes": []any{"recon", "scan"},
			"catalog_version": 1,
			"hard_deny": []any{
				"10.0.0.0/24", "10.43.0.0/16", "10.42.0.0/16",
				"169.254.169.254/32", "127.0.0.0/8", "10.99.0.1/32",
			},
		},
		Catalog: map[string]any{
			"version": 1,
			"techniques": []any{
				map[string]any{"id": "http.get", "class": "recon"},
			},
		},
		Destination: "10.99.0.2",
		NowNS:       time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC).UnixNano(),
		Approval:    map[string]any{"valid": true},
	}
}

func evaluate(t *testing.T, input Input) Decision {
	t.Helper()
	decision, err := Evaluate(context.Background(), input)
	if err != nil {
		t.Fatal(err)
	}
	return decision
}

func TestAllow(t *testing.T) {
	decision := evaluate(t, baseInput())
	if !decision.Allow || decision.Reason != "allowed" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestHardDenyWins(t *testing.T) {
	input := baseInput()
	input.Destination = "169.254.169.254"
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "hard_deny" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestUnknownTechnique(t *testing.T) {
	input := baseInput()
	input.Action["technique_id"] = "shell.exec"
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "unknown_technique" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestClassNotAllowed(t *testing.T) {
	input := baseInput()
	input.Scope["allowed_classes"] = []any{"recon"}
	input.Catalog["techniques"] = []any{
		map[string]any{"id": "http.get", "class": "exploit"},
	}
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "class_not_allowed" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestOutOfWindow(t *testing.T) {
	input := baseInput()
	input.NowNS = time.Date(2028, 1, 1, 0, 0, 0, 0, time.UTC).UnixNano()
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "out_of_window" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestOutOfScope(t *testing.T) {
	input := baseInput()
	input.Destination = "192.168.1.10"
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "out_of_scope" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestPauseOnUnknownCriticality(t *testing.T) {
	input := baseInput()
	input.Scope["target_criticality"] = "unknown"
	decision := evaluate(t, input)
	if decision.Allow || !decision.Pause || decision.Reason != "pause" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}

func TestApprovalRequired(t *testing.T) {
	input := baseInput()
	input.Approval = map[string]any{"valid": false}
	decision := evaluate(t, input)
	if decision.Allow || decision.Reason != "approval_required" {
		t.Fatalf("unexpected decision: %+v", decision)
	}
}
