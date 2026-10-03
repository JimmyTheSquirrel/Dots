# Secrets Management — sops-nix

**Module:** `Modules/Core/sops.nix`
**Flake input:** `sops-nix`

Uses **sops-nix** with age keys. Secrets decrypted at system activation, available at `/run/secrets/`.

## Files

- `.sops.yaml` — **at the repo ROOT** (not in `Secrets/`) — age public keys and path rules
- `Secrets/secrets.yaml` — encrypted secrets, rock's machines (safe to commit)
- `Secrets/kit-kat.yaml` — Kit-Kat's machine only, its own recipients (see below)
- `Modules/Core/sops.nix` — sops-nix module config

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
sops updatekeys Secrets/secrets.yaml  # Rotate keys (after adding new key to .sops.yaml)
sops -d Secrets/secrets.yaml          # View decrypted (read-only)
sops set Secrets/secrets.yaml '["my-key"]' '"value"'   # Replace one value, no editor
```

⚠️ Use `sops set`, **not** `sops --set` — the flag form mangles `$`.

⚠️ **`.sops.yaml` must live at the repo root.** sops resolves `path_regex` relative to the
directory holding `.sops.yaml`, so while it sat at `Secrets/.sops.yaml` the path it tested was
just `secrets.yaml` — and a rule mentioning `Secrets/` could never match. That, not letter case,
is why creating a new encrypted file always failed with "no matching creation rules".
Moved to the root 2026-10-02 and both rules verified working.

Two earlier attempts at this that did NOT fix it, for the record:
- `secrets/` -> `[Ss]ecrets/` (2026-09-19) — right instinct, wrong cause; the prefix was being
  stripped entirely, so neither spelling could match.
- leaving the bracket unquoted — `path_regex: [Ss]ecrets/...` is a YAML **flow sequence**, so the
  config failed to load outright (`did not find expected key`), which is strictly worse than the
  bug it was meant to fix. Both regexes are now single-quoted.

Editing an existing file always worked regardless, because sops reads recipients from that
file's own metadata and never consults `.sops.yaml` — which is why this hid for so long.

Also: never `git diff` a sops file — the output is noise.

## Path Fix

`defaultSopsFile` must use `../Secrets/secrets.yaml` (one level up from `Modules/`), NOT `../../` which resolves to `/nix/store/Secrets` and breaks pure evaluation.

## Per-machine secrets (Kit-Kat)

sops encrypts a **whole file to every recipient**, so adding a machine as a recipient
of `Secrets/secrets.yaml` gives it everything in there — including
`mullvad-wg-private-key`, `cloudflare-tunnel`, `eclipse-ssh-key`, `anthropic-api-key`
and `tailscale-api-key` (an **admin** key that can rewrite tailnet ACLs and mint auth
keys). So another person's machine gets its own file:

- `Secrets/kit-kat.yaml` — holds only `user-password-hash`.
- `.sops.yaml` has a **separate creation rule for it, listed FIRST**. sops uses the
  first matching rule, so the `[Ss]ecrets/.*\.yaml$` catch-all would otherwise
  swallow it and encrypt it without her key.
- `Modules/Core/sops.nix` defines a second module, `sops-kitkat`, pointing at that file.

Her identity is **derived from the machine's ssh host key**, not a hand-copied age key:

```bash
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub     # → the &kitkat age recipient
```

with `sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` on her host. Pair
that with `nixos-anywhere --extra-files` planting a **pre-generated** host key during
the install and sops decrypts on the very first activation — no copying a key by
hand, no install-then-reinstall. See `Claude/kit-kat.md`.

`Modules/Core/sops.nix`'s original module still uses the old pattern
(`age.keyFile = /home/<user>/.config/sops/age/keys.txt`, one shared key copied to every
machine by hand). The ssh-host-key approach above is the better one; rock's hosts have
not been migrated to it.

⚠️ Never put the age **private** key in an ISO or any other world-readable store path.
It decrypts everything in `secrets.yaml`. The Apollo installer deliberately carries no
age key at all — its tailnet auth key is a plain file on the USB stick instead
(`Claude/deploy.md`).
