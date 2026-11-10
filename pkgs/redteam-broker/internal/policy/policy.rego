package redteam

import future.keywords.if
import future.keywords.in

default decision := {"allow": false, "reason": "default_deny"}

# The order is the security order: hard denies first, then unknown/unknown-class
# input, then the time window, then scope, then approval. The final branch is
# the only allow.
decision := {"allow": false, "reason": "hard_deny"} if {
	hard_denied
} else := {"allow": false, "reason": "unknown_technique"} if {
	not technique_known
} else := {"allow": false, "reason": "class_not_allowed"} if {
	not class_allowed
} else := {"allow": false, "pause": true, "reason": "pause"} if {
	not criticality_known
} else := {"allow": false, "reason": "out_of_window"} if {
	not in_window
} else := {"allow": false, "reason": "out_of_scope"} if {
	not in_lab
} else := {"allow": false, "reason": "approval_required"} if {
	not approval_valid
} else := {"allow": true, "reason": "allowed"}

hard_denied if {
	some cidr in input.scope.hard_deny
	net.cidr_contains(cidr, input.destination)
}

technique := t if {
	some t in input.catalog.techniques
	t.id == input.action.technique_id
}

technique_known if {
	technique
}

class_allowed if {
	technique.class in input.scope.allowed_classes
}

# A missing or unknown human-assigned target criticality is scope uncertainty:
# pause for the operator instead of allowing the action.
criticality_known if {
	input.scope.target_criticality in ["low", "medium", "high", "critical"]
}

in_window if {
	input.now_ns >= time.parse_rfc3339_ns(input.scope.not_before)
	input.now_ns <= time.parse_rfc3339_ns(input.scope.not_after)
}

in_lab if {
	some cidr in input.scope.lab_cidrs
	net.cidr_contains(cidr, input.destination)
}

approval_valid if {
	input.approval.valid == true
}
