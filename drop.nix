# All drop-related configuration: the FastAPI service, its nginx virtual host
# and the deploy script.
#
# Unlike blog/machineplay this one runs as saegl out of a clone in their home,
# not as root out of /root:
#   /home/saegl/projects/python/drop   <- github.com/Saegl/drop
# Uploads go to DROP_DIR (/home/saegl/trash), NOT into the repo, so a `git pull`
# or a rebuild never touches them. The app creates that directory on first use.
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
      # nginx fronts this under a name the app cannot see for itself; without
      # it the help text advertises http://127.0.0.1:8006.
      DROP_PUBLIC_URL = "https://drop.saegl.me";
      DROP_DIR = "/home/saegl/trash";
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
      Restart = "always";
      RestartSec = 5;
    };
  };

  ##############################################################################
  # NGINX VIRTUAL HOST (merged with services.nginx in configuration.nix)
  ##############################################################################

  # `curl drop.saegl.me` has no scheme, so curl tries http. Under forceSSL that
  # is a 301, which curl does not follow unless asked, so the help text never
  # arrived. addSSL serves both instead; the map below still keeps every actual
  # upload on TLS.
  services.nginx.appendHttpConfig = ''
    map $scheme:$request_method $drop_body_over_http {
      default      0;
      ~^http:POST$ 1;
      ~^http:PUT$  1;
    }
  '';

  services.nginx.virtualHosts."drop.saegl.me" = {
    enableACME = true;
    addSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        # services.nginx.recommendedProxySettings is off host-wide, so these go
        # by hand. Without them the app is handed Host: 127.0.0.1:${toString port}
        # with no scheme, and quotes that back as the URL to curl.
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # Reading the help over plain http is harmless; shipping a file over it
        # is not, so anything carrying a body gets bounced to TLS.
        if ($drop_body_over_http) {
          return 301 https://$host$request_uri;
        }

        # client_max_body_size - nginx's default is 1m, which would 413 every
        #   real upload before it ever reached the app. Kept in step with
        #   DROP_MAX_MB so the app is the one that decides what is too big.
        # proxy_request_buffering off - stream the body straight through instead
        #   of spooling the whole file to nginx's disk first.
        # proxy_read_timeout - a slow phone on a big file needs longer than 60s.
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
