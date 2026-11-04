# AGENTS.md — sandbox agent instructions (spec 20, updated by spec 21)

This file overrides the `nixos` repo's own `AGENTS.md` for agents running **inside** the
Kubernetes Agent Sandbox. It is the sandbox-specific instructions file required by spec 20,
Unit 4, and revised by spec 21, Unit 2.

## You are edit-only: there is no Nix here

The repo's root `AGENTS.md` tells agents that missing commands should be run with
`nix-shell -p <package> --run "<command>"`. **In this sandbox that will fail, and it is not
a bug you should try to work around.**

The previous nspawn instance could `nix build` because it bind-mounted the host `/nix/store`
and the Nix daemon socket. Neither is possible in a Kubernetes pod, so:

- **Do not run `nix`, `nix-shell`, `nix build`, `nix develop`, or `rebuild`.**
- **Do not try to install packages.** The image ships what you need: `git`, `curl`,
  `coreutils`, `ripgrep`, `bash`, `tar`, `unzip`, `python3`, `cacert`, and OpenCode.
- **Edit files.** The operator (or CI) builds, tests, and deploys.

If a task genuinely needs a tool that is not present, say so in your final message and stop —
do not loop on `nix-shell`.

## You cannot push. Hand back a patch.

**There is no repository write credential in this sandbox.** The `GIT_PAT` variable that used
to exist is gone, and it is not coming back: `Contents: write` is the permission GitHub's merge
endpoint requires, a merge runs the deploy workflow, and that workflow deploys to hosts with
passwordless `sudo` as a single human. A prompt-injected agent with a write token is therefore
a path to host root, not just to a commit.

So the handoff is a patch file. Do this:

1. Work on the copy that is already in the workspace (`/home/agent/nixos`). **You cannot
   clone or fetch** — the sandbox has no internet (see Network below). It was seeded by the
   operator at a pinned revision, so it may lag behind `main`. Say so in your final message if
   that matters for the change.
2. Create a branch and commit your work locally:

   ```bash
   git switch -c <short-descriptive-branch>
   git add -A
   git commit -m "fix(<scope>): <what changed>"
   ```

   A git identity is provided by the pod environment (`GIT_COMMITTER_NAME` /
   `GIT_COMMITTER_EMAIL`), so you do not need to configure one.

3. Write the patches to the handoff directory:

   ```bash
   git format-patch -o /home/agent/patches origin/main
   ```

4. Tell the operator what you changed and why in your final message.

Rules:

- **Never** `git push`, `git remote add` with credentials, or try to authenticate to GitHub.
- **Never** hand off `.git`. The operator collects `*.patch` files only.
- **Never** put a secret, token or private key in a commit message, a patch, or a file.
- One logical change per patch. A patch the operator cannot review in one sitting will be
  rejected.
- Patches touching `.github/workflows/`, `flake.lock`, `.sops.yaml`, `secrets/`,
  `hosts/homelab/modules/sandbox-node.nix`, or `authorized_keys` will be **refused by the
  collector** unless the operator overrides it. If your change genuinely needs one of those,
  say so explicitly instead of bundling it into an unrelated patch.

## Network

There is **no internet at all** in this sandbox. `HTTP_PROXY`/`HTTPS_PROXY` point at a forward
proxy whose allowlist is empty: **every** outbound request is denied and logged. There is also
no DNS.

- **Do not** `git clone`, `git fetch`, `git pull`, `npm install`, `pip install`, `curl` or
  `wget` anything external. They will fail, and the failure is the intended behaviour, not a
  bug to work around.
- The workspace copy is seeded by the operator. Work with what is there.
- The model endpoint is reached by IP literal and bypasses the proxy; it is the only reachable
  service.
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
