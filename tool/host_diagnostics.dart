import 'dart:io';

import 'package:desktop_auth_lab/host_diagnostics.dart';

Future<void> main() async {
  stdout.writeln(compactJson(await collectHostDiagnostics()));
}
