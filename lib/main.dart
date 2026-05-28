import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_authentication/flutter_local_authentication.dart';
import 'package:flutter_local_authentication/localization_model.dart';

import 'host_diagnostics.dart';

const _diagnosticsChannel = MethodChannel('desktop_auth_lab/diagnostics');

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--diagnostics')) {
    stdout.writeln(compactJson(await collectHostDiagnostics()));
    return;
  }
  runApp(const DesktopAuthLabApp());
}

class DesktopAuthLabApp extends StatelessWidget {
  const DesktopAuthLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Auth Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF146C63),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      home: const AuthLabHome(),
    );
  }
}

class AuthLabHome extends StatefulWidget {
  const AuthLabHome({super.key});

  @override
  State<AuthLabHome> createState() => _AuthLabHomeState();
}

class _AuthLabHomeState extends State<AuthLabHome> {
  final _auth = FlutterLocalAuthentication();
  final _logs = <Map<String, Object?>>[];

  Map<String, Object?> _hostDiagnostics = {};
  Map<String, Object?> _nativeDiagnostics = {};
  bool _busy = false;
  bool _authInFlight = false;
  String _logPath = '';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _prepareLogFile();
    await _refreshDiagnostics();
  }

  Future<void> _prepareLogFile() async {
    final directory = Directory(_stateDirectory());
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _logPath = '${directory.path}/auth-lab-$timestamp.jsonl';
    });
    await _appendLog('session_started', {
      'logPath': _logPath,
      'packageRef': '../flutter_local_authentication',
    });
  }

  Future<void> _refreshDiagnostics() async {
    final host = await collectHostDiagnostics();
    final native = await _collectNativeDiagnostics();
    if (!mounted) {
      return;
    }
    setState(() {
      _hostDiagnostics = host;
      _nativeDiagnostics = native;
    });
    await _appendLog('diagnostics_refreshed', {'host': host, 'native': native});
  }

  Future<Map<String, Object?>> _collectNativeDiagnostics() async {
    try {
      final result = await _diagnosticsChannel.invokeMapMethod<String, Object?>(
        'collectDiagnostics',
      );
      return result ?? {'available': false};
    } on MissingPluginException {
      return {
        'available': false,
        'error': 'native diagnostics channel is unavailable',
      };
    } on PlatformException catch (error) {
      return {
        'available': false,
        'code': error.code,
        'message': error.message ?? '',
      };
    } on Object catch (error) {
      return {'available': false, 'error': error.toString()};
    }
  }

  Future<void> _runAction(
    String name,
    Future<Map<String, Object?>> Function() action,
  ) async {
    if (_busy) {
      await _appendLog('action_skipped', {
        'name': name,
        'reason': 'another action is already running',
      });
      return;
    }

    setState(() {
      _busy = true;
    });

    final started = DateTime.now();
    await _appendLog('action_started', {'name': name});
    try {
      final details = await action();
      await _appendLog('action_finished', {
        'name': name,
        'status': 'success',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'details': details,
      });
    } on PlatformException catch (error) {
      await _appendLog('action_finished', {
        'name': name,
        'status': 'platform_exception',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'code': error.code,
        'message': error.message ?? '',
        'details': error.details,
      });
    } on Object catch (error) {
      await _appendLog('action_finished', {
        'name': name,
        'status': 'error',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'error': error.toString(),
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _appendLog(String event, Map<String, Object?> details) async {
    final entry =
        sanitizeForLog({
              'time': DateTime.now().toUtc().toIso8601String(),
              'event': event,
              ...details,
            })
            as Map<String, Object?>;

    if (mounted) {
      setState(() {
        _logs.insert(0, entry);
      });
    }

    if (_logPath.isEmpty) {
      return;
    }
    final file = File(_logPath);
    await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  Future<Map<String, Object?>> _setLocalization() async {
    _auth.setLocalizationModel(
      LocalizationModel(
        promptDialogTitle: 'Desktop Auth Lab',
        promptDialogReason: 'Authenticate as the current Linux user.',
        cancelButtonTitle: 'Cancel',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return {'applied': true};
  }

  Future<bool> _guardedAuthenticate() async {
    if (_authInFlight) {
      throw StateError('auth_request_already_in_flight');
    }
    _authInFlight = true;
    try {
      await _setLocalization();
      return await _auth.authenticate();
    } finally {
      _authInFlight = false;
    }
  }

  Future<Map<String, Object?>> _authenticateOnce() async {
    final authenticated = await _guardedAuthenticate();
    return {'authenticated': authenticated};
  }

  Future<Map<String, Object?>> _authenticateRepeated() async {
    final results = <Map<String, Object?>>[];
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        results.add({
          'attempt': attempt,
          'authenticated': await _guardedAuthenticate(),
        });
      } on PlatformException catch (error) {
        results.add({
          'attempt': attempt,
          'status': 'platform_exception',
          'code': error.code,
          'message': error.message ?? '',
        });
      } on Object catch (error) {
        results.add({
          'attempt': attempt,
          'status': 'error',
          'error': error.toString(),
        });
      }
    }
    return {'attempts': results};
  }

  Future<Map<String, Object?>> _authenticateWithConcurrentGuard() async {
    final first = _guardedAuthenticate();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    Object? secondError;
    try {
      await _guardedAuthenticate();
    } on Object catch (error) {
      secondError = error;
    }

    Object? firstResult;
    try {
      firstResult = await first;
    } on Object catch (error) {
      firstResult = error.toString();
    }

    return {
      'firstResult': firstResult,
      'secondCall': secondError?.toString() ?? 'not guarded',
    };
  }

  Future<Map<String, Object?>> _manualBadCredentialAttempt() async {
    try {
      final authenticated = await _guardedAuthenticate();
      return {
        'authenticated': authenticated,
        'expectedManualInput': 'enter an incorrect password in the PAM dialog',
      };
    } on PlatformException catch (error) {
      return {
        'status': 'platform_exception',
        'code': error.code,
        'message': error.message ?? '',
        'expectedCodes': ['authentication_failed', 'authentication_canceled'],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desktop Auth Lab'),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => unawaited(_refreshDiagnostics()),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh diagnostics',
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final diagnostics = _DiagnosticsPanel(
              hostDiagnostics: _hostDiagnostics,
              nativeDiagnostics: _nativeDiagnostics,
              logPath: _logPath,
            );
            final authPanel = _AuthPanel(
              busy: _busy,
              onCanAuthenticate: () => _runAction(
                'canAuthenticate',
                () async => {'canAuthenticate': await _auth.canAuthenticate()},
              ),
              onSetLocalization: () =>
                  _runAction('setLocalizationModel', _setLocalization),
              onAuthenticate: () =>
                  _runAction('authenticate', _authenticateOnce),
              onCancelTest: () => _runAction('cancel_test', _authenticateOnce),
              onRepeated: () =>
                  _runAction('repeated_auth_x2', _authenticateRepeated),
              onBadCredential: () => _runAction(
                'manual_bad_credential_test',
                _manualBadCredentialAttempt,
              ),
              onConcurrent: () => _runAction(
                'concurrent_call_guard',
                _authenticateWithConcurrentGuard,
              ),
              onClearLogs: () {
                setState(_logs.clear);
              },
            );
            final logs = _LogsPanel(logs: _logs);

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: diagnostics),
                  const VerticalDivider(width: 1),
                  Expanded(child: authPanel),
                  const VerticalDivider(width: 1),
                  Expanded(child: logs),
                ],
              );
            }

            return ListView(
              children: [
                SizedBox(height: 640, child: diagnostics),
                const Divider(height: 1),
                SizedBox(height: 420, child: authPanel),
                const Divider(height: 1),
                SizedBox(height: 520, child: logs),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.hostDiagnostics,
    required this.nativeDiagnostics,
    required this.logPath,
  });

  final Map<String, Object?> hostDiagnostics;
  final Map<String, Object?> nativeDiagnostics;
  final String logPath;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'System Profile',
      icon: Icons.computer,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ValueBlock(
            label: 'JSONL log file',
            value: logPath.isEmpty ? 'pending' : logPath,
          ),
          _ValueBlock(
            label: 'Host diagnostics',
            value: compactJson(hostDiagnostics),
          ),
          _ValueBlock(
            label: 'Native diagnostics',
            value: compactJson(nativeDiagnostics),
          ),
        ],
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.busy,
    required this.onCanAuthenticate,
    required this.onSetLocalization,
    required this.onAuthenticate,
    required this.onCancelTest,
    required this.onRepeated,
    required this.onBadCredential,
    required this.onConcurrent,
    required this.onClearLogs,
  });

  final bool busy;
  final VoidCallback onCanAuthenticate;
  final VoidCallback onSetLocalization;
  final VoidCallback onAuthenticate;
  final VoidCallback onCancelTest;
  final VoidCallback onRepeated;
  final VoidCallback onBadCredential;
  final VoidCallback onConcurrent;
  final VoidCallback onClearLogs;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Auth Tests',
      icon: Icons.fingerprint,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'Can authenticate',
                icon: Icons.fact_check,
                onPressed: busy ? null : onCanAuthenticate,
              ),
              _ActionButton(
                label: 'Set prompt text',
                icon: Icons.translate,
                onPressed: busy ? null : onSetLocalization,
              ),
              _ActionButton(
                label: 'Authenticate',
                icon: Icons.lock_open,
                onPressed: busy ? null : onAuthenticate,
              ),
              _ActionButton(
                label: 'Cancel test',
                icon: Icons.cancel,
                onPressed: busy ? null : onCancelTest,
              ),
              _ActionButton(
                label: 'Repeated x2',
                icon: Icons.repeat,
                onPressed: busy ? null : onRepeated,
              ),
              _ActionButton(
                label: 'Bad credential',
                icon: Icons.warning_amber,
                onPressed: busy ? null : onBadCredential,
              ),
              _ActionButton(
                label: 'Concurrent guard',
                icon: Icons.merge_type,
                onPressed: busy ? null : onConcurrent,
              ),
              _ActionButton(
                label: 'Clear log view',
                icon: Icons.delete_sweep,
                onPressed: busy ? null : onClearLogs,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: busy ? null : 0),
          const SizedBox(height: 16),
          const _ValueBlock(
            label: 'Manual scenarios',
            value:
                'Use Authenticate, Cancel test, and Bad credential with the PAM dialog. '
                'The bad credential path depends on entering an incorrect password manually; '
                'the lab never stores or injects secrets.',
          ),
        ],
      ),
    );
  }
}

class _LogsPanel extends StatelessWidget {
  const _LogsPanel({required this.logs});

  final List<Map<String, Object?>> logs;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Run Logs',
      icon: Icons.receipt_long,
      child: logs.isEmpty
          ? const Center(child: Text('No runs yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final entry = logs[index];
                final status =
                    entry['status']?.toString() ??
                    entry['event']?.toString() ??
                    '';
                final color =
                    status.contains('error') || status.contains('exception')
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle, color: color, size: 10),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry['event']?.toString() ?? 'event',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              entry['time']?.toString() ?? '',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          compactJson(entry),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemCount: logs.length,
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _stateDirectory() {
  final xdgStateHome = Platform.environment['XDG_STATE_HOME'];
  if (xdgStateHome != null && xdgStateHome.isNotEmpty) {
    return '$xdgStateHome/desktop-auth-lab';
  }
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return '$home/.local/state/desktop-auth-lab';
  }
  return '${Directory.systemTemp.path}/desktop-auth-lab';
}
