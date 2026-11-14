# AGENTS.md — sandbox agent instructions (spec 20; revised by specs 21 and 30)

This file overrides the `nixos` repo's own `AGENTS.md` for agents running **inside** the
Kubernetes Agent Sandbox. It is the sandbox-specific instructions file required by spec 20,
Unit 4, and revised by spec 21, Unit 2 and spec 30, Unit 5.

## You are edit-only: there is no Nix here

The repo's root `AGENTS.md` tells agents that missing commands should be run with
`nix-shell -p <package> --run "<command>"`. **In this sandbox that will fail, and it is not
a bug you should try to work around.**

The previous nspawn instance could `nix build` because it bind-mounted the host `/nix/store`
and the Nix daemon socket. Neither is possible in a Kubernetes pod, so:

- **Do not run `nix`, `nix-shell`, `nix build`, `nix develop`, or `rebuild`.**
- **Do not try to install packages.** The image ships the pinned toolchain:
  - For edit/lint/format: `git`, `curl`, `jq`, `alejandra`, `statix`, `deadnix`,
    `yamllint`, `ripgrep`, `coreutils`, `bash`, `tar`, `unzip`, `python3`,
    `ca-certificates`, and OpenCode v2.0.23.
  - For the cluster repo: `kustomize`, `helm`, `kubeconform`.
- **Edit files.** The operator (or CI) builds, tests, and deploys.

If a task genuinely needs a tool that is not present, say so in your final message and stop —
do not loop on `nix-shell`.

## You cannot push. Submit a patch to the validator.

**There is no repository write credential in this sandbox.** The `GIT_PAT` variable that used
to exist is gone, and it is not coming back: `Contents: write` is the permission GitHub's merge
endpoint requires, a merge runs the deploy workflow, and that workflow deploys to hosts with
passwordless `sudo` as a single human. A prompt-injected agent with a write token is therefore
a path to host root, not just to a commit.

So the handoff is a patch submission, not a push and not a patch directory. Do this:

1. Work on the copy that is already in the workspace (`/home/agent/nixos` or
   `/home/agent/homelab-cluster`). **You cannot clone or fetch from the internet** (see
   Network below). It was materialised by the operator from a git bundle at a pinned revision,
   so it may lag behind `main`. Before you change anything, record the base commit you are
   building on:

   ```bash
   BASE_COMMIT=$(git rev-parse HEAD)
   ```

   Say so in your final message if the seeded revision matters for the change.
2. Create a branch and commit your work locally:

   ```bash
   git switch -c <short-descriptive-branch>
   git add -A
   git commit -m "fix(<scope>): <what changed>"
   ```

   A git identity is provided by the pod environment (`GIT_COMMITTER_NAME` /
   `GIT_COMMITTER_EMAIL`), so you do not need to configure one.
3. Submit the commit as patch text to the validator over mTLS:

   ```bash
   git diff "$BASE_COMMIT"..HEAD > /tmp/change.patch
   jq -n --arg repo nixos --arg base "$BASE_COMMIT" \
         --arg msg "$(git log -1 --format=%B)" --arg title "$(git log -1 --format=%s)" \
         --arg body "<what changed and why>" --rawfile patch /tmp/change.patch \
         '{repo:$repo, base_commit:$base, commit_message:$msg, title:$title, body:$body, patch:$patch}' \
         > /tmp/patch-request.json
   curl --fail-with-body --silent --show-error \
     --cacert /certs/ca.crt --cert /certs/tls.crt --key /certs/tls.key \
     -X POST https://validator.agent.internal:8443/v1/patches \
     -H 'Content-Type: application/json' \
     --data @/tmp/patch-request.json
   ```

   The client certificate is mounted under `/certs/` by cert-manager; it is the only proof of
   identity the validator accepts. `POST /v1/patches` returns `202` with `{bundle_sha256,
   canonical_hash, commit_sha, tree_sha}` on acceptance, or a structured `4xx` carrying a
   stable `rule_id` and a one-sentence reason. On `stale-base` (your base is no longer an
   ancestor of `main`), re-fetch `GET /v1/repos/{repo}/bundle`, rebase onto the new tip, and
   resubmit. Never force anything.
4. The validator applies the patch to a clean worktree, enforces the shared allowlist, and
   scans the applied tree, the commit message, and the PR body. A verified bundle then goes to
   the publisher, which pushes `refs/heads/agent/<uid>/<slug>` and opens a **draft PR**. You
   never see a push credential; the draft PR appears without you.
5. Tell the operator what you changed and why in your final message.

Rules:

- **Never** `git push`, `git remote add` with credentials, or try to authenticate to GitHub.
- **Never** hand off `.git`. Only the patch text in the request is submitted.
- **Never** put a secret, token or private key in a commit message, a patch, or a file.
- One logical change per submission. A change a reviewer cannot review in one sitting will be
  rejected.
- Every changed path is judged against the canonical per-repo allowlist at
  `homelab-cluster/services/agent-broker/policy/repos.yaml`, served by the validator at
  `GET /v1/policy` and enforced on every submission (default deny; deny always wins). Do not
  try to work around a denied path — it returns `4xx` with `rule_id=path-not-allowed`. If your
  change genuinely needs a protected path, say so explicitly and stop.

## Network

There is **no internet at all** in this sandbox. `HTTP_PROXY`/`HTTPS_PROXY` point at a forward
proxy whose allowlist is empty: **every** outbound request is denied and logged. There is also
no DNS.

- **Do not** `git clone`, `git fetch`, `git pull`, `npm install`, `pip install`, `curl` or
  `wget` anything external. They will fail, and the failure is the intended behaviour, not a
  bug to work around.
- The workspace copy is seeded by the operator. Work with what is there.
- The only reachable services are the model endpoint (by IP literal) and the validator at
  `https://validator.agent.internal:8443`. The validator name comes from a `hostAliases` entry
  and is excluded from the proxy via `NO_PROXY`; both bypass the squid path. `curl` to the
  validator is the patch handoff described above; `curl` anywhere else is a failure of the
  allowlist, not something to retry.
- If a task genuinely needs a dependency that is not present, say so and stop. Do not retry.

## Secrets

Never print, commit, or echo secrets (the model API key, the server password). They are
injected into the environment by External Secrets; use them, do not inspect them.

## Sandbox posture

The pod runs with `seccompProfile: RuntimeDefault`, no Linux capabilities, no privilege
escalation, and a **read-only root filesystem**. Writable paths are:

- `/home/agent` — the workspace PVC, including your clone.
- `/tmp` — a bounded `emptyDir` (1 GiB). Use it for scratch files, not for work you want to
  keep.

A write anywhere else fails with `Read-only file system`. That is the posture, not a bug.

## Workspace

Your workspace and `$HOME` (including the OpenCode session DB and tool caches) are on a
`local-path` PVC with reclaim `Retain`, pre-created so an ArgoCD prune or a `Sandbox` delete
cannot wipe your work. Keep heavy artifacts on that volume, not in `/tmp`.

## The kernel you see is not the host kernel

Since spec 22 this sandbox runs under **gVisor**. `uname -r` and `/proc/version` report a
synthetic `4.19.0-gvisor` kernel, not the node's NixOS kernel, and some `/proc` and `/sys`
paths are emulated and thinner than on a real Linux host.

- That is expected, not a misconfiguration. Do not try to "fix" it.
- If a syscall or a `/proc` file behaves oddly, say so and stop; do not attempt workarounds
  that assume a real kernel.
- The boundary exists so that a container escape needs a gVisor bug rather than a Linux kernel
  bug. Do not weaken it: no privileged flags, no host mounts, no changes to the runtime class.
