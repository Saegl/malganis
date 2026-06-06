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
{pkgs, ...}: {
  ##############################################################################
  # SERVICES
  ##############################################################################

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
    path = [pkgs.fastchess pkgs.stockfish];
    environment.BACKEND_URL = "ws://127.0.0.1:8888/ws";
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
    # Engine uploads are `docker save` tarballs (~hundreds of MB). nginx's
    # default client_max_body_size is 1M, which 413s them before they reach the
    # backend. Set generous headroom; the backend's MAX_UPLOAD_BYTES (200M
    # default) is the effective cap and returns a clean JSON error.
    extraConfig = ''
      client_max_body_size 512m;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
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
      echo "Runner (cli) deployed successfully"
    '')
  ];
}
