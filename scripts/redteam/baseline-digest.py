#!/usr/bin/env python3
"""baseline-digest.py - compute the disposable target's reset baseline digest.

Runs inside a lab-attached namespace. The digest covers the application version
and the full (id, solved) challenge projection. It is a reset-determinism check,
not a coverage measurement: the coverage harness uses independent probes.
"""

import hashlib
import json
import urllib.request

BASE = "http://10.99.0.2:3000"


def get(path: str) -> dict:
    with urllib.request.urlopen(BASE + path, timeout=10) as response:
        return json.load(response)


version = get("/rest/admin/application-version")["version"]
challenges = get("/api/Challenges")["data"]
projection = sorted((c["id"], bool(c.get("solved", False))) for c in challenges)
payload = json.dumps(
    {"version": version, "challenges": projection},
    sort_keys=True,
    separators=(",", ":"),
).encode()

print(f"version={version}")
print(f"challenges={len(projection)}")
print(f"solved={sum(1 for _, solved in projection if solved)}")
print(f"baseline_digest={hashlib.sha256(payload).hexdigest()}")
