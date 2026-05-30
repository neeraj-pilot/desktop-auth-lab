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

The desktop workflow builds unsigned artifacts:

- `desktop-auth-lab-linux`: Linux release tarball, `ldd`, diagnostics.
- `desktop-auth-lab-flatpak`: standalone Flatpak bundle plus a single Flatpak
  test archive.
- `desktop-auth-lab-windows`: Windows release folder.
- `desktop-auth-lab-macos`: zipped macOS `.app`.

Release assets use direct download names:

- `desktop-auth-lab-linux-x64.tar.gz`
- `desktop-auth-lab-flatpak-test.tar.gz`
- `desktop-auth-lab.flatpak` for standalone Flatpak bundle testing
- `desktop-auth-lab-windows-x64.zip`
- `desktop-auth-lab-macos.zip`
- `desktop-auth-lab-sha256.txt`

## Flatpak Testing

See [flatpak/README.md](flatpak/README.md). The Flatpak artifact includes the
manifest, launcher, policy asset, install script, cleanup script, and guide
needed to test the Polkit host-policy setup path.
