{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "redteam-evidence";
  version = "0.1.0";

  src = ../redteam-broker;
  vendorHash = "sha256-NBAiC6/+FcCV1jEfEBe06++RrEm6ZXrGWqmZrmI9W6E=";

  subPackages = ["cmd/redteam-evidence-verify"];
  env.CGO_ENABLED = 0;
  ldflags = ["-s" "-w"];

  meta = {
    description = "APTS Stage 1 evidence chain verifier";
    license = lib.licenses.mit;
    mainProgram = "redteam-evidence-verify";
    platforms = ["x86_64-linux"];
  };
}
