{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.pikvm;

  # ── pyghmi: Python IPMI library needed by kvmd ──────────────────────
  pyghmi = pkgs.python3.pkgs.buildPythonPackage rec {
    pname = "pyghmi";
    version = "1.5.69";
    pyproject = true;

    src = pkgs.python3.pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-+qNJWylZx22gBjqE82cNEchwUQUPau+4uGd7dK3wWUY=";
    };

    nativeBuildInputs = with pkgs.python3.pkgs; [setuptools wheel];
    propagatedBuildInputs = with pkgs.python3.pkgs; [cryptography python-dateutil six pbr];
    pythonImportsCheck = ["pyghmi"];
  };

  # ── ustreamer: lightweight MJPG/H.264 video streamer ────────────────
  patchedJanus = pkgs.runCommand "janus-gateway-ustreamer-patched" {} ''
    cp -r --no-preserve=mode ${pkgs.janus-gateway.dev} $out
    cp $out/include/janus/refcount.h $out/include/janus/plugins/refcount.h
  '';

  ustreamer = pkgs.stdenv.mkDerivation rec {
    pname = "ustreamer";
    version = "6.12";

    src = pkgs.fetchFromGitHub {
      owner = "pikvm";
      repo = "ustreamer";
      rev = "v${version}";
      hash = "sha256-iaCgPHgklk7tbhJhQmyjKggb1bMWBD+Zurgfk9sCQ3E=";
    };

    buildInputs = with pkgs; [
      libbsd
      libevent
      libjpeg
      libdrm
      patchedJanus
      glib
      alsa-lib
      jansson
      speex
      libopus
    ];

    nativeBuildInputs = [pkgs.pkg-config];

    makeFlags = [
      "PREFIX=${placeholder "out"}"
      "WITH_V4P=1"
      "WITH_JANUS=1"
    ];

    enableParallelBuilding = true;

    meta = with lib; {
      homepage = "https://github.com/pikvm/ustreamer";
      description = "Lightweight and fast MJPG-HTTP streamer";
      license = licenses.gpl3Plus;
      platforms = platforms.linux;
    };
  };

  # ── ustreamer python bindings (needed by kvmd) ──────────────────────
  ustreamer-python = pkgs.python3.pkgs.buildPythonPackage {
    pname = "ustreamer";
    version = ustreamer.version;
    src = ustreamer.src;
    prePatch = ''
      cd python
    '';
  };

  # ── kvmd: the main PiKVM daemon ─────────────────────────────────────
  kvmd = pkgs.python3.pkgs.buildPythonApplication rec {
    pname = "kvmd";
    version = "4.2";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "pikvm";
      repo = "kvmd";
      rev = "v${version}";
      hash = "sha256-c/E9ce9cy0AScEVb8KsTZ7zmk8rpsiW0RnkgrOLYufw=";
    };

    nativeBuildInputs = with pkgs.python3.pkgs; [setuptools wheel pkgs.makeWrapper];

    propagatedBuildInputs = with pkgs.python3.pkgs; [
      ustreamer-python
      pyyaml
      aiohttp
      aiofiles
      async-lru
      passlib
      pyotp
      qrcode
      python-periphery
      pyserial
      pyserial-asyncio
      spidev
      setproctitle
      psutil
      netifaces
      systemd
      dbus-python
      dbus-next
      pygments
      pyghmi
      pam
      pillow
      xlib
      zstandard
      libgpiod
      mako
    ];

    buildInputs = [pkgs.libxkbcommon];

    # Replace hardcoded Arch Linux paths with Nix store paths
    patchPhase = ''
      runHook prePatch

      substituteInPlace kvmd/libc.py \
        --replace-fail 'ctypes.util.find_library("c")' '"${pkgs.stdenv.cc.libc}/lib/libc.so.6"'
      substituteInPlace kvmd/keyboard/printer.py \
        --replace-fail 'ctypes.util.find_library("xkbcommon")' '"${pkgs.libxkbcommon}/lib/libxkbcommon.so"'
      substituteInPlace kvmd/apps/kvmd/ocr.py \
        --replace-fail 'ctypes.util.find_library("tesseract")' '"${pkgs.tesseract}/lib/libtesseract.so"'

      cd configs/os/services
      rm -f kvmd-certbot* kvmd-nginx* kvmd-janus-static*
      for i in $(find -name '*.service'); do
        substituteInPlace $i \
          --replace '/usr/bin/kvmd' "$out/bin/kvmd" \
          --replace '/usr/bin/ustreamer' '${ustreamer}/bin/ustreamer'
      done
      cd -

      for i in $(find -name '*.py'); do
        substituteInPlace $i \
          --replace '/usr/share/kvmd' "$out/share" \
          --replace '/usr/bin/kvmd-' "$out/bin/kvmd-" \
          --replace '/usr/bin/vcgencmd' "${pkgs.libraspberrypi}/bin/vcgencmd" \
          --replace '/bin/true' "${pkgs.coreutils}/bin/true" \
          --replace '/usr/bin/sudo' "/run/wrappers/bin/sudo" \
          --replace '/usr/bin/kvmd-helper-pst-remount' "$out/bin/kvmd-helper-pst-remount" \
          --replace '/usr/bin/ip' "${pkgs.iproute2}/bin/ip" \
          --replace '/usr/sbin/iptables' "${pkgs.iptables}/bin/iptables" \
          --replace '/usr/bin/systemd-run' "${pkgs.systemdMinimal}/bin/systemd-run" \
          --replace '/usr/bin/systemctl' "${pkgs.systemdMinimal}/bin/systemctl" \
          --replace '/etc/kvmd/ipmipasswd' '${builtins.toFile "dummy.txt" ""}' \
          --replace '/etc/kvmd/vnc/ssl/server.crt' '${builtins.toFile "dummy.txt" ""}' \
          --replace '/etc/kvmd/vnc/ssl/server.key' '${builtins.toFile "dummy.txt" ""}' \
          --replace '/etc/kvmd/vncpasswd' '${builtins.toFile "dummy.txt" ""}' \
          --replace '/usr/bin/janus' '${pkgs.janus-gateway}/bin/janus' \
          --replace '/bin/mount' '/run/wrappers/bin/mount' \
          --replace '/usr/share/tessdata' '${pkgs.tesseract}/share' \
          --replace '/usr/lib/ustreamer/janus' '${ustreamer}/lib/ustreamer/janus'
      done

      runHook postPatch
    '';

    postFixup = ''
      mkdir -p $out/share $out/lib/systemd/system
      cp ${pkgs.janus-gateway.doc}/share/janus/javascript/janus.js web/share/js/kvm/janus.js || true
      cp -r {hid,web,extras,contrib/keymaps,configs/*} $out/share || true
      cp configs/os/services/*.service $out/lib/systemd/system || true
    '';

    # Tests require /etc/kvmd/main.yaml to exist (hardcoded in argparse defaults)
    doCheck = false;

    meta = with lib; {
      description = "The main PiKVM daemon";
      homepage = "https://github.com/pikvm/kvmd";
      license = licenses.gpl3Only;
      mainProgram = "kvmd";
    };
  };

  # ── Generated main.yaml with real nix store paths ───────────────────
  mainYaml = pkgs.writeText "kvmd-main.yaml" ''
    # PiKVM main configuration
    logging: !include logging.yaml

    kvmd:
        auth:
            internal:
                file: /etc/kvmd/empty_file

        info:
            meta: /etc/kvmd/meta.yaml
            fan:
                unix: /run/kvmd/fan.sock

        hid:
            mouse:
                absolute: false
            type: otg

        atx:
            type: gpio

        msd:
            type: otg

        streamer:
            h264_bitrate:
                default: 5000
            cmd:
                - "${ustreamer}/bin/ustreamer"
                - "--device=/dev/kvmd-video"
                - "--persistent"
                - "--dv-timings"
                - "--format=uyvy"
                - "--encoder=m2m-image"
                - "--buffers=6"
                - "--workers=3"
                - "--quality={quality}"
                - "--desired-fps={desired_fps}"
                - "--drop-same-frames=30"
                - "--unix={unix}"
                - "--unix-rm"
                - "--unix-mode=0660"
                - "--exit-on-parent-death"
                - "--process-name-prefix={process_name_prefix}"
                - "--notify-parent"
                - "--no-log-colors"
                - "--jpeg-sink=kvmd::ustreamer::jpeg"
                - "--jpeg-sink-mode=0660"
                - "--h264-sink=kvmd::ustreamer::h264"
                - "--h264-sink-mode=0660"
                - "--h264-bitrate={h264_bitrate}"
                - "--h264-gop={h264_gop}"

        gpio:
            scheme:
                __v3_usb_breaker__:
                    pin: 5
                    mode: output
                    initial: true
                    pulse: false

    vnc:
        memsink:
            jpeg:
                sink: "kvmd::ustreamer::jpeg"
            h264:
                sink: "kvmd::ustreamer::h264"
  '';
in {
  options.services.pikvm = {
    enable = lib.mkEnableOption "PiKVM - KVM over IP using Raspberry Pi";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "pikvm";
      description = "Hostname shown in the PiKVM web interface";
    };

    videoDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/kvmd-video";
      description = "Path to the HDMI capture video device";
    };

    enableJanus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Janus WebRTC gateway for low-latency H.264 video";
    };

    enableVNC = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable VNC proxy to KVMD";
    };

    enableIPMI = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IPMI proxy to KVMD";
    };

    enableOTGNet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OTG network (Ethernet over USB gadget)";
    };

    enableWatchdog = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable RTC-based hardware watchdog";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Port for the nginx reverse proxy to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Packages available on system ──────────────────────────────────
    environment.systemPackages = [kvmd ustreamer];

    # ── Config files in /etc/kvmd ─────────────────────────────────────
    environment.etc = {
      "kvmd/main.yaml".source = mainYaml;
      "kvmd/logging.yaml".source = ../config/pikvm/logging.yaml;
      "kvmd/meta.yaml".source = ../config/pikvm/meta.yaml;
      "kvmd/empty_file".text = "";
      "kvmd/tc358743-edid.hex".source = "${kvmd}/share/kvmd/edid/v3.hex";
    };

    # ── Users & groups ────────────────────────────────────────────────
    users.users.kvmd = {
      isSystemUser = true;
      group = "kvmd";
      extraGroups = [
        "gpio"
        "video"
      ];
    };
    users.groups.kvmd = {};
    users.groups.gpio = {};

    users.users.kvmd-janus = lib.mkIf cfg.enableJanus {
      isSystemUser = true;
      group = "kvmd-janus";
      extraGroups = ["kvmd" "gpio" "video"];
    };
    users.groups.kvmd-janus = lib.mkIf cfg.enableJanus {};

    users.users.nginx.extraGroups = ["kvmd"] ++ lib.optional cfg.enableJanus "kvmd-janus";

    # ── Sudo rules ────────────────────────────────────────────────────
    security.sudo.extraConfig = ''
      kvmd ALL=(ALL) NOPASSWD: ${kvmd}/bin/kvmd-helper-otgmsd-remount
    '';

    # ── Core services ─────────────────────────────────────────────────

    # kvmd-otg: USB OTG gadget setup (keyboard/mouse emulation)
    systemd.services.kvmd-otg = {
      description = "PiKVM - OTG setup";
      after = ["systemd-modules-load.service"];
      before = ["kvmd.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${kvmd}/bin/kvmd-otg start";
        ExecStop = "${kvmd}/bin/kvmd-otg stop";
        RemainAfterExit = true;
      };
      wantedBy = ["multi-user.target"];
    };

    # kvmd-edid-loader: Load EDID for HDMI capture chip
    systemd.services.kvmd-edid-loader = {
      description = "PiKVM - EDID loader for TC358743";
      wants = ["dev-kvmd\\x2dvideo.device"];
      after = ["dev-kvmd\\x2dvideo.device" "systemd-modules-load.service"];
      before = ["kvmd.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.v4l-utils}/bin/v4l2-ctl --device=${cfg.videoDevice} --set-edid=file=/etc/kvmd/tc358743-edid.hex --fix-edid-checksums --info-edid";
        ExecStop = "${pkgs.coreutils}/bin/true";
        RemainAfterExit = true;
      };
      wantedBy = ["multi-user.target"];
    };

    # kvmd: The main PiKVM daemon
    systemd.services.kvmd = {
      description = "PiKVM - The main daemon";
      after = ["network.target" "network-online.target" "nss-lookup.target"];
      serviceConfig = {
        User = "kvmd";
        Group = "kvmd";
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        AmbientCapabilities = "CAP_NET_RAW";
        ExecStart = "${kvmd}/bin/kvmd --run";
        ExecStopPost = "${kvmd}/bin/kvmd-cleanup --run";
        TimeoutStopSec = 10;
        KillMode = "mixed";
      };
      wantedBy = ["multi-user.target"];
    };

    # ── Janus WebRTC Gateway ──────────────────────────────────────────
    systemd.services.kvmd-janus = lib.mkIf cfg.enableJanus {
      description = "PiKVM - Janus WebRTC Gateway";
      after = ["network.target" "network-online.target" "nss-lookup.target" "kvmd.service"];
      serviceConfig = {
        User = "kvmd-janus";
        Group = "kvmd-janus";
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        AmbientCapabilities = "CAP_NET_RAW";
        LimitNOFILE = 65536;
        UMask = "0117";
        ExecStart = "${kvmd}/bin/kvmd-janus --run";
        TimeoutStopSec = 10;
        KillMode = "mixed";
      };
      wantedBy = ["multi-user.target"];
    };

    # ── Optional services ─────────────────────────────────────────────

    systemd.services.kvmd-vnc = lib.mkIf cfg.enableVNC {
      description = "PiKVM - VNC to KVMD/Streamer proxy";
      after = ["kvmd.service"];
      serviceConfig = {
        User = "kvmd-vnc";
        Group = "kvmd-vnc";
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        ExecStart = "${kvmd}/bin/kvmd-vnc --run";
        TimeoutStopSec = 3;
      };
      wantedBy = ["multi-user.target"];
    };

    systemd.services.kvmd-ipmi = lib.mkIf cfg.enableIPMI {
      description = "PiKVM - IPMI to KVMD proxy";
      after = ["kvmd.service"];
      serviceConfig = {
        User = "kvmd-ipmi";
        Group = "kvmd-ipmi";
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        ExecStart = "${kvmd}/bin/kvmd-ipmi --run";
        TimeoutStopSec = 3;
      };
      wantedBy = ["multi-user.target"];
    };

    systemd.services.kvmd-otgnet = lib.mkIf cfg.enableOTGNet {
      description = "PiKVM - OTG network service";
      after = ["kvmd-otg.service" "network-pre.target"];
      wants = ["network-pre.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${kvmd}/bin/kvmd-otgnet start";
        ExecStop = "${kvmd}/bin/kvmd-otgnet stop";
        RemainAfterExit = true;
      };
      wantedBy = ["multi-user.target"];
    };

    systemd.services.kvmd-watchdog = lib.mkIf cfg.enableWatchdog {
      description = "PiKVM - RTC-based hardware watchdog";
      after = ["systemd-modules-load.service"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        ExecStart = "${kvmd}/bin/kvmd-watchdog run";
        TimeoutStopSec = 3;
      };
      wantedBy = ["multi-user.target"];
    };

    # ── Nginx reverse proxy ───────────────────────────────────────────
    services.nginx = {
      enable = true;
      upstreams =
        {
          ustreamer.servers = {
            "unix:/run/kvmd/ustreamer.sock" = {
              fail_timeout = "0s";
              max_fails = 0;
            };
          };
          kvmd.servers = {
            "unix:/run/kvmd/kvmd.sock" = {
              fail_timeout = "0s";
              max_fails = 0;
            };
          };
        }
        // lib.optionalAttrs cfg.enableJanus {
          janus-ws.servers = {
            "unix:/run/kvmd/janus-ws.sock" = {
              fail_timeout = "0s";
              max_fails = 0;
            };
          };
        };
      virtualHosts."pikvm" = {
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.listenPort;
          }
        ];
        extraConfig =
          ''
            absolute_redirect off;
            index index.html;
            auth_request /auth_check;

            location = /auth_check {
              internal;
              proxy_pass http://kvmd/auth/check;
              proxy_pass_request_body off;
              proxy_set_header Content-Length "";
              auth_request off;
            }

            location / {
              root ${kvmd}/share/web;
              include ${kvmd}/share/nginx/loc-login.conf;
              include ${kvmd}/share/nginx/loc-nocache.conf;
            }

            location @login {
              return 302 /login;
            }

            location /login {
              root ${kvmd}/share/web;
              auth_request off;
            }

            location /share {
              root ${kvmd}/share/web;
              include ${kvmd}/share/nginx/loc-nocache.conf;
              auth_request off;
            }

            location = /favicon.ico {
              alias ${kvmd}/share/web/favicon.ico;
              include ${kvmd}/share/nginx/loc-nocache.conf;
              auth_request off;
            }

            location = /robots.txt {
              alias ${kvmd}/share/web/robots.txt;
              include ${kvmd}/share/nginx/loc-nocache.conf;
              auth_request off;
            }

            location /api/ws {
              rewrite ^/api/ws$ /ws break;
              rewrite ^/api/ws\?(.*)$ /ws?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-websocket.conf;
              auth_request off;
            }

            location /api/hid/print {
              rewrite ^/api/hid/print$ /hid/print break;
              rewrite ^/api/hid/print\?(.*)$ /hid/print?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-bigpost.conf;
              auth_request off;
            }

            location /api/msd/read {
              rewrite ^/api/msd/read$ /msd/read break;
              rewrite ^/api/msd/read\?(.*)$ /msd/read?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-nobuffering.conf;
              proxy_read_timeout 7d;
              auth_request off;
            }

            location /api/msd/write_remote {
              rewrite ^/api/msd/write_remote$ /msd/write_remote break;
              rewrite ^/api/msd/write_remote\?(.*)$ /msd/write_remote?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-nobuffering.conf;
              proxy_read_timeout 7d;
              auth_request off;
            }

            location /api/msd/write {
              rewrite ^/api/msd/write$ /msd/write break;
              rewrite ^/api/msd/write\?(.*)$ /msd/write?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-bigpost.conf;
              auth_request off;
            }

            location /api/log {
              rewrite ^/api/log$ /log break;
              rewrite ^/api/log\?(.*)$ /log?$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-nobuffering.conf;
              proxy_read_timeout 7d;
              auth_request off;
            }

            location /api {
              rewrite ^/api$ / break;
              rewrite ^/api/(.*)$ /$1 break;
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              auth_request off;
            }

            location /streamer {
              rewrite ^/streamer$ / break;
              rewrite ^/streamer\?(.*)$ ?$1 break;
              rewrite ^/streamer/(.*)$ /$1 break;
              proxy_pass http://ustreamer;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-nobuffering.conf;
            }

            location /redfish {
              proxy_pass http://kvmd;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              auth_request off;
            }
          ''
          + lib.optionalString cfg.enableJanus ''

            location /janus/ws {
              rewrite ^/janus/ws$ / break;
              rewrite ^/janus/ws\?(.*)$ /?$1 break;
              proxy_pass http://janus-ws;
              include ${kvmd}/share/nginx/loc-proxy.conf;
              include ${kvmd}/share/nginx/loc-websocket.conf;
            }

            location = /share/js/kvm/janus.js {
              alias ${pkgs.janus-gateway.doc}/share/janus/javascript/janus.js;
              include ${kvmd}/share/nginx/loc-nocache.conf;
            }
          '';
      };
    };

    # ── Kernel modules for USB gadget ─────────────────────────────────
    boot.kernelModules = [
      "dwc2"
      "libcomposite"
      "tc358743"
      "bcm2835-unicam"
    ];

    # ── Udev rules for video device symlink ───────────────────────────
    services.udev.extraRules = ''
      SUBSYSTEM=="video4linux", ATTR{name}=="unicam-image",  SYMLINK+="kvmd-video", TAG+="systemd"
      SUBSYSTEM=="video4linux", ATTR{name}=="*TC358743*",  SYMLINK+="kvmd-video", TAG+="systemd"
      SUBSYSTEM=="video4linux", ATTR{name}=="*UVC*",       SYMLINK+="kvmd-video", TAG+="systemd"
      SUBSYSTEM=="video4linux", ATTR{name}=="*USB Video*", SYMLINK+="kvmd-video", TAG+="systemd"
      SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
      KERNEL=="hidg0", SUBSYSTEM=="hidg", SYMLINK+="kvmd-hid-keyboard", GROUP="kvmd", MODE="0660"
      KERNEL=="hidg1", SUBSYSTEM=="hidg", SYMLINK+="kvmd-hid-mouse",    GROUP="kvmd", MODE="0660"
    '';

    # ── MSD (virtual USB drive) loopback image ─────────────────────────
    systemd.services.kvmd-msd-image = {
      description = "PiKVM - Create MSD loopback image";
      before = ["kvmd.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        IMG=/var/lib/kvmd/msd/msd.img
        MNT=/var/lib/kvmd/msd/mount
        mkdir -p "$MNT"
        if [ ! -f "$IMG" ]; then
          ${pkgs.coreutils}/bin/truncate -s 256M "$IMG"
          ${pkgs.dosfstools}/bin/mkfs.vfat "$IMG"
        fi
        ${pkgs.util-linux}/bin/mount -o loop,rw,uid=kvmd,gid=kvmd "$IMG" "$MNT"
      '';
      preStop = ''
        ${pkgs.util-linux}/bin/umount /var/lib/kvmd/msd/mount || true
      '';
      wantedBy = ["multi-user.target"];
    };

    # fstab entry for MSD — kvmd parses fstab for X-kvmd.otgmsd-root option
    fileSystems."/var/lib/kvmd/msd/mount" = {
      device = "/var/lib/kvmd/msd/msd.img";
      fsType = "vfat";
      options = ["loop" "nofail" "noauto" "X-kvmd.otgmsd-root=/var/lib/kvmd/msd/mount" "X-kvmd.otgmsd-user=kvmd"];
    };

    # ── Tmpfiles for runtime directories ──────────────────────────────
    systemd.tmpfiles.rules = [
      "d /run/kvmd 0770 kvmd kvmd -"
      "d /var/lib/kvmd 0770 kvmd kvmd -"
      "d /var/lib/kvmd/msd 0770 kvmd kvmd -"
      "d /var/lib/kvmd/msd/mount 0770 kvmd kvmd -"
      "d /var/lib/kvmd/pst 0770 kvmd kvmd -"
    ];

    # ── Firewall ──────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = [cfg.listenPort];
  };
}
