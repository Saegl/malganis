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

  services.nginx = {
    enable = true;
    virtualHosts."saegl.me" = {
      default = true;
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8000";
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
    (writeShellScriptBin "deploy-blog" ''
      set -e
      cd /root/blog
      ${git}/bin/git pull
      systemctl restart blog
      echo "Blog deployed successfully"
    '')
  ];

  system.stateVersion = "25.11";
}
