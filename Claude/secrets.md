# Secrets Management — sops-nix

**Module:** `Modules/sops.nix`
**Flake input:** `sops-nix`

Uses **sops-nix** with age keys. Secrets decrypted at system activation, available at `/run/secrets/`.

## Files

- `Secrets/.sops.yaml` — lists age public keys and path rules
- `Secrets/secrets.yaml` — encrypted secrets (safe to commit)
- `Modules/sops.nix` — sops-nix module config

## Key Locations

- PC key: `~/.config/sops/age/keys.txt`
- Apollo USB backup: `/run/media/rock/Apollo/keys/age-keys.txt`

## Adding a Secret

1. Edit encrypted file: `sops Secrets/secrets.yaml`
2. Add: `my-api-key: "the-actual-key"`
3. Save and exit (auto re-encrypts)
4. Reference in `sops.nix`:
   ```nix
   sops.secrets.my-api-key = { };
   ```
5. Available at `/run/secrets/my-api-key` after rebuild

**Editor:** `EDITOR` is set to `codium --wait` in `zsh.nix`, so sops opens VSCodium.

## Useful Commands

```bash
sops Secrets/secrets.yaml             # Edit (decrypts in editor, re-encrypts on save)
sops updatekeys secrets/secrets.yaml  # Rotate keys (after adding new key to .sops.yaml)
sops -d secrets/secrets.yaml          # View decrypted (read-only)
```

## Path Fix

`defaultSopsFile` must use `../Secrets/secrets.yaml` (one level up from `Modules/`), NOT `../../` which resolves to `/nix/store/Secrets` and breaks pure evaluation.
