# Flatpak Test Guide

This lab uses a lab-scoped Polkit action modeled after Ente Auth:

```text
io.ente.authlab.unlock
```

The Flatpak can talk to `org.freedesktop.PolicyKit1`, but the Polkit policy
file must be installed on the host. This mirrors the expected Ente Auth Flatpak
setup behavior.

## Install From a GitHub Release

For Flatpak testing, download the Flatpak test bundle from the latest GitHub
release:

- `desktop-auth-lab-flatpak-test.tar.gz`

Then install the Flatpak:

```sh
curl -L -o desktop-auth-lab-flatpak-test.tar.gz \
  https://github.com/neeraj-pilot/desktop-auth-lab/releases/download/v0.2.3/desktop-auth-lab-flatpak-test.tar.gz

tar -xzf desktop-auth-lab-flatpak-test.tar.gz
cd desktop-auth-lab-flatpak-test
flatpak install --user ./desktop-auth-lab.flatpak
flatpak run io.ente.authlab
```

If the Run tab shows `Polkit policy: setup required`, install the host policy
directly from GitHub:

```sh
tmp="$(mktemp)"

curl -fsSL \
  https://raw.githubusercontent.com/neeraj-pilot/desktop-auth-lab/v0.2.3/assets/polkit/io.ente.authlab.policy \
  -o "$tmp"

sudo install -D -o root -g root -m 0644 \
  "$tmp" \
  /usr/share/polkit-1/actions/io.ente.authlab.policy

rm -f "$tmp"

if command -v chcon >/dev/null 2>&1; then
  sudo chcon system_u:object_r:usr_t:s0 \
    /usr/share/polkit-1/actions/io.ente.authlab.policy || true
fi

pkaction --action-id io.ente.authlab.unlock --verbose
```

Run the lab again:

```sh
flatpak run io.ente.authlab
```

## Ubuntu Fingerprint Setup

The policy above only registers the app action. Password vs fingerprint is
controlled by the host Polkit/PAM setup.

On Ubuntu, if authentication works with password but does not prompt for
fingerprint:

```sh
fprintd-list "$USER"
sudo apt install fprintd libpam-fprintd
sudo pam-auth-update
grep -n "pam_fprintd" /etc/pam.d/common-auth
cat /etc/pam.d/polkit-1
```

Enable **Fingerprint authentication** in `pam-auth-update`. Polkit should route
through `common-auth`; otherwise `/etc/pam.d/polkit-1` may remain password-only.

## Install Policy Manually

If you already have `io.ente.authlab.policy` locally, copy it to the host policy
directory, set root ownership, and apply an SELinux context when `chcon` is
available:

```sh
sudo install -D -o root -g root -m 0644 io.ente.authlab.policy /usr/share/polkit-1/actions/io.ente.authlab.policy
if command -v chcon >/dev/null 2>&1; then sudo chcon system_u:object_r:usr_t:s0 /usr/share/polkit-1/actions/io.ente.authlab.policy || true; fi
pkaction --action-id io.ente.authlab.unlock --verbose
```

The test archive also includes `install-polkit-policy.sh`, but the direct GitHub
download above is the recommended path because it is easier to paste into issue
comments.

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
sudo rm -f /usr/share/polkit-1/actions/io.ente.authlab.policy
flatpak uninstall --user io.ente.authlab
```
