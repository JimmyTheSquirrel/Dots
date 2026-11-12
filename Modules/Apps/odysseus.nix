# ══════════════════════════════════════════════════════════════════════════════
# Odysseus — the self-hosted AI workspace (chat, agents, research, documents,
# email, notes, calendar) from github.com/odysseus-dev/odysseus. AGPL-3.0.
# Four containers: the app, ChromaDB (vector store), SearXNG (web search for
# the research feature) and ntfy (notifications).
#
# WHY SISYPHUS AND NOT ASGARD
# The app itself is CPU-only and would be happier on the server, but its
# "Cookbook" page is how models get installed: it downloads from HuggingFace,
# pip-installs a serving engine (llama.cpp / vLLM) INSIDE this container, and
# serves on whatever GPU Docker shows it. Asgard's only GPU is the i5-14400's
# UHD 730 iGPU — fine for Jellyfin's QSV transcoding, useless for inference —
# so Cookbook has to sit next to the RX 9060 XT. The trade accepted here is
# that the workspace is only up while the desktop is. Pointing the app at an
# OpenAI-compatible endpoint instead (Settings → endpoints, or LLM_HOSTS, which
# scans for Ollama on :11434) would free it to live on Asgard — that is the
# alternative if the desktop-only window starts to chafe.
#
# ⚠️ WHAT IS NOT DECLARATIVE
# Everything Cookbook installs. Models land in data/huggingface and the
# pip-installed serve engines in data/local — volume state Nix knows nothing
# about, the same category as the noctalia layout and the wallpapers in
# Claude/next-up.md's wipe gaps. The app's own settings (endpoints, accounts,
# chats, notes) live in its SQLite DB under data/ as well. Nix owns the
# deployment — images, ports, devices, paths, the SearXNG config — and the app
# owns its contents. A fresh install comes up empty and ready, not populated.
#
# ⚠️ GPU PASSTHROUGH IS DELIBERATELY NARROW
# Only /dev/kfd and renderD128 go in, NOT all of /dev/dri. On this machine
# renderD128 is the RX 9060 XT (1002:7590) and renderD129 is the Ryzen iGPU
# (1002:13C0) — and upstream warns Cookbook "sees the iGPU, another card, or
# CPU instead of your intended GPU" when passthrough is loose. Passing one node
# removes the choice. Verify after a deploy with:
#
#   docker exec odysseus sh -lc 'ls -l /dev/kfd /dev/dri/renderD*'
#
# The slim image ships no ROCm userspace at all, so Cookbook → Dependencies has
# to fetch a ROCm build of the engine itself. This card is gfx1200 (RDNA4),
# which needs ROCm ≥ 6.4 — new enough that it may not work first try. If an
# engine installs but cannot see the card, HSA_OVERRIDE_GFX_VERSION is the
# first knob to reach for; it is NOT set here, because a wrong override is
# worse than none at all.
#
# ⚠️ THE DOCKER SOCKET IS NOT MOUNTED
# Upstream's docker/host-docker.yml overlay exists for Cookbook's "manage the
# local Docker daemon" flow and says plainly that socket access "can
# effectively grant broad control over the host Docker daemon". Serving models
# in-container needs none of it, and on this host that same socket is what Wolf
# drives to spawn game containers (Modules/Gaming/wolf.nix). Left out.
#
# Reachability: every port binds 127.0.0.1, so this is a localhost-only app on
# Sisyphus — nothing is opened in networking.firewall and the tailnet cannot
# see it. It holds email and calendar once those are connected; if it ever
# needs to be reachable from elsewhere, do it with `tailscale serve` the way
# MarsBar does (Modules/Server/marsbar.nix), never an open port.
# ══════════════════════════════════════════════════════════════════════════════
{ ... }: {
  flake.nixosModules.odysseus = { config, lib, pkgs, activeUser, ... }:
  let
    dataDir = "/var/lib/odysseus";

    # A user-defined bridge so the four containers resolve each other by name.
    # `networks` below only ATTACHES to a network — nothing in nixpkgs creates
    # one — hence odysseus-network.service further down.
    net = "odysseus";

    # The backend is whatever the host already chose; Sisyphus is "docker",
    # set by Modules/Gaming/wolf.nix. Deliberately not set here: that option
    # takes a single value and declaring it twice is a conflict.
    backend = config.virtualisation.oci-containers.backend;
    backendPkg =
      if backend == "docker" then config.virtualisation.docker.package
      else config.virtualisation.podman.package;
    # oci-containers names its units "<backend>-<container>". unitName is the
    # systemd.services key (no suffix); unitOf is the full unit name, for
    # After=/Before=/WantedBy=.
    unitName = name: "${backend}-${name}";
    unitOf = name: "${unitName name}.service";
    containerNames = [ "odysseus" "odysseus-chromadb" "odysseus-searxng" "odysseus-ntfy" ];

    # Host-side ports. Only these two are published: the UI, and ntfy (the
    # browser talks to it directly). ChromaDB and SearXNG are reachable on the
    # container network and have no business on the host at all — which also
    # keeps SearXNG off :8080, where it would be a nuisance.
    appPort = 7011;
    ntfyPort = 8091;

    # Pinned by digest, not tag. Upstream's own compose warns that ":latest and
    # bare :X.Y.Z tags move on every main push" — and this project pushes to
    # main most days, so a tag would mean the app silently changing version
    # under a rebuild that touched nothing. Resolved from :latest 2026-11-11.
    # To take an upgrade deliberately:
    #   skopeo inspect docker://ghcr.io/odysseus-dev/odysseus:latest | grep Digest
    odysseusImage =
      "ghcr.io/odysseus-dev/odysseus@sha256:5117c5e07e5976095ce213e601277ff372e0387a67de34c5fd59a3de723e6113";

    # The other three keep upstream's own pins verbatim. SearXNG in particular
    # is pinned upstream for a reason: the app waits on its healthcheck, and a
    # broken `latest` there blocks the whole stack from starting.
    chromaImage = "docker.io/chromadb/chroma:1.5.9@sha256:1e0b73a187a28757c572acba508c46f48c9e8b0acaf5c20e6d95cdedce1acdf6";
    searxngImage = "docker.io/searxng/searxng:2026.10.24-ef0ec03da@sha256:7c7cbe509429e82755104b2a95f52085a98633c95d53f44e4e905fa3a59f08c8";
    ntfyImage = "docker.io/binwiederhier/ntfy:v2.32.0@sha256:59250e1d8be2ee2186c4560322f625faef22ace380331f05b63f8842dbd62602";

    # renderD128 is the dGPU — see the header. Not /dev/dri wholesale.
    renderNode = "/dev/dri/renderD128";

    # ⭐ THE INFERENCE ENGINE. Cookbook's serve script runs a bare
    # `llama-server`, and the slim image ships none — so it tries to COMPILE
    # llama.cpp inside the container, fails for want of a toolchain, and falls
    # back to a pip `llama-cpp-python` wheel. That wheel is CPU-only: the UI
    # then reports "llama.cpp ready", the launch command still sets
    # HIP_VISIBLE_DEVICES=0, and the model loads into SYSTEM RAM and runs at
    # ~3 tok/s. The giveaway in the serve log is:
    #   done_getting_tensors: ... cannot be used with preferred buffer type
    #   CPU_REPACK, using CPU instead
    # and VRAM use that never climbs off the desktop's ~1.3 GiB.
    #
    # So we hand it a real binary instead. nixpkgs' llama-cpp with ROCm is
    # fully cached (0 builds, ~2.1 GiB fetch) and its CMAKE_HIP_ARCHITECTURES
    # already lists gfx1200 — this exact card — against ROCm 7.2.3, well past
    # the 6.4 that RDNA4 needs. This is also why HSA_OVERRIDE_GFX_VERSION
    # stays unset: the card is genuinely supported, nothing needs faking.
    llamaCpp = pkgs.llama-cpp.override { rocmSupport = true; };
  in {
    # ── Paths ────────────────────────────────────────────────────────────────
    # data/ and logs/ are owned by the user the container drops to (PUID/PGID
    # below), so bind-mounted files stay editable from the host. The rest is
    # root-owned; each image sorts out its own ownership on first boot.
    systemd.tmpfiles.rules = [
      "d ${dataDir}                    0750 root        root  -"
      "d ${dataDir}/data               0750 ${activeUser} users -"
      "d ${dataDir}/logs               0750 ${activeUser} users -"
      # Cookbook generates an SSH identity here for its remote-server flow.
      "d ${dataDir}/data/ssh           0700 ${activeUser} users -"
      # Downloaded model weights. Tens of GB each — this is what eats the disk.
      "d ${dataDir}/data/huggingface   0750 ${activeUser} users -"
      # pip-installed serve engines (vLLM, llama-cpp-python). Persisted so a
      # container recreate does not silently remove them.
      "d ${dataDir}/data/local         0750 ${activeUser} users -"
      "d ${dataDir}/chromadb           0750 root        root  -"
      "d ${dataDir}/ntfy               0750 root        root  -"
      "d ${dataDir}/searxng            0755 root        root  -"
    ];

    # ── The container network ────────────────────────────────────────────────
    systemd.services = lib.mkMerge [ {
      odysseus-network = {
      description = "Create the Odysseus container network";
      after = [ "${backend}.service" ];
      requires = [ "${backend}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${backend} network inspect ${net} >/dev/null 2>&1 \
          || ${backend} network create ${net}
      '';
      path = [ backendPkg ];
      };

    # ── Generated config: SearXNG settings + the uid/gid the app runs as ─────
    #
    # SearXNG: upstream bind-mounts a template out of their git clone and runs a
    # migration script over it at boot. We have no clone and never an old
    # settings file to migrate, so the whole wrapper collapses into writing the
    # nine lines it would have produced. `formats: [html, json]` is the part
    # Odysseus actually needs — the JSON API is how the research feature reads
    # results.
    #
    # The secret_key signs SearXNG's own cookies and CSRF tokens. It cannot
    # live in the Nix store (world-readable), so it is generated once and kept
    # beside the config. That one file is the only state here Nix does not
    # author; if this ever needs to be reproducible across machines, it moves to
    # sops (Claude/secrets.md).
    #
    # PUID/PGID: the entrypoint drops to this uid/gid and chowns /app/data to
    # match. Read at runtime rather than hardcoded, because NixOS assigns the
    # uid and config.users.users.<n>.uid is null here.
      odysseus-init = {
      description = "Generate Odysseus runtime config (SearXNG settings, PUID/PGID)";
      before = [ (unitOf "odysseus") (unitOf "odysseus-searxng") ];
      wantedBy = [ (unitOf "odysseus") (unitOf "odysseus-searxng") ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "odysseus";
        RuntimeDirectoryPreserve = true;
      };
      path = with pkgs; [ openssl coreutils ];
      script = ''
        set -euo pipefail

        secret=${dataDir}/searxng/secret
        if [ ! -s "$secret" ]; then
          openssl rand -hex 32 > "$secret"
          chmod 600 "$secret"
        fi

        # Rewritten every boot — the content is Nix's, only the key persists.
        cat > ${dataDir}/searxng/settings.yml <<EOF
        use_default_settings: true

        server:
          secret_key: "$(cat "$secret")"

        search:
          formats:
            - html
            - json
        EOF
        chmod 644 ${dataDir}/searxng/settings.yml

        # --env-file for the app container.
        {
          echo "PUID=$(id -u ${activeUser})"
          echo "PGID=$(id -g ${activeUser})"
        } > /run/odysseus/ids.env
      '';
      };
    }

      # Every container unit waits on the network existing. Keyed off the
      # backend, so these follow if the host ever switches to podman.
      (lib.genAttrs (map unitName containerNames) (_: {
        after = [ "odysseus-network.service" ];
        requires = [ "odysseus-network.service" ];
      }))
    ];

    # ── The app ──────────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers.odysseus = {
      image = odysseusImage;
      networks = [ net ];
      dependsOn = [ "odysseus-chromadb" "odysseus-searxng" ];
      autoStart = true;
      # Never re-resolve the digest at start; it is immutable by definition.
      pull = "missing";

      ports = [ "127.0.0.1:${toString appPort}:7000" ];

      # ROCm wants exactly these two. See the header on why not all of /dev/dri.
      devices = [
        "/dev/kfd:/dev/kfd"
        "${renderNode}:${renderNode}"
      ];

      extraOptions = [
        # Both nodes are mode 0666 on this host, so these are belt-and-braces
        # rather than load-bearing — but the gids come from config, so they
        # stay correct if that ever tightens.
        "--group-add=${toString config.users.groups.video.gid}"
        "--group-add=${toString config.users.groups.render.gid}"
        # Lets the app reach services on the host — e.g. an Ollama on :11434,
        # if a second model path is ever wanted alongside Cookbook's.
        "--add-host=host.docker.internal:host-gateway"
      ];

      volumes = [
        "${dataDir}/data:/app/data:z"
        "${dataDir}/logs:/app/logs:z"
        "${dataDir}/data/ssh:/app/.ssh:z"
        "${dataDir}/data/huggingface:/app/.cache/huggingface:z"
        "${dataDir}/data/local:/app/.local:z"

        # The engine. /usr/local/bin is already on the image's PATH (it is
        # where its own python3.14 and uvicorn live), so dropping the binary
        # there needs no PATH override — and overriding PATH would risk
        # shadowing the pip-installed CLIs Cookbook puts in /app/.local/bin.
        "${llamaCpp}/bin/llama-server:/usr/local/bin/llama-server:ro"
        # llama-server resolves ~50 libraries (libggml-hip, libamdhip64,
        # hipblas, rocm-comgr …) by absolute /nix/store path, so the binary
        # alone is useless — the closure has to be visible. Read-only, and
        # the store holds only world-readable build artefacts; sops secrets
        # live in /run/secrets and are not exposed by this.
        "/nix/store:/nix/store:ro"
      ];

      environmentFiles = [ "/run/odysseus/ids.env" ];

      environment = {
        # Container-network names, not host ports — see `net` above.
        SEARXNG_INSTANCE = "http://odysseus-searxng:8080";
        CHROMADB_HOST = "odysseus-chromadb";
        CHROMADB_PORT = "8000";
        DATABASE_URL = "sqlite:///./data/app.db";

        # Auth stays on. Upstream's SECURITY note: keep AUTH_ENABLED=true on
        # any network-accessible deployment — and LOCALHOST_BYPASS would hand a
        # session to anything arriving from loopback, which on a desktop means
        # any local process, not just you.
        AUTH_ENABLED = "true";
        LOCALHOST_BYPASS = "false";

        # The app cannot see the host-side port map, so the origin it is
        # actually opened on has to be spelled out — both for CORS and for the
        # MCP OAuth callback.
        ALLOWED_ORIGINS = "http://localhost:${toString appPort},http://127.0.0.1:${toString appPort}";
        OAUTH_REDIRECT_BASE_URL = "http://localhost:${toString appPort}";

        # First-run admin password: left unset on purpose, so the app generates
        # one and prints it once. Read it with:
        #   journalctl -u ${unitOf "odysseus"} | grep -i password
        # Change it in the app afterwards; it lives in the SQLite DB from then
        # on, not here. (Pinning it would mean a secret in the Nix store.)
        ODYSSEUS_ADMIN_USER = activeUser;
      };
    };

    # ── Vector store ─────────────────────────────────────────────────────────
    # Without this the app falls back to an in-memory store and logs DEGRADED;
    # memory and document search would reset on every restart.
    virtualisation.oci-containers.containers.odysseus-chromadb = {
      image = chromaImage;
      networks = [ net ];
      autoStart = true;
      pull = "missing";
      # The image runs `chroma run /config.yaml`, whose persist_path is /data,
      # and declares no VOLUME — so anything written elsewhere dies with the
      # container. /chroma/chroma was the pre-1.0 location and catches nothing.
      volumes = [ "${dataDir}/chromadb:/data" ];
      environment.ANONYMIZED_TELEMETRY = "FALSE";
    };

    # ── Web search for the research feature ──────────────────────────────────
    virtualisation.oci-containers.containers.odysseus-searxng = {
      image = searxngImage;
      networks = [ net ];
      autoStart = true;
      pull = "missing";
      volumes = [ "${dataDir}/searxng:/etc/searxng" ];
      environment = {
        SEARXNG_BASE_URL = "http://odysseus-searxng:8080/";
      };
      extraOptions = [
        # Upstream's cap set: the image runs as a non-root user but its
        # entrypoint still needs to chown /etc/searxng on first boot and drop
        # privileges with su-exec. Without these it fails its healthcheck on
        # permission errors during setup.
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-add=DAC_OVERRIDE"
      ];
    };

    # ── Notifications ────────────────────────────────────────────────────────
    virtualisation.oci-containers.containers.odysseus-ntfy = {
      image = ntfyImage;
      networks = [ net ];
      autoStart = true;
      pull = "missing";
      cmd = [ "serve" ];
      ports = [ "127.0.0.1:${toString ntfyPort}:80" ];
      volumes = [ "${dataDir}/ntfy:/var/cache/ntfy" ];
      environment.NTFY_BASE_URL = "http://localhost:${toString ntfyPort}";
    };
  };
}
