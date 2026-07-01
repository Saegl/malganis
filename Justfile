# Deploy malganis (Linode VPS)
deploy:
    # nixos-rebuild switch --target-host root@saegl.me --flake .#malganis
    nh os switch --hostname malganis --target-host root@saegl.me --elevation-strategy none .

# Run this if after update some systemd services cannot be restarted
deploy-boot:
    nixos-rebuild boot --target-host root@saegl.me --flake .#malganis

# Push machineplay secrets to the VPS and restart the affected services.
# Reads (all gitignored):
#   secrets/backend.env        backend config, KEY=VALUE per line
#   secrets/runner.env         runner MP_TOKEN + RUNNER_ID (see machineplay.nix)
#   secrets/registry-auth.key  registry token-signing private key
# The matching public cert is embedded in machineplay.nix (registryAuthCert).
push-secrets:
    ssh root@saegl.me 'mkdir -p /etc/machineplay && chmod 700 /etc/machineplay'
    scp secrets/backend.env root@saegl.me:/etc/machineplay/backend.env
    scp secrets/runner.env root@saegl.me:/etc/machineplay/runner.env
    scp secrets/registry-auth.key root@saegl.me:/etc/machineplay/registry-auth.key
    scp secrets/registry-auth.crt root@saegl.me:/etc/machineplay/registry-auth.crt
    ssh root@saegl.me 'chmod 600 /etc/machineplay/backend.env /etc/machineplay/runner.env /etc/machineplay/registry-auth.key && chmod 644 /etc/machineplay/registry-auth.crt && systemctl restart machineplay machineplay-runner'

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
