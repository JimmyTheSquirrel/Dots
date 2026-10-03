# system-rebuild — packaged by Modules/Shell/deploy-tools.nix (writeShellApplication:
# errexit/nounset/pipefail are already on, and shellcheck runs at build time).
#
# The single entry point. Two jobs behind one menu:
#   1. rebuild a system (local boot profile, or push to a remote machine)
#   2. deploy a system onto NEW hardware through the Apollo USB
#
# The USB itself (building the ISO, writing the tailnet key) is deliberately
# NOT here: it is a rare, fiddly operation done from this machine, not
# something to stumble into from a rebuild menu. apollo-iso / apollo-key
# still exist as commands. apollo-connect (SSH to the booted stick) is on
# the navi cheatsheet.
cd "$HOME/Dots" || { echo "❌ ~/Dots not found"; exit 1; }

# host              flake user   kind    ssh target
# ------------------------------------------------------------------
# Sisyphus          rock         local   -
# Kit-Kat           kitkat       remote  kitkat@kit-kat
#
# kind=local  -> sudo nixos-rebuild -p <profile>   (GRUB boot profile here)
# kind=remote -> nixos-rebuild --target-host       (separate machine, no -p)
host_meta() {
  case "$1" in
    Sisyphus) echo "rock   local  -" ;;
    Kit-Kat)  echo "kitkat remote kitkat@kit-kat" ;;
    *)        echo "" ;;
  esac
}

ask() { local p="$1"; shift; local r; read -r -p "$p" r; echo "$r"; }
title() {
  echo -e "\033[1;36m╭──────────────────────────────╮\033[0m"
  printf  "\033[1;36m│\033[0m %-28s \033[1;36m│\033[0m\n" "$1"
  echo -e "\033[1;36m╰──────────────────────────────╯\033[0m"
}

# Only a placeholder: every path below replaces it — host_meta for a known
# host, the first argument on the CLI.
user="$(id -un)"
system=""
action="switch"
target_override=""
mode="rebuild"

if [[ -z "${1:-}" ]]; then
  # ── interactive ──────────────────────────────────────────────────
  title "Dots"
  echo ""
  echo "  1) Rebuild a system      — push changes to a machine that already runs NixOS"
  echo "  2) Deploy a system       — install onto NEW hardware booted from the Apollo USB"
  echo ""
  case "$(ask 'What [1-2]: ')" in
    1) mode="rebuild" ;;
    2) mode="deploy"  ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac


  echo ""
  if [[ "$mode" == "deploy" ]]; then
    title "Deploy onto NEW hardware"
    echo ""
    echo -e "\033[1;33m  The target must already be booted from the Apollo USB.\033[0m"
    echo -e "\033[1;33m  Check with: apollo-connect\033[0m"
    echo ""
    echo "  1) Kit-Kat   (her machine)"
    echo ""
    case "$(ask 'Deploy which system [1]: ')" in
      1) system="Kit-Kat" ;;
      *) echo "Invalid choice"; exit 1 ;;
    esac

    echo ""
    echo "  1) Dry run   — print the disk script, change nothing"
    echo "  2) VM test   — apply the layout in a throwaway VM"
    echo "  3) INSTALL   — ERASES the target's disks"
    echo ""
    read -r fu _ _ <<< "$(host_meta "$system")"
    case "$(ask 'What [1-3]: ')" in
      1) exec apollo-deploy --dry-run "${fu}-${system}" ;;
      2) exec apollo-deploy --vm-test "${fu}-${system}" ;;
      3) exec apollo-deploy "${fu}-${system}" ;;
      *) echo "Invalid choice"; exit 1 ;;
    esac
  fi

  title "Rebuild a system"
  echo ""
  echo "  1) Sisyphus  (Niri — this disk)"
  echo "  2) Kit-Kat   (Hyprland — her machine, over the tailnet)"
  echo ""
  case "$(ask 'System [1-2]: ')" in
    1) system="Sisyphus" ;;
    2) system="Kit-Kat"  ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac

  echo ""
  echo "  1) Switch  (rebuild & activate now)"
  echo "  2) Boot    (rebuild, activate on next boot)"
  # `nixos-rebuild build`, NOT `nixos-rebuild test` — this option was labelled
  # "Test" for a long time, which in nixos-rebuild terms means *activate now
  # without a boot entry*: the opposite of what it did.
  echo "  3) Build   (build only, activate nothing)"
  echo ""
  case "$(ask 'Action [1-3]: ')" in
    1) action="switch" ;;
    2) action="boot"   ;;
    3) action="build"  ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
else
  # ── CLI: system-rebuild USER SYSTEM [--boot|--build] [--target HOST] ─
  user="${1:-}"
  system="${2:-}"
  shift 2 || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --boot) action="boot" ;;
      # --test kept as an alias so old muscle memory still works; it has
      # always meant "build only", never nixos-rebuild's own `test`.
      --build|--test) action="build" ;;
      --target) target_override="${2:-}"; shift ;;
      *) echo "Unknown option: $1"; exit 2 ;;
    esac
    shift
  done
  if [[ -z "$system" ]]; then
    echo "Usage: system-rebuild USER SYSTEM [--boot|--build] [--target HOST]"
    echo "   or: system-rebuild            (interactive — rebuild/deploy/apollo)"
    exit 2
  fi
fi

# Asgard's config is edited ON Asgard — Claude/server-info.md: "edit
# server.nix on Asgard, not here — it drifts". Pushing this repo's copy
# would overwrite the live config with a stale one, so refuse unless an
# explicit --target says you really mean it.
if [[ "$system" == "Asgard" && -z "$target_override" ]]; then
  echo -e "\033[1;31m==> Asgard is managed on Asgard, not from here.\033[0m"
  echo "    ssh asgard && sudo nixos-rebuild switch --flake ~/Dots#rock-Asgard"
  echo "To override deliberately: system-rebuild rock Asgard --target asgard"
  exit 1
fi

read -r meta_user meta_kind meta_target <<< "$(host_meta "$system")"
[[ -n "${meta_user:-}" ]] && user="$meta_user"
remote_host=""
[[ "${meta_kind:-}" == "remote" ]] && remote_host="${meta_target#*@}"
[[ -n "$target_override" ]] && remote_host="$target_override"

flake_key="${user}-${system}"

if [[ -n "$remote_host" ]]; then
  ssh_target="${user}@${remote_host}"
  echo -e "\n\033[1;34m==> Deploying ${system} to ${ssh_target}...\033[0m"
  if [[ "$action" == "build" ]]; then
    cmd=(nixos-rebuild build --flake ".#${flake_key}")
  else
    # --ask-sudo-password prompts here and feeds it over; only Asgard sets
    # wheelNeedsPassword = false.
    cmd=(nixos-rebuild "${action}" --flake ".#${flake_key}"
         --target-host "${ssh_target}" --ask-sudo-password)
  fi
elif [[ "$action" == "build" ]]; then
  # No sudo for a plain build: it activates nothing, so it needs no root —
  # and as root it left a root-owned ./result symlink in ~/Dots. No -p either;
  # a profile only matters to something that installs a generation.
  echo -e "\n\033[1;34m==> Build ${system}...\033[0m"
  cmd=(nixos-rebuild build --flake ".#${flake_key}")
else
  profile=$(echo "$system" | tr '[:upper:]' '[:lower:]')
  echo -e "\n\033[1;34m==> ${action^} ${system} (profile: ${profile})...\033[0m"
  cmd=(sudo nixos-rebuild "${action}" -p "${profile}" --flake ".#${flake_key}")
fi

if "${cmd[@]}"; then
  echo -e "\n\033[1;32m==> Done!\033[0m"
  # An `if`, not `[[ ... ]] && echo`. As the LAST statement in the script
  # that form returns the test's status, so a successful *switch* (where
  # the test is false) made the whole command exit 1 — printing "Done!"
  # and then reporting failure to anything chaining off it.
  if [[ "$action" == "boot" && -z "$remote_host" ]]; then
    echo -e "\033[1;33m==> Reboot and select ${system} from GRUB.\033[0m"
  fi
else
  echo -e "\n\033[1;31m==> Build failed.\033[0m"
  exit 1
fi
