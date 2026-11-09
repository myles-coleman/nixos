{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  nodejs_24,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "juice-shop";
  version = "20.4.0";

  # Pinned upstream release tarball, not a floating tag. The digest is the
  # GitHub release asset's SHA-256 (spec 31, Task 3.1).
  src = fetchurl {
    url = "https://github.com/juice-shop/juice-shop/releases/download/v${finalAttrs.version}/juice-shop-${finalAttrs.version}_node24_linux_x64.tgz";
    sha256 = "dbc3d5d17edb85f908d6807a5a9b42e0e2c652fc595bdca8032ef4f30c420d8d";
  };

  nativeBuildInputs = [autoPatchelfHook makeWrapper];
  buildInputs = [stdenv.cc.cc.lib zlib];

  # The upstream tarball carries broken symlinks in node-gyp's test fixtures.
  # They are not used at runtime, so tolerate the extraction warnings and drop
  # the directory in installPhase.
  unpackPhase = ''
    runHook preUnpack
    tar --no-same-owner -xzf "$src" || true
    runHook postUnpack
  '';

  sourceRoot = "juice-shop_${finalAttrs.version}-SNAPSHOT";

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/juice-shop"
    cp -a . "$out/share/juice-shop/"
    rm -rf "$out/share/juice-shop/node_modules/sqlite3/node_modules/node-gyp"
    runHook postInstall
  '';

  postFixup = ''
    makeWrapper ${nodejs_24}/bin/node "$out/bin/juice-shop" \
      --add-flags "$out/share/juice-shop/build/app.js"
  '';

  meta = {
    description = "OWASP Juice Shop, pinned release tarball for the spec 31 target";
    homepage = "https://owasp.org/www-project-juice-shop/";
    license = lib.licenses.mit;
    mainProgram = "juice-shop";
    platforms = ["x86_64-linux"];
  };
})
