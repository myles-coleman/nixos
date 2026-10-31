# LearnHarness — repackaged upstream Linux release.
#
# Upstream (github.com/amosblomqvist/learnharness, AGPL-3.0-only) ships an
# AppImage whose payload is a two-part Electron app:
#
#   resources/app.asar   the Electron shell (electron/main.cjs, electron-updater, jose)
#   resources/server/    a Next.js 16 standalone server the shell spawns as a
#                        child process with ELECTRON_RUN_AS_NODE=1
#
# The AppImage cannot be executed on NixOS (its runtime needs a system loader)
# and it carries its own glibc-pinned Electron, so we reuse only the upstream
# payload and pair it with the nixpkgs Electron. Deliberate differences from
# the AppImage:
#
#   * app.asar is unpacked to resources/app/ and its updater is switched off
#     under LH_DISABLE_UPDATER=1 — in-app updates would try to replace files
#     inside /nix/store. Bump `version` + `hash` to update instead.
#   * the bundled native modules get an RPATH into nixpkgs glibc/libstdc++.
#   * CHROME_DEVEL_SANDBOX points at the packaged helper; without it Chromium's
#     zygote traps with SIGILL instead of falling back to the namespace sandbox.
#   * upstream's AppRun and its `--no-sandbox` desktop Exec are dropped; the
#     sandbox stays on.
#
# Known and harmless: `require("sharp")` segfaults in this tree (its bundled
# libvips dies in a static init). Nothing imports it — sharp is only Next's
# optional /_next/image dependency, and upstream deliberately keeps app code
# off it ("one native image lib per process", src/agent/subagents/headless.ts).
#
# The payload is x86_64-only: upstream publishes no Linux arm64 build, and
# scripts/build-server.mjs deliberately does not cross-build the Next trace.
{
  lib,
  stdenv,
  fetchurl,
  electron,
  python3,
  squashfsTools,
  patchelf,
  makeWrapper,
  gtk3,
  gsettings-desktop-schemas,
  dconf,
  librsvg,
  glibc,
}: let
  version = "0.4.1";

  appimage = fetchurl {
    url = "https://github.com/amosblomqvist/learnharness/releases/download/v${version}/LearnHarness-${version}-x86_64.AppImage";
    hash = "sha256-n8aA23BE2DD7yePDAbuWcLc29jo22bYivln2toh3DNg=";
  };

  # Native modules in the Next trace: @resvg/resvg-js, @napi-rs/canvas and
  # sharp (plus its bundled libvips). All of them need nothing beyond
  # glibc + libstdc++/libgcc.
  rpath = lib.makeLibraryPath [glibc stdenv.cc.cc.lib];

  payload = stdenv.mkDerivation {
    pname = "learnharness-payload";
    inherit version;

    src = appimage;
    dontUnpack = true;
    dontStrip = true;
    dontPatchELF = true;

    nativeBuildInputs = [
      python3
      squashfsTools
      patchelf
    ];

    buildPhase = ''
      runHook preBuild

      python3 ${./unpack-appimage.py} $src payload.squashfs
      unsquashfs -q -n -d unpacked payload.squashfs

      python3 ${./extract-asar.py} unpacked/resources/app.asar shell

      # In-app updates must never run against a read-only store path.
      substituteInPlace shell/electron/main.cjs \
        --replace-fail \
        'if (!app.isPackaged) {' \
        'if (!app.isPackaged || process.env.LH_DISABLE_UPDATER === "1") {'

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r shell $out/app
      cp -r unpacked/resources/server $out/server
      cp -r unpacked/resources/licenses $out/licenses
      cp unpacked/learnharness.png $out/icon.png

      runHook postInstall
    '';

    postFixup = ''
      while IFS= read -r -d "" native; do
        if head -c 4 "$native" | grep -q ELF; then
          # --add-rpath, never --set-rpath: sharp's prebuilt .node and libvips
          # carry $ORIGIN-relative entries that must survive.
          patchelf --add-rpath ${rpath} "$native"
        fi
      done < <(find $out/server -type f \( -name '*.node' -o -name '*.so*' \) -print0)
    '';
  };
in
  stdenv.mkDerivation {
    pname = "learnharness";
    inherit version;

    dontUnpack = true;
    dontStrip = true;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/learnharness
      cp -r ${electron}/libexec/electron/. $out/lib/learnharness/
      chmod -R u+w $out/lib/learnharness
      # The unpacked shell only wins over the archive if no archive is present.
      rm -f $out/lib/learnharness/resources/default_app.asar
      cp -r ${payload}/app $out/lib/learnharness/resources/app
      cp -r ${payload}/server $out/lib/learnharness/resources/server
      cp -r ${payload}/licenses $out/lib/learnharness/resources/licenses

      install -Dm644 ${payload}/icon.png $out/share/icons/hicolor/512x512/apps/learnharness.png
      install -Dm644 ${./learnharness.desktop} $out/share/applications/learnharness.desktop

      runHook postInstall
    '';

    postFixup = ''
      makeWrapper $out/lib/learnharness/electron $out/bin/learnharness \
        --set CHROME_DEVEL_SANDBOX $out/lib/learnharness/chrome-sandbox \
        --set LH_DISABLE_UPDATER 1 \
        --prefix XDG_DATA_DIRS : ${gtk3}/share/gsettings-schemas/${gtk3.name} \
        --prefix XDG_DATA_DIRS : ${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name} \
        --suffix GIO_EXTRA_MODULES : ${dconf}/lib/gio/modules \
        --set GDK_PIXBUF_MODULE_FILE ${librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
    '';

    meta = {
      description = "Agent harness for learning: adaptive teaching, practice, and a persistent knowledge graph";
      homepage = "https://github.com/amosblomqvist/learnharness";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "learnharness";
      platforms = ["x86_64-linux"];
    };
  }
