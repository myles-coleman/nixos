#!/usr/bin/env bash
#
# Tests for the PR workflow split (spec 30, FR-45 / tasks 4.4 and 4.5).
#
# The security property is not "the comment still works"; it is that a
# `pull_request`-triggered workflow has no write token and no repository secret,
# and that the closure-diff comment is rendered by a separate `workflow_run`
# workflow that checks out the base repository only.
#
# The YAML is parsed by the small, dependency-free parser below (Python 3
# standard library only). PyYAML and yq are deliberately not used: this test
# runs in the same secret-free CI path it is guarding.
#
# Usage: scripts/tests/test-pr-workflow.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

python3 - "$ROOT" <<'PY'
import os
import re
import sys

TOTAL = 10


class YamlError(Exception):
    pass


def fail(number, message):
    print(f"FAIL {number}/{TOTAL} - {message}", file=sys.stderr, flush=True)
    sys.exit(1)


def ok(number, message):
    print(f"PASS {number}/{TOTAL} - {message}", flush=True)


# ── minimal YAML subset parser ───────────────────────────────────────────────
# It understands indentation-based mappings and sequences, flow sequences,
# quoted scalars, inline comments, and literal/folded block scalars. That is
# enough for GitHub Actions workflow files and avoids a third-party parser.

def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def strip_comment(value):
    out = []
    quote = None
    for i, ch in enumerate(value):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or value[i - 1].isspace()):
            break
        out.append(ch)
    return "".join(out).rstrip()


def parse_scalar(value):
    value = strip_comment(value).strip()
    if value == "":
        return None
    if value.startswith("[") and value.endswith("]"):
        return split_flow(value[1:-1])
    return unquote(value)


def split_flow(body):
    items = []
    current = []
    quote = None
    depth = 0
    for ch in body:
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            current.append(ch)
        elif ch in "[{":
            depth += 1
            current.append(ch)
        elif ch in "]}":
            depth -= 1
            current.append(ch)
        elif ch == "," and depth == 0:
            items.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        items.append("".join(current).strip())
    return [parse_scalar(item) for item in items if item != ""]


def tokenize(text):
    tokens = []
    for raw in text.splitlines():
        if raw.strip() == "":
            continue
        leading = raw[: len(raw) - len(raw.lstrip())]
        if "\t" in leading:
            raw = raw.expandtabs(8)
        stripped = raw.lstrip(" ")
        indent = len(raw) - len(stripped)
        if stripped.startswith("#"):
            continue
        if stripped in ("---", "..."):
            continue
        tokens.append((indent, stripped, raw))
    return tokens


def is_list_item(text):
    return text == "-" or text.startswith("- ")


def split_key(text):
    key, sep, rest = text.partition(":")
    if not sep:
        raise YamlError(f"expected a mapping key: {text!r}")
    return unquote(key.strip()), rest


def parse_value(tokens, index, indent, rest):
    rest = rest.strip()
    if rest == "":
        if index + 1 < len(tokens) and tokens[index + 1][0] > indent:
            return parse_block(tokens, index + 1, tokens[index + 1][0])
        return None, index + 1
    if rest[0] in ("|", ">"):
        index += 1
        content = []
        block_indent = None
        while index < len(tokens) and tokens[index][0] > indent:
            ind, text, _raw = tokens[index]
            if block_indent is None:
                block_indent = ind
            if ind >= block_indent:
                content.append(" " * (ind - block_indent) + text)
            else:
                content.append(text)
            index += 1
        return "\n".join(content), index
    return parse_scalar(rest), index + 1


def parse_map_entries(tokens, index, indent, mapping):
    while index < len(tokens):
        ind, text, _raw = tokens[index]
        if ind < indent:
            break
        if ind > indent:
            raise YamlError(f"unexpected indentation: {text!r}")
        if is_list_item(text):
            break
        key, rest = split_key(text)
        value, index = parse_value(tokens, index, indent, rest)
        mapping[key] = value
    return mapping, index


def parse_list(tokens, index, indent):
    items = []
    while index < len(tokens):
        ind, text, _raw = tokens[index]
        if ind != indent or not is_list_item(text):
            break
        after_dash = text[1:]
        content = after_dash.lstrip(" ")
        spaces = len(after_dash) - len(content)
        item_indent = ind + 1 + spaces
        rest = content.strip()
        if rest == "":
            if index + 1 < len(tokens) and tokens[index + 1][0] > indent:
                value, index = parse_block(tokens, index + 1, tokens[index + 1][0])
            else:
                value, index = None, index + 1
            items.append(value)
            continue
        key, sep, value_rest = rest.partition(":")
        if sep and re.match(r"^[A-Za-z0-9_.\-]+$", key.strip()):
            mapping = {}
            value, index = parse_value(tokens, index, item_indent, value_rest)
            mapping[unquote(key.strip())] = value
            mapping, index = parse_map_entries(tokens, index, item_indent, mapping)
            items.append(mapping)
        else:
            items.append(parse_scalar(rest))
            index += 1
    return items, index


def parse_block(tokens, index, indent):
    if index >= len(tokens):
        return None, index
    if is_list_item(tokens[index][1]):
        return parse_list(tokens, index, indent)
    return parse_map_entries(tokens, index, indent, {})


def parse_yaml(text):
    tokens = tokenize(text)
    value, index = parse_block(tokens, 0, 0)
    if index != len(tokens):
        raise YamlError(f"unparsed input starting at: {tokens[index][1]!r}")
    return value


# ── assertions ───────────────────────────────────────────────────────────────

root = sys.argv[1]
workflows = os.path.join(root, ".github", "workflows")
pr_path = os.path.join(workflows, "pr.yaml")
comment_path = os.path.join(workflows, "pr-comment.yaml")


def read(path, number, label):
    if not os.path.isfile(path):
        fail(number, f"{label} does not exist at {path}")
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def parse(path, text, number, label):
    try:
        return parse_yaml(text)
    except (YamlError, IndexError) as error:
        fail(number, f"{label} is not parseable by the test parser: {error}")


# 1. pr.yaml exists and is triggered by pull_request only.
pr_text = read(pr_path, 1, "pr.yaml")
pr = parse(pr_path, pr_text, 1, "pr.yaml")
on = pr.get("on")
if isinstance(on, dict):
    triggers = list(on.keys())
elif isinstance(on, str):
    triggers = [on]
elif isinstance(on, list):
    triggers = on
else:
    triggers = []
if triggers != ["pull_request"]:
    fail(1, f"pr.yaml triggers are {triggers!r}, expected only ['pull_request']")
ok(1, "pr.yaml exists and is triggered by pull_request only")

# 2. No pull-requests: write anywhere in pr.yaml.
if re.search(r"pull-requests\s*:\s*write", pr_text):
    fail(2, "pr.yaml contains 'pull-requests: write'")
ok(2, "pr.yaml contains no pull-requests: write")

# 3. No secrets reference anywhere in pr.yaml.
if re.search(r"\bsecrets\.", pr_text):
    match = re.search(r"\bsecrets\.\S*", pr_text)
    fail(3, f"pr.yaml references a secret: {match.group(0)!r}")
ok(3, "pr.yaml contains no secrets.* reference")

# 4. Workflow-level and every job-level permissions are exactly contents: read.
workflow_permissions = pr.get("permissions")
if workflow_permissions != {"contents": "read"}:
    fail(4, f"workflow permissions are {workflow_permissions!r}, expected only contents: read")
jobs = pr.get("jobs")
if not isinstance(jobs, dict) or not jobs:
    fail(4, "pr.yaml has no jobs mapping")
for job_name, job in jobs.items():
    if not isinstance(job, dict):
        fail(4, f"job {job_name!r} is not a mapping")
    job_permissions = job.get("permissions")
    if job_permissions != {"contents": "read"}:
        fail(4, f"job {job_name!r} permissions are {job_permissions!r}, expected only contents: read")
ok(4, "the workflow and every job declare exactly contents: read")

# 5. The PR workflow no longer posts a comment.
for needle, label in (
    ("Post PR comment", "the 'Post PR comment' step"),
    ("GH_TOKEN", "a GH_TOKEN reference"),
    ("gh pr comment", "a 'gh pr comment' command"),
):
    if needle in pr_text:
        fail(5, f"pr.yaml still contains {label}")
if re.search(r"gh\s+api[^\n]*issues/[^\n]*/comments", pr_text):
    fail(5, "pr.yaml still calls gh api .../issues/.../comments")
ok(5, "pr.yaml no longer posts a PR comment")

# 6. closure-diff uploads the comment as an artifact.
closure = jobs.get("closure-diff")
if not isinstance(closure, dict):
    fail(6, "pr.yaml has no closure-diff job")
steps = closure.get("steps")
if not isinstance(steps, list):
    fail(6, "closure-diff has no steps list")
upload_found = False
for step in steps:
    if not isinstance(step, dict):
        continue
    uses = step.get("uses") or ""
    if not re.fullmatch(r"actions/upload-artifact@[0-9a-f]{40}", uses):
        continue
    with_ = step.get("with") or {}
    if (
        with_.get("name") == "nixos-diff-comment"
        and with_.get("path") == "${{ steps.diff.outputs.comment_file }}"
    ):
        upload_found = True
if not upload_found:
    fail(
        6,
        "closure-diff does not upload actions/upload-artifact with "
        "name: nixos-diff-comment and path: ${{ steps.diff.outputs.comment_file }}",
    )
ok(6, "closure-diff uploads the comment as the nixos-diff-comment artifact")

# 7. pr-comment.yaml exists with the workflow_run trigger.
comment_text = read(comment_path, 7, "pr-comment.yaml")
comment = parse(comment_path, comment_text, 7, "pr-comment.yaml")
comment_on = comment.get("on")
if not isinstance(comment_on, dict):
    fail(7, "pr-comment.yaml has no 'on:' mapping")
if "pull_request" in comment_on:
    fail(7, "pr-comment.yaml must not have a pull_request trigger")
workflow_run = comment_on.get("workflow_run")
if not isinstance(workflow_run, dict):
    fail(7, "pr-comment.yaml has no workflow_run trigger")
workflows = workflow_run.get("workflows")
if isinstance(workflows, str):
    workflows = [workflows]
if workflows != ["PR Build & Diff"]:
    fail(7, f"workflow_run.workflows is {workflows!r}, expected ['PR Build & Diff']")
types = workflow_run.get("types")
if isinstance(types, str):
    types = [types]
if types != ["completed"]:
    fail(7, f"workflow_run.types is {types!r}, expected ['completed']")
ok(7, "pr-comment.yaml is workflow_run-triggered by 'PR Build & Diff' on completion")

# 8. Write permission lives only in pr-comment.yaml, which downloads the artifact.
comment_permissions = comment.get("permissions")
expected_comment_permissions = {"contents": "read", "pull-requests": "write"}
if comment_permissions != expected_comment_permissions:
    fail(
        8,
        f"pr-comment.yaml permissions are {comment_permissions!r}, "
        f"expected {expected_comment_permissions!r}",
    )
comment_jobs = comment.get("jobs")
if not isinstance(comment_jobs, dict):
    fail(8, "pr-comment.yaml has no jobs mapping")
download_found = False
for job in comment_jobs.values():
    if not isinstance(job, dict):
        continue
    for step in job.get("steps") or []:
        if not isinstance(step, dict):
            continue
        uses = step.get("uses") or ""
        if not re.fullmatch(r"actions/download-artifact@[0-9a-f]{40}", uses):
            continue
        with_ = step.get("with") or {}
        if (
            with_.get("name") == "nixos-diff-comment"
            and with_.get("run-id") == "${{ github.event.workflow_run.id }}"
        ):
            download_found = True
if not download_found:
    fail(
        8,
        "pr-comment.yaml does not download actions/download-artifact with "
        "name: nixos-diff-comment and run-id: ${{ github.event.workflow_run.id }}",
    )
ok(8, "pr-comment.yaml holds pull-requests: write and downloads nixos-diff-comment")

# 9. The checkout is base-only and keeps credentials out of the worktree.
for needle in (
    "github.event.workflow_run.head_sha",
    "github.event.workflow_run.head_branch",
    "github.event.pull_request.head",
):
    if needle in comment_text:
        fail(9, f"pr-comment.yaml references {needle}")
checkout_found = False
for job in comment_jobs.values():
    if not isinstance(job, dict):
        continue
    for step in job.get("steps") or []:
        if not isinstance(step, dict):
            continue
        uses = step.get("uses") or ""
        if not re.fullmatch(r"actions/checkout@[0-9a-f]{40}", uses):
            continue
        checkout_found = True
        with_ = step.get("with") or {}
        if "ref" in with_:
            fail(9, "pr-comment.yaml checkout declares a ref")
        persist = with_.get("persist-credentials")
        if str(persist).lower() != "false":
            fail(9, f"pr-comment.yaml checkout persist-credentials is {persist!r}, expected false")
if not checkout_found:
    fail(9, "pr-comment.yaml has no pinned actions/checkout step")
ok(9, "pr-comment.yaml checks out without a ref and sets persist-credentials: false")

# 10. Every uses: in both workflows is pinned to a full SHA with a version comment.
def check_pins(text, label):
    for lineno, line in enumerate(text.splitlines(), 1):
        match = re.match(r"^\s*(?:-\s+)?uses:\s*(\S+)(.*)$", line)
        if not match:
            continue
        ref = match.group(1).strip("'\"")
        trailing = match.group(2)
        if ref.startswith("./"):
            continue
        if not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", ref):
            fail(10, f"{label}:{lineno}: uses {ref!r} is not pinned to a 40-character commit SHA")
        if not re.match(r"^\s*#\s*v\S+", trailing):
            fail(10, f"{label}:{lineno}: uses {ref!r} has no trailing '# v...' version comment")


check_pins(pr_text, "pr.yaml")
check_pins(comment_text, "pr-comment.yaml")
ok(10, "every uses: in both workflows is pinned to a full SHA with a version comment")

print(f"\nall {TOTAL} pr-workflow assertions passed")
PY
