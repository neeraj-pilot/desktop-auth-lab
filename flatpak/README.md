# Flatpak Test Guide

This lab uses the same Polkit action as Ente Auth:

```text
io.ente.auth.unlock
```

The Flatpak can talk to `org.freedesktop.PolicyKit1`, but the host policy file
still has to be installed on the host. This mirrors the expected Ente Auth
Flatpak setup behavior.

## Install the CI Flatpak Bundle

Download the `desktop-auth-lab-flatpak` artifact from GitHub Actions, then:

```sh
flatpak install --user ./desktop-auth-lab.flatpak
flatpak run io.ente.authlab
```

If the Run tab shows `Polkit policy: setup required`, install the host policy:

```sh
app_id=io.ente.authlab
install_dir="$(flatpak info --show-location "$app_id")"
pkexec install -D -m 0644 "$install_dir/files/share/enteauth/data/flutter_assets/assets/polkit/io.ente.auth.policy" /usr/share/polkit-1/actions/io.ente.auth.policy
pkaction --action-id io.ente.auth.unlock --verbose
```

Run the lab again:

```sh
flatpak run io.ente.authlab
```

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
pkexec rm -f /usr/share/polkit-1/actions/io.ente.auth.policy
flatpak uninstall --user io.ente.authlab
```
