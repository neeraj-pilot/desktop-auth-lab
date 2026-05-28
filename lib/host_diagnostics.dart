import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _sensitiveWords = ['password', 'passwd', 'secret', 'token', 'credential'];

Future<Map<String, Object?>> collectHostDiagnostics() async {
  final sessionId = Platform.environment['XDG_SESSION_ID'];
  final diagnostics = <String, Object?>{
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'platform': {
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'kernel': await _commandProbe('uname', ['-a']),
      'hostname': Platform.localHostname,
    },
    'environment': _selectedEnvironment(),
    'package': {
      'name': 'flutter_local_authentication',
      'source': '../flutter_local_authentication',
      'linuxBackend': 'pam',
      'pamServiceOverride':
          Platform.environment['FLUTTER_LOCAL_AUTHENTICATION_PAM_SERVICE'] ??
          '',
    },
    'files': await _fileProbe({
      '/etc/os-release': 'distro metadata',
      '/etc/pam.d/login': 'default PAM service used by the package',
      '/etc/pam.d/sudo': 'common password PAM service',
      '/etc/pam.d/polkit-1': 'desktop policy auth service',
      '/etc/pam.d/gdm-password': 'GNOME password auth service',
      '/run/dbus/system_bus_socket': 'system D-Bus socket used by fprintd',
    }),
    'commands': await _commandAvailability([
      'fprintd-list',
      'fprintd-verify',
      'loginctl',
      'systemctl',
      'dbus-send',
      'pkcheck',
    ]),
    'distro': await _osRelease(),
  };

  if (sessionId != null && sessionId.isNotEmpty) {
    diagnostics['loginctlSession'] = await _commandProbe('loginctl', [
      'show-session',
      sessionId,
      '-p',
      'Type',
      '-p',
      'Remote',
      '-p',
      'Active',
      '-p',
      'State',
    ]);
  }

  return sanitizeForLog(diagnostics) as Map<String, Object?>;
}

dynamic sanitizeForLog(Object? value, [String key = '']) {
  if (_isSensitiveKey(key)) {
    return '<redacted>';
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): sanitizeForLog(entry.value, entry.key.toString()),
    };
  }
  if (value is Iterable) {
    return [for (final item in value) sanitizeForLog(item, key)];
  }
  if (value is String) {
    return value.replaceAllMapped(
      RegExp(
        r'\b(password|passwd|secret|token|credential)\b\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
  }
  return value;
}

String compactJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(sanitizeForLog(value));
}

bool _isSensitiveKey(String key) {
  if (key.startsWith('/')) {
    return false;
  }
  final lowerKey = key.toLowerCase();
  return _sensitiveWords.any((word) => lowerKey.contains(word));
}

Map<String, String> _selectedEnvironment() {
  const keys = [
    'USER',
    'LOGNAME',
    'SHELL',
    'XDG_CURRENT_DESKTOP',
    'DESKTOP_SESSION',
    'XDG_SESSION_TYPE',
    'XDG_SESSION_DESKTOP',
    'XDG_SESSION_ID',
    'WAYLAND_DISPLAY',
    'DISPLAY',
    'DBUS_SESSION_BUS_ADDRESS',
  ];
  return {
    for (final key in keys)
      if ((Platform.environment[key] ?? '').isNotEmpty)
        key: Platform.environment[key]!,
  };
}

Future<Map<String, Object?>> _fileProbe(Map<String, String> paths) async {
  final result = <String, Object?>{};
  for (final entry in paths.entries) {
    final type = await FileSystemEntity.type(entry.key);
    result[entry.key] = {
      'label': entry.value,
      'exists': type != FileSystemEntityType.notFound,
      'type': _fileTypeName(type),
    };
  }
  return result;
}

String _fileTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.link) {
    return 'link';
  }
  return 'notFound';
}

Future<Map<String, Object?>> _commandAvailability(List<String> commands) async {
  final result = <String, Object?>{};
  for (final command in commands) {
    result[command] = await _commandProbe('sh', ['-lc', 'command -v $command']);
  }
  return result;
}

Future<Map<String, Object?>> _commandProbe(
  String executable,
  List<String> arguments,
) async {
  try {
    final process = await Process.run(
      executable,
      arguments,
      runInShell: false,
    ).timeout(const Duration(seconds: 3));
    return {
      'available': process.exitCode == 0,
      'exitCode': process.exitCode,
      'stdout': _trimOutput(process.stdout),
      'stderr': _trimOutput(process.stderr),
    };
  } on TimeoutException {
    return {'available': false, 'error': 'timeout'};
  } on Object catch (error) {
    return {'available': false, 'error': error.toString()};
  }
}

Future<Map<String, Object?>> _osRelease() async {
  final file = File('/etc/os-release');
  if (!await file.exists()) {
    return {'available': false};
  }

  final values = <String, String>{};
  for (final line in await file.readAsLines()) {
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = line.substring(0, separator);
    final rawValue = line.substring(separator + 1);
    values[key] = rawValue.replaceAll(RegExp(r'^"|"$'), '');
  }

  return {
    'available': true,
    'prettyName': values['PRETTY_NAME'] ?? '',
    'id': values['ID'] ?? '',
    'versionId': values['VERSION_ID'] ?? '',
    'idLike': values['ID_LIKE'] ?? '',
  };
}

String _trimOutput(Object? output) {
  final text = output?.toString().trim() ?? '';
  if (text.length <= 1200) {
    return text;
  }
  return '${text.substring(0, 1200)}...';
}
