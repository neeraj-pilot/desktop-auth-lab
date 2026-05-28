# Desktop Auth Lab

Linux desktop utility for exercising Ente's local-auth assumptions before wiring
the patched `flutter_local_authentication` package into Ente Auth.

The app is intentionally narrow:

- profile the host session, distro, PAM files, fprintd command availability, and
  runtime libraries;
- run `canAuthenticate()`, `authenticate()`, repeated auth, cancel, bad
  credential, and concurrent-call guard scenarios;
- write redacted JSONL logs under `$XDG_STATE_HOME/desktop-auth-lab` or
  `$HOME/.local/state/desktop-auth-lab`;
- keep lab-only diagnostics in this app, not in the production package API.

## Local Run

```sh
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux
```

The app depends on the sibling package checkout:

```yaml
flutter_local_authentication:
  path: ../flutter_local_authentication
```

## Non-Secret Diagnostics

```sh
dart run tool/host_diagnostics.dart
```

## CI

`.github/workflows/linux.yml` checks out both this lab repo and
`neeraj-pilot/flutter_local_authentication`, runs package tests, analyzes and
tests the lab, builds the Linux release bundle, captures non-secret diagnostics,
and uploads the binary plus logs as artifacts.
