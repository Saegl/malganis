# All drop-related configuration: the FastAPI service, its nginx virtual host
# and the deploy script.
#
# Unlike blog/machineplay this one runs as saegl out of a clone in their home,
# not as root out of /root:
#   /home/saegl/projects/python/drop   <- github.com/Saegl/drop
# Uploads go to /var/lib/drop, NOT into the repo, so a `git pull` or a rebuild
# never touches them. StateDirectory creates it owned by saegl.
{pkgs, ...}: let
  user = "saegl";
  home = "/home/${user}";
  repo = "${home}/projects/python/drop";
  port = 8006;
  maxMB = 100;
in {
  ##############################################################################
  # SERVICE
  ##############################################################################

  systemd.services.drop = {
    description = "drop file inbox";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    environment = {
      # uv resolves its cache and toolchains out of HOME; systemd would
      # otherwise hand the unit a bare environment.
      HOME = home;
      DROP_DIR = "/var/lib/drop";
      DROP_MAX_MB = toString maxMB;
      # nginx is the only thing that should reach it; it terminates TLS.
      DROP_HOST = "127.0.0.1";
      DROP_PORT = toString port;
    };
    serviceConfig = {
      User = user;
      Group = "users";
      WorkingDirectory = repo;
      ExecStart = "${pkgs.uv}/bin/uv run python -m drop";
      # Creates /var/lib/drop owned by ${user} on first start, then leaves it be.
      StateDirectory = "drop";
      StateDirectoryMode = "0750";
      Restart = "always";
      RestartSec = 5;
    };
  };

  ##############################################################################
  # NGINX VIRTUAL HOST (merged with services.nginx in configuration.nix)
  ##############################################################################

  services.nginx.virtualHosts."drop.saegl.me" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      # client_max_body_size - nginx's default is 1m, which would 413 every
      #   real upload before it ever reached the app. Kept in step with
      #   DROP_MAX_MB so the app is the one that decides what is too big.
      # proxy_request_buffering off - stream the body straight through instead
      #   of spooling the whole file to nginx's disk first.
      # proxy_read_timeout - a slow phone on a big file needs longer than 60s.
      extraConfig = ''
        client_max_body_size ${toString maxMB}m;
        proxy_request_buffering off;
        proxy_read_timeout 600s;
      '';
    };
  };

  ##############################################################################
  # DEPLOY SCRIPT
  ##############################################################################

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "deploy-drop" ''
      set -e
      # Works either way round: `ssh saegl@saegl.me deploy-drop` pulls directly
      # and sudos the restart, `ssh root@saegl.me deploy-drop` drops to saegl
      # for the pull so git never sees a repo owned by someone else.
      if [ "$(id -un)" = "${user}" ]; then
        ${git}/bin/git -C ${repo} pull
        sudo systemctl restart drop
      else
        ${util-linux}/bin/runuser -u ${user} -- ${git}/bin/git -C ${repo} pull
        systemctl restart drop
      fi
      echo "drop deployed successfully"
    '')
  ];
}
