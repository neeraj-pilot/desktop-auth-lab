#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_NAME="desktop-auth-lab"
APP_ID="io.ente.authlab"
DISPLAY_NAME="Desktop Auth Lab"
INSTALL_DIR="/usr/share/desktop-auth-lab"
BUNDLE_DIR="build/linux/x64/release/bundle"
ARTIFACT_DIR="artifacts"
DIST_DIR="dist"
POLICY_ASSET="assets/polkit/io.ente.authlab.policy"
DESKTOP_FILE="linux/packaging/io.ente.authlab.desktop"
METAINFO_FILE="flatpak/io.ente.authlab.metainfo.xml"
ICON_FILE="flatpak/io.ente.authlab.png"

VERSION="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml | head -n1)"
if [[ -z "$VERSION" ]]; then
  echo "Could not read version from pubspec.yaml" >&2
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Linux release bundle not found: $BUNDLE_DIR" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR" "$DIST_DIR"

write_native_wrapper() {
  local target="$1"
  cat >"$target" <<'SH'
#!/bin/sh
set -eu
cd /usr/share/desktop-auth-lab
exec ./desktop_auth_lab "$@"
SH
  chmod 0755 "$target"
}

copy_native_payload() {
  local root="$1"
  mkdir -p \
    "$root$INSTALL_DIR" \
    "$root/usr/bin" \
    "$root/usr/share/applications" \
    "$root/usr/share/metainfo" \
    "$root/usr/share/icons/hicolor/256x256/apps" \
    "$root/usr/share/polkit-1/actions"

  cp -a "$BUNDLE_DIR"/. "$root$INSTALL_DIR"/
  write_native_wrapper "$root/usr/bin/$PACKAGE_NAME"
  install -m 0644 "$DESKTOP_FILE" "$root/usr/share/applications/$APP_ID.desktop"
  install -m 0644 "$METAINFO_FILE" "$root/usr/share/metainfo/$APP_ID.metainfo.xml"
  install -m 0644 "$ICON_FILE" "$root/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"
  install -m 0644 "$POLICY_ASSET" "$root/usr/share/polkit-1/actions/io.ente.authlab.policy"
}

build_appimage() {
  if ! command -v appimagetool >/dev/null 2>&1; then
    echo "appimagetool is required" >&2
    exit 1
  fi

  local appdir="$DIST_DIR/appimage/$PACKAGE_NAME.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/share/metainfo" "$appdir/usr/share/icons/hicolor/256x256/apps"
  cp -a "$BUNDLE_DIR"/. "$appdir"/
  install -m 0644 "$DESKTOP_FILE" "$appdir/$APP_ID.desktop"
  install -m 0644 "$METAINFO_FILE" "$appdir/usr/share/metainfo/$APP_ID.metainfo.xml"
  install -m 0644 "$ICON_FILE" "$appdir/$APP_ID.png"
  install -m 0644 "$ICON_FILE" "$appdir/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"

  cat >"$appdir/$PACKAGE_NAME" <<'SH'
#!/bin/sh
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
export APPDIR="${APPDIR:-$HERE}"
cd "$HERE"
exec "$HERE/desktop_auth_lab" "$@"
SH
  chmod 0755 "$appdir/$PACKAGE_NAME"
  ln -sf "$PACKAGE_NAME" "$appdir/AppRun"

  ARCH=x86_64 appimagetool "$appdir" "$ARTIFACT_DIR/$PACKAGE_NAME-$VERSION-x86_64.AppImage"
}

build_deb() {
  local staging="$DIST_DIR/deb-staging"
  rm -rf "$staging"
  copy_native_payload "$staging"
  mkdir -p "$staging/DEBIAN"
  local installed_size
  installed_size="$(du -sk "$staging" | awk '{print $1}')"
  cat >"$staging/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Ente Developers <auth@ente.com>
Installed-Size: $installed_size
Depends: libgtk-3-0, policykit-1 | polkitd
Description: Desktop utility for testing local authentication assumptions
 $DISPLAY_NAME tests Ente desktop local authentication assumptions.
EOF
  dpkg-deb --build --root-owner-group "$staging" "$ARTIFACT_DIR/$PACKAGE_NAME-$VERSION-amd64.deb"
}

build_rpm() {
  if ! command -v fpm >/dev/null 2>&1; then
    echo "fpm is required" >&2
    exit 1
  fi

  local staging="$DIST_DIR/rpm-staging"
  rm -rf "$staging"
  copy_native_payload "$staging"

  fpm -s dir -t rpm \
    -n "$PACKAGE_NAME" \
    -v "$VERSION" \
    --iteration 1 \
    --architecture x86_64 \
    --vendor "Ente" \
    --maintainer "Ente Developers <auth@ente.com>" \
    --license "GPL-3.0-or-later" \
    --url "https://github.com/neeraj-pilot/desktop-auth-lab" \
    --description "$DISPLAY_NAME tests Ente desktop local authentication assumptions." \
    --category "Application/Utility" \
    --depends gtk3 \
    --depends polkit \
    -C "$staging" \
    -p "$ARTIFACT_DIR/$PACKAGE_NAME-$VERSION-1.x86_64.rpm" \
    .
}

build_appimage
build_deb
build_rpm
