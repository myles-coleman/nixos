# AGENTS.md — sandbox agent instructions (spec 20)

This file overrides the `nixos` repo's own `AGENTS.md` for agents running **inside** the
Kubernetes Agent Sandbox. It is the sandbox-specific instructions file required by spec 20,
Unit 4.

## You are edit-only: there is no Nix here

The repo's root `AGENTS.md` tells agents that missing commands should be run with
`nix-shell -p <package> --run "<command>"`. **In this sandbox that will fail, and it is not
a bug you should try to work around.**

The previous nspawn instance could `nix build` because it bind-mounted the host `/nix/store`
and the Nix daemon socket. Neither is possible in a Kubernetes gVisor pod, so:

- **Do not run `nix`, `nix-shell`, `nix build`, `nix develop`, or `rebuild`.**
- **Do not try to install packages.** The image ships what you need: `git`, `curl`,
  `coreutils`, `ripgrep`, `bash`, `tar`, `unzip`, `cacert`, and OpenCode.
- **Edit files.** The operator (or CI) builds, tests, and deploys. Your job is a reviewable
  diff on a branch, not a green build.

If a task genuinely needs a tool that is not present, say so in your final message and stop —
do not loop on `nix-shell`.

## Network

There is **no direct internet and no DNS** in this sandbox. Egress is an FQDN-allowlisted
forward proxy, so only a small set of hosts is reachable, and only through the proxy:

- Use `git`/`curl` normally; `HTTP_PROXY`/`HTTPS_PROXY` are set.
- The model endpoint is reached by IP literal (no DNS).
- A request to a non-allowlisted host is denied and logged.

## Secrets

Never print, commit, or echo secrets (the git PAT, the model API key, the server password).
They are injected into the environment by External Secrets; use them, do not inspect them.

## Workspace

Your workspace and `$HOME` (including the OpenCode session DB and tool caches) are on a
`local-path` PVC with reclaim `Retain`, pre-created so an ArgoCD prune or a `Sandbox` delete
cannot wipe your work. Keep heavy artifacts on that volume, not in `emptyDir` (gVisor turns
`emptyDir` into a RAM-backed tmpfs).
