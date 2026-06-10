#!/bin/sh
set -eu

export APPDIR=/app/share/desktop-auth-lab
cd "$APPDIR"
exec ./desktop_auth_lab "$@"
