#!/bin/sh
set -eu

action_id="io.ente.auth.unlock"
policy_name="io.ente.auth.policy"
target="/usr/share/polkit-1/actions/$policy_name"

script_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")"
  pwd
)

source_path="${1:-}"
if [ -z "$source_path" ] && [ -f "$script_dir/$policy_name" ]; then
  source_path="$script_dir/$policy_name"
fi

if [ -z "$source_path" ]; then
  app_id="${FLATPAK_ID:-io.ente.authlab}"
  if command -v flatpak >/dev/null 2>&1; then
    install_dir="$(flatpak info --show-location "$app_id" 2>/dev/null || true)"
    candidate="$install_dir/files/share/enteauth/data/flutter_assets/assets/polkit/$policy_name"
    if [ -n "$install_dir" ] && [ -f "$candidate" ]; then
      source_path="$candidate"
    fi
  fi
fi

if [ -z "$source_path" ] || [ ! -f "$source_path" ]; then
  echo "Could not find $policy_name." >&2
  echo "Run from the Flatpak test kit directory or pass the policy path." >&2
  exit 1
fi

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
  echo "sudo is required unless this script is run as root." >&2
  exit 1
fi

run_as_root install -D -o root -g root -m 0644 "$source_path" "$target"

if command -v chcon >/dev/null 2>&1; then
  run_as_root chcon system_u:object_r:usr_t:s0 "$target" 2>/dev/null || true
fi

echo "Installed $target"

if command -v pkaction >/dev/null 2>&1; then
  pkaction --action-id "$action_id" --verbose
else
  echo "pkaction is not available; restart the lab and check setup status."
fi
