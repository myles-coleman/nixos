{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "redteam-broker";
  version = "0.1.0";

  src = ./.;
  vendorHash = "sha256-NBAiC6/+FcCV1jEfEBe06++RrEm6ZXrGWqmZrmI9W6E=";

  subPackages = ["cmd/broker"];
  env.CGO_ENABLED = 0;
  ldflags = ["-s" "-w"];

  meta = {
    description = "APTS Stage 1 red-team broker (scope compiler, policy PEP, lab proxy)";
    license = lib.licenses.mit;
    mainProgram = "broker";
    platforms = ["x86_64-linux"];
  };
}
