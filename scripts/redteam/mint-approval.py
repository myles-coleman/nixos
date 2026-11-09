#!/usr/bin/env python3
"""mint-approval.py - mint a Stage 1 approval token.

This is the small operator-side tool used before the Task 5 CLI exists. It signs
the canonical claims with an OpenSSL Ed25519 key and prints the base64 token the
broker expects. The private key never leaves the operator machine.
"""

import argparse
import base64
import json
import subprocess
import tempfile
import time


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", required=True, help="OpenSSL Ed25519 private key")
    parser.add_argument("--engagement", default="stage1-demo")
    parser.add_argument("--scope-version", type=int, default=1)
    parser.add_argument("--technique", default="http.get")
    parser.add_argument("--target", default="10.99.0.2")
    parser.add_argument("--path", default="/ftp/")
    parser.add_argument("--nonce", default=str(int(time.time() * 1000)))
    parser.add_argument("--ttl", type=int, default=600)
    args = parser.parse_args()

    claims = {
        "engagement_id": args.engagement,
        "expires_at": int(time.time()) + args.ttl,
        "nonce": args.nonce,
        "parameters": {"path": args.path},
        "scope_version": args.scope_version,
        "target": args.target,
        "technique_id": args.technique,
    }
    canonical = json.dumps(claims, sort_keys=True, separators=(",", ":")).encode()

    with tempfile.NamedTemporaryFile() as handle:
        handle.write(canonical)
        handle.flush()
        signature = subprocess.check_output(
            [
                "openssl",
                "pkeyutl",
                "-sign",
                "-rawin",
                "-inkey",
                args.key,
                "-in",
                handle.name,
            ]
        )

    claims["signature"] = base64.b64encode(signature).decode()
    token = base64.b64encode(json.dumps(claims, separators=(",", ":")).encode()).decode()
    print(token)


if __name__ == "__main__":
    main()
