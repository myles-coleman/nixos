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
# Reverting is deleting this import from `hosts/homelab/default.nix` and
# restarting the guest once.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      gvisor =
        (prev.gvisor.override {
          # gVisor 20261102.0 requires Go >= 1.27.3; nixpkgs' default `buildGoModule`
          # is the 1.26 wrapper (Go 1.26.8), which is too old. The tree also ships
          # `buildGo127Module`, pinned to `go_1_27` (1.27.3) — exactly enough.
          buildGoModule = prev.buildGo127Module;
        }).overrideAttrs (_old: {
          version = "20261102.0";
          # gVisor's synthetic `go` branch (buildable without Bazel), pinned to the
          # branch tip at release-20261102.0-25. To update, take a newer go-branch
          # commit and refresh both hashes:
          #   nix-prefetch-github google gvisor --rev <rev>   (src.hash)
          #   nix build .../pkgs.gvisor                       (reports the vendorHash)
          src = prev.fetchFromGitHub {
            owner = "google";
            repo = "gvisor";
            rev = "1ff810cb4f8ebf85cf009c60c236ff9d14f07618";
            hash = "sha256-oD2uS3PCQRQGLGtuF4/yter9I3t6Txn2oAPhDhvAscs=";
          };
          vendorHash = "sha256-Hk9wHVoaRmYXsKZNa7hy+Alstf6iUCP8zccZO4MKfjc=";
          # nixpkgs carries a `go mod tidy` patch for the 20260406.0 tree (it drops
          # requires that are absent from the vendor directory). The newer tree no
          # longer matches those hunks; drop the patch and let the tree's own go.mod
          # define the vendor set that `vendorHash` covers.
          patches = [];
        });
    })
  ];
}
