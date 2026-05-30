# Desktop Auth Lab

Desktop utility for testing Ente local authentication behavior before shipping
changes in Auth.

The lab uses:

- `local_auth` for the public Flutter API used by Ente;
- a vendored copy of Ente's `local_auth_linux` Polkit implementation under
  `packages/local_auth_linux`;
- the same Polkit action and policy asset used by Ente Auth:
  `io.ente.auth.unlock`.

## Local Run

```sh
flutter pub get
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
```

On Linux, run:

```sh
flutter config --enable-linux-desktop
```

## UI

- Run: compact auth state plus support/auth/repeated/concurrent test actions.
- Diagnostics: host and native probes as redacted JSON.
- Logs: visible log stream plus the JSONL file path.

## Non-Secret Diagnostics

```sh
dart run tool/host_diagnostics.dart
```

## CI Artifacts

The desktop workflow builds unsigned tester artifacts:

- `desktop-auth-lab-linux-packages`: native Linux AppImage, deb, rpm, and
  checksums.
- `desktop-auth-lab-flatpak-test`: one Flatpak test archive containing the
  Flatpak bundle, Polkit policy, install/cleanup scripts, manifest, and guide.
- `desktop-auth-lab-windows`: unsigned Windows installer exe and checksum.
- `desktop-auth-lab-macos`: unsigned macOS dmg and checksum.
- `desktop-auth-lab-linux-diagnostics`: Linux `ldd` and host diagnostics for CI
  debugging only.

Release assets use direct download names:

- `desktop-auth-lab-<version>-x86_64.AppImage`
- `desktop-auth-lab-<version>-amd64.deb`
- `desktop-auth-lab-<version>-1.x86_64.rpm`
- `desktop-auth-lab-flatpak-test.tar.gz`
- `desktop-auth-lab-windows-x64-installer.exe`
- `desktop-auth-lab-macos.dmg`
- `desktop-auth-lab-sha256.txt`

The raw Flutter build folders are intentionally not release assets. They are
harder for testers to run correctly and do not exercise installer assumptions.

## Flatpak Testing

See [flatpak/README.md](flatpak/README.md). The Flatpak artifact includes the
manifest, launcher, policy asset, install script, cleanup script, and guide.
The guide installs the host Polkit policy directly from a pinned GitHub URL, so
users do not need to unpack the test archive just to register the policy.

## Linux Fingerprint Notes

The Linux backend uses Polkit/PAM. `canCheckBiometrics=false` and an empty
`availableBiometrics` list are expected because the app does not enumerate
fingerprint hardware directly. The app-level readiness signal is
`Device support=true` plus `Polkit policy=installed`; fingerprint availability
depends on the host `fprintd` and PAM configuration.
