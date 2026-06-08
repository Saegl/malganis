# Deploy malganis (Linode VPS)
deploy:
    # nixos-rebuild switch --target-host root@saegl.me --flake .#malganis
    nh os switch --hostname malganis --target-host root@saegl.me --elevation-strategy none .

# Run this if after update some systemd services cannot be restarted
deploy-boot:
    nixos-rebuild boot --target-host root@saegl.me --flake .#malganis

# Push machineplay backend secrets to the VPS and restart the backend.
# Reads secrets/backend.env (gitignored, KEY=VALUE per line) and the registry
# token-signing private key (secrets/registry-auth.key). The matching public
# cert is embedded in machineplay.nix (registryAuthCert).
push-secrets:
    ssh root@saegl.me 'mkdir -p /etc/machineplay && chmod 700 /etc/machineplay'
    scp secrets/backend.env root@saegl.me:/etc/machineplay/backend.env
    scp secrets/registry-auth.key root@saegl.me:/etc/machineplay/registry-auth.key
    scp secrets/registry-auth.crt root@saegl.me:/etc/machineplay/registry-auth.crt
    ssh root@saegl.me 'chmod 600 /etc/machineplay/backend.env /etc/machineplay/registry-auth.key && chmod 644 /etc/machineplay/registry-auth.crt && systemctl restart machineplay'

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
