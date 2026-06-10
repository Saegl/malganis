# All machineplay-related configuration: backend + runner services, nginx
# virtual hosts, packages and the per-component deploy scripts.
#
# The three components now live in independent repos, each cloned at /root on
# the VPS and deployed individually from its own Justfile (`just deploy`):
#   /root/backend     <- github.com/MachinePlay/backend     (FastAPI app)
#   /root/frontend    <- github.com/MachinePlay/frontend    (Vite static site)
#   /root/machineplay <- github.com/MachinePlay/machineplay (CLI / runner)
#
# Backend environment variables (secrets) are NOT stored in the nix store.
# They live in /etc/machineplay/backend.env on the VPS and are pushed there
# out-of-band with `just push-secrets` (see ./secrets and the Justfile).
{pkgs, ...}: let
  # Public cert matching the registry-auth RSA private key that is pushed to
  # /etc/machineplay/registry-auth.key (see the Justfile `push-secrets` target).
  # The backend signs Docker registry tokens with the private key; the registry
  # validates them against this cert (its `auth.token.rootcertbundle`). It lives
  # in the nix store because the docker-registry user can't read the 0700
  # /etc/machineplay dir, and because flakes ignore untracked (gitignored)
  # files. Safe to commit — it is public. Regenerate both together when rotating:
  #   openssl req -newkey rsa:2048 -nodes -keyout registry-auth.key \
  #     -x509 -days 3650 -out registry-auth.crt -subj "/CN=machineplay-registry-auth"
  registryAuthCert = pkgs.writeText "registry-auth.crt" ''
    -----BEGIN CERTIFICATE-----
    MIIDKTCCAhGgAwIBAgIULwbgrKndXKBpSpQBEDKdMFzf70MwDQYJKoZIhvcNAQEL
    BQAwJDEiMCAGA1UEAwwZbWFjaGluZXBsYXktcmVnaXN0cnktYXV0aDAeFw0yNjA2
    MDgxODM5MzdaFw0zNjA2MDUxODM5MzdaMCQxIjAgBgNVBAMMGW1hY2hpbmVwbGF5
    LXJlZ2lzdHJ5LWF1dGgwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCk
    wjs/XRbhnYdxmZn662/vLLEfszRgqVyYrClbM+5H8tUiWgSMExZo/22lLO/8yFhK
    FVhN9Ll8/yLAK9oljUuPcFCxmbgb05SSeh9ZnvJ2NHV/BRlBNR6B8Gnv56pJmn7q
    DGgfH9uokGlv93c8ZA5lJvrYpdCgWEiRXUzkGsIPQzpUxVcKgkMNnEfS6fzfHOIN
    i8jdgrIXaZtZbU53RebIoybWMB7q3Ytaib0Aj7lT5vjbIN29868gUPcCM4JI30HW
    0fsYHiI4gu0E2jJyqA7GyH01CYa28iHYfCQGuSFsVo0bm9i6XDO47XNB2W6HF/xe
    Lt2qoMdkA/A/HKctfN99AgMBAAGjUzBRMB0GA1UdDgQWBBSIHlINeworG3A2ctV+
    kZZgwZ2VYzAfBgNVHSMEGDAWgBSIHlINeworG3A2ctV+kZZgwZ2VYzAPBgNVHRMB
    Af8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAeyA+GfC530kUQsvv+SuyBoF+a
    qTuxYY2Xxg6UZuvAELh4A1w4Vyg6jTbHZnrPvZUWLSi5+ronN4RJUIRI4CXY6zh8
    HnAyjNFFgtxYXjHE6EGOeM2R1IWUd7PQVH0mvxV4eV12knUlwW5k4sSpUcd/Zu3X
    ZtlBqPSurvO35KNjx6UKGBvTF9mviwYSAlvz3UpmmTgNQux3E/oSTqIavSHrwx5I
    N+MY8KxEczuktxJAmzI/DeryqccpWThwqiHRj1RaviGr4uZ1zssdySXE1lzOL8jJ
    yt0lF8u5CmD0ZKH5x8qrxx5oC9+M/kDqSoLwG8Bwl28mpG0TrzSo8J/m2Lnw
    -----END CERTIFICATE-----
  '';
in {
  ##############################################################################
  # SERVICES
  ##############################################################################

  # Docker registry engines are pushed to. It listens only on localhost; nginx
  # (registry.machineplay.org) terminates TLS in front of it. Pulls are public;
  # pushes require a token minted by the backend's /registry/token endpoint,
  # which the registry validates against registryAuthCert. The runner can pull
  # straight from 127.0.0.1:5000 (docker treats localhost as insecure-ok), so it
  # needs no credentials.
  services.dockerRegistry = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 5000;
    # Allow `DELETE`s so engine deletion can drop images later (M6 follow-up).
    enableDelete = true;
    extraConfig.auth.token = {
      realm = "https://api.machineplay.org/registry/token";
      service = "registry.machineplay.org";
      issuer = "machineplay-auth";
      rootcertbundle = "${registryAuthCert}";
    };
  };

  systemd.services.machineplay = {
    description = "Machineplay FastAPI app";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.stockfish];
    serviceConfig = {
      WorkingDirectory = "/root/backend";
      # Leading "-" makes the file optional: the service still starts before
      # any secrets have been pushed. Push them with `just push-secrets`.
      EnvironmentFile = "-/etc/machineplay/backend.env";
      ExecStart = "${pkgs.uv}/bin/uv run uvicorn app.main:app --port 8888 --timeout-graceful-shutdown 0";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.machineplay-runner = {
    description = "Machineplay runner (plays games via WS to local backend)";
    after = ["network.target" "machineplay.service"];
    wants = ["machineplay.service"];
    wantedBy = ["multi-user.target"];
    # docker: the runner pulls engine images and plays them via `docker run`.
    path = [pkgs.fastchess pkgs.stockfish pkgs.docker];
    environment = {
      BACKEND_URL = "ws://127.0.0.1:8888/ws";
      # Co-located with the registry: pull straight from it, skipping nginx/TLS.
      MACHINEPLAY_REGISTRY = "127.0.0.1:5000";
      # The runner logs via print(); without this, stdout is block-buffered
      # under systemd and nothing reaches the journal.
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      WorkingDirectory = "/root/machineplay";
      ExecStart = "${pkgs.uv}/bin/uv run machineplay";
      Restart = "always";
      RestartSec = 5;
    };
  };

  ##############################################################################
  # NGINX VIRTUAL HOSTS (merged with services.nginx in configuration.nix)
  ##############################################################################

  services.nginx.virtualHosts."api.machineplay.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
    };
  };

  # Public TLS front for the docker registry. Image blobs are large and
  # streamed, so disable the body-size cap and request buffering. The registry
  # builds blob-upload Location URLs from the forwarded Host/proto, so pass them
  # through. DNS: add an A/AAAA record for registry.machineplay.org → this VPS.
  services.nginx.virtualHosts."registry.machineplay.org" = {
    enableACME = true;
    forceSSL = true;
    extraConfig = ''
      client_max_body_size 0;
      chunked_transfer_encoding on;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:5000";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_request_buffering off;
        proxy_read_timeout 900s;
      '';
    };
  };

  services.nginx.virtualHosts."machineplay.org" = {
    enableACME = true;
    forceSSL = true;
    root = "/var/www/machineplay/dist"; # see permissions note below
    locations."/" = {
      tryFiles = "$uri /index.html";
    };
    # Vite hashes filenames (index-Drtt7cGr.js), so assets/ can cache forever
    locations."/assets/" = {
      extraConfig = ''
        expires 1y;
        add_header Cache-Control "public, immutable";
      '';
    };
    # index.html must NOT be cached, otherwise users get stale shells after deploys
    locations."= /index.html" = {
      extraConfig = ''
        add_header Cache-Control "no-cache";
      '';
    };
  };

  ##############################################################################
  # PACKAGES & DEPLOY SCRIPTS
  ##############################################################################

  # One script per component. Each repo's Justfile sshes in and runs the
  # matching one (`just deploy`); it git-pulls the already-cloned repo and
  # rebuilds/restarts only that component. `deploy-machineplay` does all three.
  environment.systemPackages = with pkgs; [
    fastchess
    stockfish

    (writeShellScriptBin "deploy-machineplay-backend" ''
      set -e
      # The backend editable-installs ../machineplay (shared schemas), so the
      # two checkouts must move together — a stale sibling breaks /game.
      cd /root/machineplay
      git pull
      cd /root/backend
      git pull
      # `uv run` (the service's ExecStart) syncs deps from the lockfile on start.
      systemctl restart machineplay
      echo "Backend deployed successfully"
    '')

    (writeShellScriptBin "deploy-machineplay-frontend" ''
      set -e
      cd /root/frontend
      git pull
      pnpm install --frozen-lockfile
      pnpm build
      mkdir -p /var/www/machineplay
      rsync -a --delete dist/ /var/www/machineplay/dist/
      echo "Frontend deployed successfully"
    '')

    (writeShellScriptBin "deploy-machineplay-cli" ''
      set -e
      cd /root/machineplay
      git pull
      # The runner auto-reconnects, so it's safe to restart independently.
      systemctl restart machineplay-runner
      # The backend imports machineplay.schemas (editable install), so it must
      # reload too or the two sides disagree on the wire schema.
      systemctl restart machineplay
      echo "Runner (cli) deployed successfully"
    '')
  ];
}
