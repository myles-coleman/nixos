{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "redteam-cli";
  version = "0.1.0";

  src = ../redteam-broker;
  vendorHash = "sha256-NBAiC6/+FcCV1jEfEBe06++RrEm6ZXrGWqmZrmI9W6E=";

  subPackages = ["cmd/redteam-cli"];
  env.CGO_ENABLED = 0;
  ldflags = ["-s" "-w"];

  meta = {
    description = "APTS Stage 1 operator CLI (canonical action, approval, mTLS)";
    license = lib.licenses.mit;
    mainProgram = "redteam-cli";
    platforms = ["x86_64-linux"];
  };
}
