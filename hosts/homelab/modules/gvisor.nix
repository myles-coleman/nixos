# gVisor version override for the agent sandbox node (spec 22, Unit 1).
#
# Why this exists: both flake inputs (`nixpkgs` and `nixpkgs-unstable`) pin
# `gvisor` to 20260406.0, and that release predates the fix for CVE-2026-96812 —
# a host-root escape in the gofer reachable through a /dev/cuse node (published
# 2026-09-25, fixed upstream at commit 573a9e73cf844f, CVSS 8.8). The runtime
# spec 22 proposes as a security boundary must not ship a known host escape, so
# the pin moves here instead of waiting for an upstream nixpkgs bump.
#
# Why this file is a *host* module and not part of `sandbox-node.nix`:
# microvm.nix evaluates each guest with `inherit (config) extraModules specialArgs
# pkgs`, so the guest's `pkgs` IS homelab's `pkgs`. An overlay declared inside the
# guest module is silently ignored. `sandbox-node.nix` picks the new package up
# through `systemd.services.k3s.path = [ pkgs.gvisor ]`.
#
# ── Why the upstream release tarball and not a source build ──────────────────
# nixpkgs builds gVisor from its synthetic `go` branch, which carries only the Go
# sources. Since the 2026 releases `runsc` no longer embeds the sentry: it spawns
# `gvisor-bin/{gvisor_sentry, gvisor-sentry-prewarmer, runsc-fd-parking,
# gvisor-proc-umounter, runsc-metric-server, checkpointgofer}` from beside the
# binary. Four of those are C programs whose only build rules live in the Bazel
# files that the `go` branch strips, so a source build produces a `runsc` that
# cannot create a single sandbox. The published release tarball — the same
# artifact `runsc install` downloads — contains the whole set with matching
# release labels. It is hash-pinned here, so it is still a fixed, reproducible
# input.
#
# Reverting is deleting this import from `hosts/homelab/default.nix` and
# restarting the guest once.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      gvisor = prev.stdenv.mkDerivation {
        pname = "gvisor";
        version = "20261102.0";

        src = prev.fetchurl {
          url = "https://storage.googleapis.com/gvisor/releases/release/20261102.0/x86_64/gvisor.tar.bz2";
          hash = "sha256-b2sajw9GZaQDI4E1Fn0NmQv66v9VRKv2j14Ngis1SEo=";
        };

        nativeBuildInputs = [prev.bzip2 prev.makeWrapper];

        # The tarball is flat: runsc, containerd-shim-runsc-v1, and gvisor-bin/.
        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          install -m 0755 runsc containerd-shim-runsc-v1 $out/bin/
          cp -a gvisor-bin $out/bin/gvisor-bin
          runHook postInstall
        '';

        # `runsc do` shells out to these; containerd does not need them, but the
        # nixpkgs package provided them and dropping them would be a silent
        # regression for anyone debugging on the node.
        postFixup = ''
          wrapProgram $out/bin/runsc \
            --prefix PATH : ${prev.lib.makeBinPath [prev.iproute2 prev.iptables prev.procps]}
        '';

        meta =
          (prev.gvisor.meta or {})
          // {
            # The release bucket publishes per-architecture tarballs, and the sandbox
            # node is the fleet's one deliberate amd64 host.
            platforms = ["x86_64-linux"];
          };
      };
    })
  ];
}
