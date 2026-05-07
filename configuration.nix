{
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware-configuration.nix];

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

  ##############################################################################
  # SERVICES
  ##############################################################################

  security.acme.acceptTerms = true;
  security.acme.defaults.email = "saegl@protonmail.com";

  systemd.services.blog = {
    description = "Blog FastAPI app";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      WorkingDirectory = "/root/blog";
      ExecStart = "${pkgs.uv}/bin/uv run fastapi run --port 8000";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.machineplay = {
    description = "Machineplay FastAPI app";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.cutechess pkgs.stockfish];
    serviceConfig = {
      WorkingDirectory = "/root/machineplay";
      ExecStart = "${pkgs.uv}/bin/uv run fastapi run --port 8888";
      Restart = "always";
      RestartSec = 5;
    };
  };

  services.nginx = {
    enable = true;
    # levels=1:2 - two-level directory hierarchy for cache files
    # keys_zone=blog:10m - 10MB shared memory zone for cache keys
    # max_size=100m - 100MB max disk usage for cached responses
    # inactive=60m - remove entries not accessed for 60 minutes
    appendHttpConfig = ''
      proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=blog:10m max_size=100m inactive=60m;
    '';
    virtualHosts."saegl.me" = {
      default = true;
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
        # proxy_cache blog - use the "blog" cache zone
        # proxy_cache_valid 200 10m - cache 200 responses for 10 minutes
        # proxy_cache_use_stale - serve stale cache on error, timeout, or while updating
        # X-Cache-Status - header to check HIT/MISS/STALE etc.
        extraConfig = ''
          proxy_cache blog;
          proxy_cache_valid 200 10m;
          proxy_cache_use_stale error timeout updating;
          add_header X-Cache-Status $upstream_cache_status;
        '';
      };
    };
    virtualHosts."api.machineplay.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8888";
        proxyWebsockets = true;
      };
    };
    virtualHosts."machineplay.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      root = "/var/www/machineplay/dist";  # see permissions note below
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
    virtualHosts."frostmourne.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8005";
    };
    virtualHosts."dev.saegl.me" = {
      enableACME = true;
      forceSSL = true;
      locations."/".return = ''200 "dev.saegl.me is alive\n"'';
      extraConfig = ''default_type text/plain;'';
    };
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  ##############################################################################
  # NIX-LD (for dynamically linked binaries like uv's Python)
  ##############################################################################

  programs.nix-ld.enable = true;

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
    pnpm_9
    rsync
    cutechess
    stockfish
    (writeShellScriptBin "deploy-blog" ''
      set -e
      cd /root/blog
      ${git}/bin/git pull
      rm -rf /var/cache/nginx/*  # Invalidate nginx cache
      systemctl restart blog
      echo "Blog deployed successfully"
    '')
    (writeShellScriptBin "deploy-machineplay" ''
      set -e
      cd /root/machineplay
      git pull
      cd frontend
      pnpm install --frozen-lockfile
      pnpm build
      mkdir -p /var/www/machineplay
      rsync -a --delete dist/ /var/www/machineplay/dist/
      cd ..
      systemctl restart machineplay
      echo "Machineplay deployed successfully"
    '')
  ];

  system.stateVersion = "25.11";
}
