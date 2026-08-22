# All t3-related configuration: the T3 Code server, its nginx virtual host and
# the `t3` CLI on PATH.
{
  pkgs,
  lib,
  ...
}: let
  # The account the t3 agent runs as, and whose ~/.t3 holds its runtime state.
  # `t3 pair` reads that same directory, so it must be run as this user.
  t3User = "saegl";
  t3Home = "/home/${t3User}";
  t3Port = 3773;

  # Agent backends are left to PATH rather than pulled in here: claude-code is
  # installed out-of-band into ~/.local/bin, which t3Path below exposes.
  t3code = pkgs.t3code.override {
    enableCodex = false;
    enableClaude = false;
  };

  # systemd gives services a bare PATH, so claude would be invisible to the
  # agent without ~/.local/bin. Order mirrors this user's login shell, with
  # /run/wrappers needed for setuid programs like sudo.
  t3Path = lib.makeBinPath [
    "${t3Home}/.local"
    "/run/wrappers"
    "/run/current-system/sw"
  ];
in {
  ##############################################################################
  # SERVICE
  ##############################################################################

  # T3 Code server behind the code.saegl.me vhost below. `serve` is the headless
  # entry point: no browser launch, and it logs pairing details on startup.
  #
  # Deliberately unhardened: the whole point is to run a coding agent that edits
  # files and spawns processes, so ProtectSystem/NoNewPrivileges would only get
  # in its way. It is confined by being ${t3User} rather than root.
  systemd.services.t3 = {
    description = "T3 Code server";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    # HOME is what t3 derives its ~/.t3 data directory from; keep it in sync
    # with the `t3 pair` invocation, which must resolve to the same directory.
    #
    # mkForce because the systemd module sets a default PATH of coreutils,
    # findutils, gnugrep, gnused and systemd. Dropping it costs nothing here:
    # /run/current-system/sw/bin carries all of those and more.
    environment = {
      HOME = t3Home;
      PATH = lib.mkForce t3Path;
    };

    serviceConfig = {
      ExecStart = "${t3code}/bin/t3 serve --host 127.0.0.1 --port ${toString t3Port}";
      User = t3User;
      Group = "users";
      # Doubles as the default cwd for provider sessions.
      WorkingDirectory = t3Home;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  ##############################################################################
  # NGINX VIRTUAL HOST (merged with services.nginx in configuration.nix)
  ##############################################################################

  # Public front for the `t3` server (systemd unit above).
  #
  # NOTE: t3 drives a coding agent with shell access to this host as ${t3User},
  # who has passwordless sudo, and its only auth is a short-lived pairing
  # token. To gate it behind a password, add
  # `basicAuthFile = "/etc/nginx/code-htpasswd";` below and push that file the
  # way `just push-secrets` handles the others.
  services.nginx.virtualHosts."code.saegl.me" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString t3Port}";
      # Agent output and terminal I/O stream over websockets.
      proxyWebsockets = true;
    };
  };

  ##############################################################################
  # PACKAGES
  ##############################################################################

  # `t3` CLI; npx can't build its node-pty dep here (no python3/gcc on the
  # host, and upstream ships prebuilds for darwin/win32 only). Same derivation
  # the service above runs.
  environment.systemPackages = [t3code];
}
