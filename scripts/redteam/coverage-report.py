#!/usr/bin/env python3
"""coverage-report.py - independent Juice Shop coverage from probe results.

The target never reports its own coverage. This harness reads a signed answer
key, sends each probe, and decides found/not-found from the HTTP response. A
`control` probe is expected *not* to match; if it does, the harness counts a
false positive instead of crediting coverage.

Run from a lab-attached namespace (see lab-exec.sh) because the target is only
reachable on lab0.
"""

import argparse
import http.client
import json
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path


def verify(answer_key: Path, allowed_signers: Path) -> None:
    sig = answer_key.with_suffix(answer_key.suffix + ".sig")
    subprocess.run(
        [
            "ssh-keygen",
            "-Y",
            "verify",
            "-f",
            str(allowed_signers),
            "-I",
            "redteam-answer-key",
            "-n",
            "redteam-answer-key",
            "-s",
            str(sig),
        ],
        stdin=answer_key.open("rb"),
        check=True,
        stdout=subprocess.DEVNULL,
    )


def probe(base_url: str, spec: dict, timeout: float) -> tuple[bool, int, str]:
    url = base_url.rstrip("/") + spec["path"]
    request = urllib.request.Request(url, method=spec.get("method", "GET"))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            try:
                body = response.read().decode("utf-8", errors="replace")
            except http.client.IncompleteRead as exc:
                # Juice Shop's /ftp/ listing closes the connection early. The
                # partial body still contains the directory entries, which is
                # what the probe is looking for.
                body = exc.partial.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        status = exc.code
        body = exc.read().decode("utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001 - report the failure, do not crash
        return False, 0, f"{type(exc).__name__}: {exc}"

    matched = status == spec["expect_status"] and spec["expect_body_contains"] in body
    return matched, status, ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://10.99.0.2:3000")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument(
        "--answer-key",
        type=Path,
        default=Path(__file__).resolve().parents[2]
        / "config"
        / "redteam"
        / "juice-shop-answer-key.json",
    )
    parser.add_argument(
        "--allowed-signers",
        type=Path,
        default=Path(__file__).resolve().parents[2]
        / "config"
        / "redteam"
        / "allowed_signers",
    )
    args = parser.parse_args()

    verify(args.answer_key, args.allowed_signers)
    data = json.loads(args.answer_key.read_text())

    positives = 0
    found = 0
    controls = 0
    false_positives = 0

    print(f"{'CHALLENGE':28} {'KIND':8} {'STATUS':6} {'EXPECTED':8} {'RESULT':8} NOTE")
    for challenge in data["challenges"]:
        kind = challenge.get("kind", "positive")
        spec = challenge["probe"]
        matched, status, note = probe(args.base_url, spec, args.timeout)

        if kind == "control":
            controls += 1
            if matched:
                false_positives += 1
                result = "FP"
            else:
                result = "PASS"
        else:
            positives += 1
            if matched:
                found += 1
                result = "FOUND"
            else:
                result = "MISS"

        print(
            f"{challenge['id']:28} {kind:8} {status:<6} {spec['expect_status']:<8} "
            f"{result:8} {note}"
        )

    coverage = (found / positives * 100) if positives else 0.0
    print()
    print(f"coverage: {found}/{positives} ({coverage:.0f}%)")
    print(f"false_positives: {false_positives}/{controls}")

    if false_positives:
        print("coverage-report: control probe matched; refusing to credit coverage", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
