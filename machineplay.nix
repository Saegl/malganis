# MachinePlay: registry, backend and runner services, nginx vhosts and deploy
# scripts. The repos are cloned at /root/{backend,frontend,machineplay}; secrets
# live in /etc/machineplay, pushed by `just push-secrets`.
{pkgs, ...}: let
  # Public half of /etc/machineplay/registry-auth.key, which signs registry
  # tokens. In the store because the registry user can't read /etc/machineplay.
  # Rotate both together:
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
  # Pulls are public; pushes need a token from the backend's /registry/token.
  # The local runner pulls from 127.0.0.1:5000, which docker allows over HTTP.
  services.dockerRegistry = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 5000;
    # The backend deletes the manifests of deleted engines.
    enableDelete = true;
    # Reclaims unlinked blobs. A push racing it could lose a blob; re-push.
    enableGarbageCollect = true;
    garbageCollectDates = "weekly";
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
    environment = {
      REGISTRY_API_URL = "http://127.0.0.1:5000";
    };
    serviceConfig = {
      WorkingDirectory = "/root/backend";
      # "-": starts before the secrets are pushed.
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
    path = [pkgs.fastchess pkgs.docker];
    environment = {
      BACKEND_URL = "ws://127.0.0.1:8888/ws";
      MACHINEPLAY_REGISTRY = "127.0.0.1:5000";
      # The runner logs via print(), block-buffered under systemd otherwise.
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      WorkingDirectory = "/root/machineplay";
      # MP_TOKEN (the owner's token) and RUNNER_ID. Until it is pushed the
      # runner exits and systemd retries.
      EnvironmentFile = "-/etc/machineplay/runner.env";
      ExecStart = "${pkgs.uv}/bin/uv run machineplay runner";
      Restart = "always";
      RestartSec = 5;
    };
  };

  services.nginx.virtualHosts."api.machineplay.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
    };
  };

  # Blobs are large and streamed: no body cap or buffering. The registry builds
  # upload URLs from the forwarded Host/proto.
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
    root = "/var/www/machineplay/dist";
    locations."/" = {
      tryFiles = "$uri /index.html";
    };
    # Vite hashes asset filenames.
    locations."/assets/" = {
      extraConfig = ''
        expires 1y;
        add_header Cache-Control "public, immutable";
      '';
    };
    # Otherwise users get a stale shell after a deploy.
    locations."= /index.html" = {
      extraConfig = ''
        add_header Cache-Control "no-cache";
      '';
    };
  };

  # Each repo's `just deploy` runs its script here.
  environment.systemPackages = with pkgs; [
    fastchess

    (writeShellScriptBin "deploy-machineplay-backend" ''
      set -e
      # The backend editable-installs ../machineplay; they move together.
      cd /root/machineplay
      git pull
      cd /root/backend
      git pull
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
      systemctl restart machineplay-runner
      # The backend imports machineplay.schemas, so it reloads too.
      systemctl restart machineplay
      echo "Runner (cli) deployed successfully"
    '')
  ];
}
