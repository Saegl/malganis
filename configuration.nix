{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./blog.nix
    ./machineplay.nix
    ./beszel.nix
    ./drop.nix
    ./t3.nix
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
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
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
    rsync
    mongodb-tools # mongodump/mongorestore for `just backup` (server pkg omits them)
  ];

  system.stateVersion = "25.11";
}
