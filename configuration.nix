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
  imports = [
    ./hardware-configuration.nix
    ./blog.nix
    ./machineplay.nix
    ./beszel.nix
    ./drop.nix
  ];

  ##############################################################################
  # BOOT
  ##############################################################################

  boot.loader.grub.enable = true;
  boot.loader.grub.forceInstall = true;
  boot.loader.grub.device = "nodev";
  boot.loader.timeout = 10;

  ##############################################################################
  # NETWORKING
  ##############################################################################

  networking.hostName = "malganis";
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;
  networking.firewall.allowedTCPPorts = [22 80 443];

  ##############################################################################
  # LOCALE & TIME
  ##############################################################################

  time.timeZone = "Asia/Almaty";
  i18n.defaultLocale = "en_US.UTF-8";

  ##############################################################################
  # NIX
  ##############################################################################

  nix.settings.experimental-features = ["nix-command" "flakes"];

  ##############################################################################
  # USERS
  ##############################################################################

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3mq6jo73DWU/soz5MM4hSh0q61HiDxBk2apfMDNsWV saegl@protonmail.com"
  ];

  users.users.saegl = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3mq6jo73DWU/soz5MM4hSh0q61HiDxBk2apfMDNsWV saegl@protonmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  ##############################################################################
  # SERVICES
  ##############################################################################

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "saegl@protonmail.com";

  services.nginx = {
    enable = true;
    virtualHosts."frostmourne.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8005";
    };
    virtualHosts."preview.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:7777";
    };
    virtualHosts."dev.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/".return = ''200 "dev.saegl.me is alive\n"'';
      extraConfig = ''default_type text/plain;'';
    };
    # Public front for the `t3` server (systemd unit below).
    #
    # NOTE: t3 drives a coding agent with shell access to this host as ${t3User},
    # who has passwordless sudo, and its only auth is a short-lived pairing
    # token. To gate it behind a password, add
    # `basicAuthFile = "/etc/nginx/code-htpasswd";` below and push that file the
    # way `just push-secrets` handles the others.
    virtualHosts."code.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString t3Port}";
        # Agent output and terminal I/O stream over websockets.
        proxyWebsockets = true;
      };
    };
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  # T3 Code server behind the code.saegl.me vhost above. `serve` is the headless
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

  virtualisation.docker.enable = true;
  services.mongodb = {
    enable = true;
    package = pkgs.mongodb-ce;
    bind_ip = "127.0.0.1";
  };

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["mongodb-ce"];

  ##############################################################################
  # NIX-LD (for dynamically linked binaries like uv's Python)
  ##############################################################################

  programs.nix-ld.enable = true;

  ##############################################################################
  # SHELL
  ##############################################################################

  environment.localBinInPath = true;
  environment.shellAliases = {
    q = "exit";
  };

  ##############################################################################
  # PACKAGES
  ##############################################################################

  environment.systemPackages = with pkgs; [
    neovim
    wget
    htop
    git
    inetutils
    uv
    nodejs_24
    pnpm_10
    # `t3` CLI; npx can't build its node-pty dep here (no python3/gcc on the
    # host, and upstream ships prebuilds for darwin/win32 only). Defined in the
    # `let` block above, which the t3 service reuses.
    t3code
    rsync
    mongodb-tools # mongodump/mongorestore for `just backup` (server pkg omits them)
  ];

  system.stateVersion = "25.11";
}
