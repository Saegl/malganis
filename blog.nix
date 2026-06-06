# All blog-related configuration: the FastAPI service, its nginx virtual host
# (with response caching) and the deploy script.
{pkgs, ...}: {
  ##############################################################################
  # SERVICES
  ##############################################################################

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

  ##############################################################################
  # NGINX VIRTUAL HOST (merged with services.nginx in configuration.nix)
  ##############################################################################

  # levels=1:2 - two-level directory hierarchy for cache files
  # keys_zone=blog:10m - 10MB shared memory zone for cache keys
  # max_size=100m - 100MB max disk usage for cached responses
  # inactive=60m - remove entries not accessed for 60 minutes
  services.nginx.appendHttpConfig = ''
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=blog:10m max_size=100m inactive=60m;
  '';

  services.nginx.virtualHosts."saegl.me" = {
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

  ##############################################################################
  # DEPLOY SCRIPT
  ##############################################################################

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "deploy-blog" ''
      set -e
      cd /root/blog
      ${git}/bin/git pull
      rm -rf /var/cache/nginx/*  # Invalidate nginx cache
      systemctl restart blog
      echo "Blog deployed successfully"
    '')
  ];
}
