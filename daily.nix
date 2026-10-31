# All daily-related configuration: the study site's web service and its two
# nginx virtual hosts.
#
# Like drop it runs as saegl out of their home, but not from a git clone: the
# daily repo's `just deploy` copies HEAD and a locally built dist/ to
#   /home/saegl/projects/daily
# and `just push` / `just pull` move its data/ to and from the laptop. That
# path matches the laptop's on purpose: chat sessions live in ~/.claude under
# a name taken from it, so they move with the data.
#
# Only the web server runs here. Lesson jobs are too heavy for this box, so
# there is no worker: jobs queued from the phone wait in the database until
# `just pull` brings them to the laptop.
#
# /etc/daily/env (not in this repo) holds SECRET, and CLAUDE_CODE_OAUTH_TOKEN
# for chat unless saegl's own `claude` login is used.
{pkgs, ...}: let
  user = "saegl";
  home = "/home/${user}";
  app = "${home}/projects/daily";
  appPort = 8009;
  lessonPort = 8010;
  # Kept in step with the app's own source-upload cap.
  maxMB = 300;
in {
  ##############################################################################
  # SERVICE
  ##############################################################################

  systemd.services.daily = {
    description = "daily study site";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    environment = {
      HOME = home;
      NODE_ENV = "production";
      DATA_DIR = "${app}/data";
      APP_ORIGIN = "https://daily.saegl.me";
      LESSON_ORIGIN = "https://lessons.saegl.me";
      APP_PORT = toString appPort;
      LESSON_PORT = toString lessonPort;
    };
    serviceConfig = {
      User = user;
      Group = "users";
      WorkingDirectory = app;
      EnvironmentFile = "/etc/daily/env";
      ExecStart = "${pkgs.nodejs_24}/bin/node ${app}/node_modules/tsx/dist/cli.mjs src/server/main.ts";
      Restart = "always";
      RestartSec = 5;
    };
  };

  ##############################################################################
  # NGINX VIRTUAL HOSTS (merged with services.nginx in configuration.nix)
  ##############################################################################

  services.nginx.virtualHosts."daily.saegl.me" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString appPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size ${toString maxMB}m;
        proxy_request_buffering off;
        # Chat answers stream over SSE.
        proxy_buffering off;
        proxy_read_timeout 1h;
      '';
    };
  };

  services.nginx.virtualHosts."lessons.saegl.me" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString lessonPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };

  ##############################################################################
  # PACKAGES
  ##############################################################################

  # sqlite3 takes consistent snapshots for `just push` / `just pull`.
  environment.systemPackages = [pkgs.sqlite];
}
