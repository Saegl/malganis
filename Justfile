# Deploy malganis (Linode VPS)
deploy:
    # nixos-rebuild switch --target-host root@saegl.me --flake .#malganis
    nh os switch --hostname malganis --target-host root@saegl.me --elevation-strategy none .

# Run this if after update some systemd services cannot be restarted
deploy-boot:
    nixos-rebuild boot --target-host root@saegl.me --flake .#malganis

# Push every secret to the VPS. Run this BEFORE the first `just deploy` on a
# fresh machine: beszel-hub loads its SSH key as a systemd credential, which is
# mandatory, so the unit will not start until the key is in place.
push-secrets: push-machineplay-secrets push-beszel-secrets

# Push machineplay secrets to the VPS and restart the affected services.
# Reads (all gitignored):
#   secrets/backend.env        backend config, KEY=VALUE per line
#   secrets/runner.env         runner MP_TOKEN + RUNNER_ID (see machineplay.nix)
#   secrets/registry-auth.key  registry token-signing private key
# The matching public cert is embedded in machineplay.nix (registryAuthCert).
push-machineplay-secrets:
    ssh root@saegl.me 'mkdir -p /etc/machineplay && chmod 700 /etc/machineplay'
    scp secrets/backend.env root@saegl.me:/etc/machineplay/backend.env
    scp secrets/runner.env root@saegl.me:/etc/machineplay/runner.env
    scp secrets/registry-auth.key root@saegl.me:/etc/machineplay/registry-auth.key
    scp secrets/registry-auth.crt root@saegl.me:/etc/machineplay/registry-auth.crt
    ssh root@saegl.me 'chmod 600 /etc/machineplay/backend.env /etc/machineplay/runner.env /etc/machineplay/registry-auth.key && chmod 644 /etc/machineplay/registry-auth.crt && systemctl restart machineplay machineplay-runner'

# Push beszel secrets to the VPS and restart the hub.
# Reads (both gitignored):
#   secrets/beszel.env       USER_EMAIL + USER_PASSWORD, used once to create the
#                            admin account on the hub's very first boot
#   secrets/beszel-hub.key   the hub's SSH private key, seeded into its data dir
#                            so the identity survives a rebuild
# The matching public key is embedded in beszel.nix (hubPublicKey).
push-beszel-secrets:
    ssh root@saegl.me 'mkdir -p /etc/beszel && chmod 700 /etc/beszel'
    scp secrets/beszel.env root@saegl.me:/etc/beszel/hub.env
    scp secrets/beszel-hub.key root@saegl.me:/etc/beszel/hub.key
    # `|| true`: on a first-time deploy the unit does not exist yet, since the
    # secrets have to land before the nix config that consumes them.
    ssh root@saegl.me 'chmod 600 /etc/beszel/hub.env /etc/beszel/hub.key && (systemctl restart beszel-hub || true)'

# Connect with ssh
ssh:
    ssh root@saegl.me

# Clean old generations and garbage collect on VPS
clean:
    ssh root@saegl.me 'nix-collect-garbage -d'

# Show free space on VPS
space:
    ssh root@saegl.me 'df -h /'

# Update flake inputs
up:
    nix flake update --commit-lock-file --impure \
        --override-input nixpkgs github:NixOS/nixpkgs/$(curl -L https://channels.nixos.org/nixpkgs-unstable/git-revision)
