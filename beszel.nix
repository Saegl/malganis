# All beszel-related configuration: the monitoring hub, the agent that reports
# this machine's metrics to it, and the hub's nginx virtual host.
#
# Topology — both halves run on this box, so nothing is exposed but the UI:
#
#   internet ──HTTPS──> nginx (status.saegl.me) ──> 127.0.0.1:8090  hub
#                                                          │
#                                                   SSH over loopback
#                                                          ▼
#                                                   127.0.0.1:45876 agent
#
# The agent listens on loopback only (no firewall port). The hub authenticates
# to it with an SSH key, exactly as it would to an agent on a remote host.
#
# Secrets are NOT in the nix store. They live under /etc/beszel on the VPS and
# are pushed out-of-band with `just push-secrets` (see ./secrets and the
# Justfile):
#   /etc/beszel/hub.env   USER_EMAIL + USER_PASSWORD (bootstraps the admin)
#   /etc/beszel/hub.key   the hub's SSH private key (see below)
{
  pkgs,
  lib,
  ...
}: let
  domain = "status.saegl.me";
  hubPort = 8090;
  agentPort = 45876;
  dataDir = "/var/lib/beszel-hub";
  agentDataDir = "/var/lib/beszel-agent";

  # Public half of the hub's SSH identity, whose private half is pushed to
  # /etc/beszel/hub.key and seeded into the hub's data dir (see below). The hub
  # connects to agents with the private key; each agent trusts this public one.
  #
  # Left in the nix store / committed on purpose — it is public, and the flake
  # cannot read ./secrets anyway (gitignored files don't enter the flake's
  # source tree). Same arrangement as machineplay.nix's registryAuthCert.
  # Regenerate both halves together when rotating:
  #   ssh-keygen -t ed25519 -N "" -C beszel-hub -f secrets/beszel-hub.key
  hubPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOIx/zRsG90W61K8Su8NwUHKnEY8SS/+PwzjMu0ieS/U beszel-hub";
in {
  ##############################################################################
  # SERVICES
  ##############################################################################

  services.beszel.hub = {
    enable = true;
    host = "127.0.0.1"; # nginx terminates TLS in front of it
    port = hubPort;
    inherit dataDir;

    environment = {
      # Used for links in alert emails/notifications, which otherwise point at
      # the loopback address the hub actually binds.
      APP_URL = "https://${domain}";
    };
    # environmentFile is deliberately left unset — see EnvironmentFile below.
    # The option demands an absolute path, which rules out systemd's "-" prefix.
  };

  # The hub generates an SSH keypair in its data dir on first run. Left to
  # itself that identity is unreproducible mutable state: wipe the data dir (or
  # rebuild the VPS) and every agent's pinned key stops matching. So we install
  # our own private key over it instead, which is what makes hubPublicKey above
  # a stable, committable constant.
  #
  # LoadCredential hands the 0600 root-owned file to the service's DynamicUser
  # without widening its permissions; the copy lands in the data dir owned by
  # that user because the ExecStartPre runs as it. mkBefore puts this ahead of
  # the module's own `migrate up` / `history-sync` steps.
  #
  # Note the "beszel_data" component: the hub takes its data directory from
  # --dir, whose default is the *relative* path "beszel_data", resolved against
  # the unit's WorkingDirectory. So the database and key really live one level
  # below dataDir, and a key written to dataDir itself is silently ignored.
  # -D creates the directory when the hub has not run yet.
  systemd.services.beszel-hub.serviceConfig = {
    LoadCredential = "hub.key:/etc/beszel/hub.key";
    ExecStartPre = lib.mkBefore [
      "${pkgs.coreutils}/bin/install -D -m600 %d/hub.key ${dataDir}/beszel_data/id_ed25519"
    ];

    # USER_EMAIL + USER_PASSWORD, which bootstrap the admin account. Read on the
    # hub's first boot only: they create a `users` record plus the matching
    # superuser while the database is empty, and are ignored once it exists — so
    # a password changed later in the UI is not clobbered by a restart. Keeping
    # them here means a rebuild from bare metal re-creates the account rather
    # than leaving the hub sitting unclaimed on a public URL.
    #
    # Note this must apply to the whole unit, not just `serve`: the account is
    # created by the `migrate up` ExecStartPre that initialises the database,
    # and the variables have no effect if they are only visible to `serve`.
    #
    # Leading "-" makes the file optional — once the account exists the hub no
    # longer needs it. (The hub.key credential above is mandatory by contrast:
    # without it the hub would silently mint a new identity and every agent's
    # pinned KEY would stop matching, which is worse than failing loudly.)
    EnvironmentFile = "-/etc/beszel/hub.env";
  };

  # Reports this machine's metrics. It also picks up docker containers (the
  # module puts it in the docker group) and systemd units, so the machineplay,
  # runner, blog and mongodb services show up in the dashboard for free.
  #
  # It logs one WARN on startup — "Error creating WebSocket client: HUB_URL
  # environment variable not set" — which is expected and harmless: that is the
  # agent's other, outbound connection mode, and we deliberately use the SSH one
  # below instead. Nothing to chase.
  services.beszel.agent = {
    enable = true;
    environment = {
      # Loopback only: the hub is on this same machine, so the agent needs no
      # public port and openFirewall stays off.
      LISTEN = "127.0.0.1:${toString agentPort}";
      KEY = hubPublicKey;
      # Where the agent persists its fingerprint. Without it the agent warns
      # "Data directory not found" on every start.
      DATA_DIR = agentDataDir;
    };
  };

  # The agent module sets ProtectSystem=strict but no StateDirectory, so DATA_DIR
  # above would be unwritable without this.
  systemd.services.beszel-agent.serviceConfig.StateDirectory = baseNameOf agentDataDir;

  ##############################################################################
  # NGINX VIRTUAL HOST (merged with services.nginx in configuration.nix)
  ##############################################################################

  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString hubPort}";
      # The dashboard streams live metrics over a websocket; without this the
      # charts only update on a manual reload.
      proxyWebsockets = true;
    };
  };
}
