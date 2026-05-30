#!/bin/sh
set -eu

target="/usr/share/polkit-1/actions/io.ente.auth.policy"

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

run_as_root rm -f "$target"
echo "Removed $target"
