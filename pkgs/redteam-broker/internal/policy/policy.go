package policy

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"

	"github.com/open-policy-agent/opa/v1/rego"
)

//go:embed policy.rego
var module string

// Decision is the broker's single policy output. Pause is a distinct state: the
// action is neither allowed nor denied, and the operator must clarify the scope.
type Decision struct {
	Allow  bool   `json:"allow"`
	Pause  bool   `json:"pause,omitempty"`
	Reason string `json:"reason"`
}

// Input is the policy input. The maps mirror the signed scope and catalog
// documents; the broker fills Destination, NowNS, and Approval.
type Input struct {
	Action      map[string]any `json:"action"`
	Scope       map[string]any `json:"scope"`
	Catalog     map[string]any `json:"catalog"`
	Destination string         `json:"destination"`
	NowNS       int64          `json:"now_ns"`
	Approval    map[string]any `json:"approval"`
}

// Evaluate runs the embedded policy and returns a single decision.
func Evaluate(ctx context.Context, input Input) (Decision, error) {
	query, err := rego.New(
		rego.Query("data.redteam.decision"),
		rego.Module("policy.rego", module),
	).PrepareForEval(ctx)
	if err != nil {
		return Decision{}, fmt.Errorf("prepare policy: %w", err)
	}

	results, err := query.Eval(ctx, rego.EvalInput(input))
	if err != nil {
		return Decision{}, fmt.Errorf("evaluate policy: %w", err)
	}
	if len(results) == 0 || len(results[0].Expressions) == 0 {
		return Decision{Allow: false, Reason: "default_deny"}, nil
	}

	raw, err := json.Marshal(results[0].Expressions[0].Value)
	if err != nil {
		return Decision{}, fmt.Errorf("marshal decision: %w", err)
	}
	var decision Decision
	if err := json.Unmarshal(raw, &decision); err != nil {
		return Decision{}, fmt.Errorf("decode decision: %w", err)
	}
	return decision, nil
}
