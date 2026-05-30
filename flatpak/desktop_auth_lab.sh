#!/bin/sh
set -eu

export APPDIR=/app/share/enteauth
cd "$APPDIR"
exec ./desktop_auth_lab "$@"
