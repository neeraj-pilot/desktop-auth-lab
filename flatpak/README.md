# Flatpak Test Guide

This lab uses the same Polkit action as Ente Auth:

```text
io.ente.auth.unlock
```

The Flatpak can talk to `org.freedesktop.PolicyKit1`, but the Polkit policy
file must be installed on the host. This mirrors the expected Ente Auth Flatpak
setup behavior.

## Install From a GitHub Release

Download these assets from the latest GitHub release:

- `desktop-auth-lab.flatpak`
- `desktop-auth-lab-flatpak-test-kit.tar.gz`

Then install the app:

```sh
flatpak install --user ./desktop-auth-lab.flatpak
flatpak run io.ente.authlab
```

If the Run tab shows `Polkit policy: setup required`, install the host policy
from the test kit:

```sh
tar -xzf desktop-auth-lab-flatpak-test-kit.tar.gz
./flatpak-test-kit/install-polkit-policy.sh
```

Run the lab again:

```sh
flatpak run io.ente.authlab
```

## Install Policy Manually

The installer copies `io.ente.auth.policy` to the host policy directory, sets
root ownership, and applies an SELinux context when `chcon` is available:

```sh
sudo install -D -o root -g root -m 0644 io.ente.auth.policy /usr/share/polkit-1/actions/io.ente.auth.policy
if command -v chcon >/dev/null 2>&1; then sudo chcon system_u:object_r:usr_t:s0 /usr/share/polkit-1/actions/io.ente.auth.policy || true; fi
pkaction --action-id io.ente.auth.unlock --verbose
```

The release also attaches `io.ente.auth.policy` and
`install-polkit-policy.sh` directly for testers who only want the policy setup
files.

## Before Flathub Publish

This flow does not need a Flathub listing. A GitHub release asset is enough for
testing the Flatpak bundle and the host policy registration path.

After an Ente Auth Flathub package exists, the same host policy still has to be
installed somewhere under the host Polkit policy search path. The published app
can make the bundled-policy path more predictable, but it cannot silently write
to `/usr/share/polkit-1/actions` from inside the sandbox.

## Manual Build From a Linux Bundle

From the repository root, after `flutter build linux --release`:

```sh
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//46 org.gnome.Sdk//46
flatpak-builder --user --force-clean --repo=build/flatpak-repo build/flatpak-build flatpak/io.ente.authlab.yml
flatpak build-bundle build/flatpak-repo build/desktop-auth-lab.flatpak io.ente.authlab
```

## Cleanup

Only remove the host policy if you installed it solely for this lab:

```sh
./flatpak-test-kit/uninstall-polkit-policy.sh
flatpak uninstall --user io.ente.authlab
```
