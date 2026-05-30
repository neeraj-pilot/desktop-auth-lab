import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_linux/local_auth_linux.dart';

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
          seedColor: const Color(0xFF1F6F64),
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
  final _auth = LocalAuthentication();
  final _logs = <Map<String, Object?>>[];

  Map<String, Object?> _hostDiagnostics = {};
  Map<String, Object?> _nativeDiagnostics = {};
  Map<String, Object?> _status = {'state': 'starting'};
  LinuxLocalAuthSetupStatus? _linuxSetup;
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
    await _refreshAll();
  }

  Future<void> _prepareLogFile() async {
    final directory = Directory(_stateDirectory());
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    _logPath = '${directory.path}/auth-lab-$timestamp.jsonl';
    await _appendLog('session_started', {
      'logPath': _logPath,
      'package': 'local_auth',
      'linuxImplementation': 'packages/local_auth_linux',
    });
  }

  Future<void> _refreshAll() async {
    await _runAction('refresh_status', () async {
      final host = await collectHostDiagnostics();
      final native = await _collectNativeDiagnostics();
      final status = await _collectAuthStatus();
      if (mounted) {
        setState(() {
          _hostDiagnostics = host;
          _nativeDiagnostics = native;
          _status = status;
        });
      }
      return {'status': status, 'host': host, 'native': native};
    }, updateBusy: false);
  }

  Future<Map<String, Object?>> _collectNativeDiagnostics() async {
    if (!Platform.isLinux) {
      return {'available': false, 'reason': 'linux-only'};
    }
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

  Future<Map<String, Object?>> _collectAuthStatus() async {
    LinuxLocalAuthSetupStatus? linuxSetup;
    if (Platform.isLinux) {
      linuxSetup = await _getLinuxSetupStatus();
    }

    Object? deviceSupported;
    Object? canCheckBiometrics;
    Object? biometrics;
    try {
      deviceSupported = await _auth.isDeviceSupported();
    } on Object catch (error) {
      deviceSupported = error.toString();
    }
    try {
      canCheckBiometrics = await _auth.canCheckBiometrics;
    } on Object catch (error) {
      canCheckBiometrics = error.toString();
    }
    try {
      biometrics = (await _auth.getAvailableBiometrics())
          .map((type) => type.name)
          .toList();
    } on Object catch (error) {
      biometrics = error.toString();
    }

    if (mounted) {
      setState(() {
        _linuxSetup = linuxSetup;
      });
    }

    return {
      'state': 'ready',
      'platform': Platform.operatingSystem,
      'deviceSupported': deviceSupported,
      'canCheckBiometrics': canCheckBiometrics,
      'availableBiometrics': biometrics,
      if (linuxSetup != null)
        'linuxSetup': {
          'actionId': linuxSetup.actionId,
          'polkitAvailable': linuxSetup.polkitAvailable,
          'policyInstalled': linuxSetup.policyInstalled,
          'setupRequired': linuxSetup.setupRequired,
          'isFlatpak': linuxSetup.isFlatpak,
          'policyAssetPath': linuxSetup.policyAssetPath,
          'errorMessage': linuxSetup.errorMessage,
        },
    };
  }

  Future<LinuxLocalAuthSetupStatus?> _getLinuxSetupStatus() async {
    try {
      return await LocalAuthLinux().getSetupStatus();
    } on PlatformException catch (error) {
      await _appendLog('linux_setup_status_failed', {
        'code': error.code,
        'message': error.message ?? '',
      });
      return null;
    } on Object catch (error) {
      await _appendLog('linux_setup_status_failed', {
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<void> _runAction(
    String name,
    Future<Map<String, Object?>> Function() action, {
    bool updateBusy = true,
  }) async {
    if (_busy && updateBusy) {
      await _appendLog('action_skipped', {
        'name': name,
        'reason': 'another action is already running',
      });
      return;
    }

    if (updateBusy && mounted) {
      setState(() {
        _busy = true;
      });
    }

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
    } on LocalAuthException catch (error) {
      await _appendLog('action_finished', {
        'name': name,
        'status': 'local_auth_exception',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        ..._localAuthExceptionDetails(error),
      });
    } on PlatformException catch (error) {
      await _appendLog('action_finished', {
        'name': name,
        'status': 'platform_exception',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        ..._platformExceptionDetails(error),
      });
    } on Object catch (error) {
      await _appendLog('action_finished', {
        'name': name,
        'status': 'error',
        'durationMs': DateTime.now().difference(started).inMilliseconds,
        'error': error.toString(),
      });
    } finally {
      if (updateBusy && mounted) {
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
    await File(
      _logPath,
    ).writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  Future<bool> _guardedAuthenticate() async {
    if (_authInFlight) {
      throw const LocalAuthException(
        code: LocalAuthExceptionCode.authInProgress,
        description: 'Authentication is already in progress.',
      );
    }
    _authInFlight = true;
    try {
      await _auth.stopAuthentication();
      return await _auth.authenticate(
        localizedReason: 'Authenticate to test desktop local auth.',
      );
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
      } on LocalAuthException catch (error) {
        results.add({
          'attempt': attempt,
          'status': 'local_auth_exception',
          ..._localAuthExceptionDetails(error),
        });
      } on PlatformException catch (error) {
        results.add({
          'attempt': attempt,
          'status': 'platform_exception',
          ..._platformExceptionDetails(error),
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

  Future<Map<String, Object?>> _manualFailureAttempt() async {
    final authenticated = await _guardedAuthenticate();
    return {
      'authenticated': authenticated,
      'expectedManualInput':
          'cancel the prompt, deny it, or provide a failing system credential',
    };
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Desktop Auth Lab'),
          actions: [
            IconButton(
              onPressed: _busy ? null : () => unawaited(_refreshAll()),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.play_circle), text: 'Run'),
              Tab(icon: Icon(Icons.rule), text: 'Diagnostics'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Logs'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _RunTab(
                busy: _busy,
                status: _status,
                linuxSetup: _linuxSetup,
                onCanAuthenticate: () => _runAction(
                  'can_authenticate',
                  () async => await _collectAuthStatus(),
                ),
                onAuthenticate: () =>
                    _runAction('authenticate', _authenticateOnce),
                onCancelTest: () =>
                    _runAction('cancel_or_deny_test', _manualFailureAttempt),
                onRepeated: () =>
                    _runAction('repeated_auth_x2', _authenticateRepeated),
                onConcurrent: () => _runAction(
                  'concurrent_call_guard',
                  _authenticateWithConcurrentGuard,
                ),
              ),
              _DiagnosticsTab(
                hostDiagnostics: _hostDiagnostics,
                nativeDiagnostics: _nativeDiagnostics,
              ),
              _LogsTab(
                logPath: _logPath,
                logs: _logs,
                onClearLogs: _busy
                    ? null
                    : () {
                        setState(_logs.clear);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunTab extends StatelessWidget {
  const _RunTab({
    required this.busy,
    required this.status,
    required this.linuxSetup,
    required this.onCanAuthenticate,
    required this.onAuthenticate,
    required this.onCancelTest,
    required this.onRepeated,
    required this.onConcurrent,
  });

  final bool busy;
  final Map<String, Object?> status;
  final LinuxLocalAuthSetupStatus? linuxSetup;
  final VoidCallback onCanAuthenticate;
  final VoidCallback onAuthenticate;
  final VoidCallback onCancelTest;
  final VoidCallback onRepeated;
  final VoidCallback onConcurrent;

  @override
  Widget build(BuildContext context) {
    final setupRequired = linuxSetup?.setupRequired == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatusTile(
              label: 'Platform',
              value: status['platform']?.toString() ?? Platform.operatingSystem,
              icon: Icons.desktop_windows,
            ),
            _StatusTile(
              label: 'Device support',
              value: status['deviceSupported']?.toString() ?? 'pending',
              icon: Icons.verified_user,
            ),
            _StatusTile(
              label: 'Biometrics',
              value: status['canCheckBiometrics']?.toString() ?? 'pending',
              icon: Icons.fingerprint,
            ),
            if (linuxSetup != null)
              _StatusTile(
                label: 'Polkit policy',
                value: linuxSetup!.policyInstalled
                    ? 'installed'
                    : setupRequired
                    ? 'setup required'
                    : 'unavailable',
                icon: Icons.policy,
                isWarning: setupRequired,
              ),
          ],
        ),
        if (setupRequired) ...[
          const SizedBox(height: 20),
          _CommandBlock(command: linuxSetup!.policyInstallCommand),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              label: 'Check support',
              icon: Icons.fact_check,
              onPressed: busy ? null : onCanAuthenticate,
            ),
            _ActionButton(
              label: 'Authenticate',
              icon: Icons.lock_open,
              onPressed: busy ? null : onAuthenticate,
            ),
            _ActionButton(
              label: 'Cancel / deny',
              icon: Icons.cancel,
              onPressed: busy ? null : onCancelTest,
            ),
            _ActionButton(
              label: 'Repeated x2',
              icon: Icons.repeat,
              onPressed: busy ? null : onRepeated,
            ),
            _ActionButton(
              label: 'Concurrent guard',
              icon: Icons.merge_type,
              onPressed: busy ? null : onConcurrent,
            ),
          ],
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(value: busy ? null : 0),
      ],
    );
  }
}

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({
    required this.hostDiagnostics,
    required this.nativeDiagnostics,
  });

  final Map<String, Object?> hostDiagnostics;
  final Map<String, Object?> nativeDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ValueBlock(
          label: 'Host diagnostics',
          value: compactJson(hostDiagnostics),
        ),
        _ValueBlock(
          label: 'Native diagnostics',
          value: compactJson(nativeDiagnostics),
        ),
      ],
    );
  }
}

class _LogsTab extends StatelessWidget {
  const _LogsTab({
    required this.logPath,
    required this.logs,
    required this.onClearLogs,
  });

  final String logPath;
  final List<Map<String, Object?>> logs;
  final VoidCallback? onClearLogs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  logPath.isEmpty ? 'Log file pending' : logPath,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              TextButton.icon(
                onPressed: onClearLogs,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear view'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('No runs yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
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
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
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
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemCount: logs.length,
                ),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
    required this.icon,
    this.isWarning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isWarning
              ? colorScheme.errorContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    return _ValueBlock(label: 'Linux setup command', value: command);
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
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

Map<String, Object?> _localAuthExceptionDetails(LocalAuthException error) {
  return {
    'code': error.code.name,
    'message': error.description ?? '',
    'issue': _localAuthIssue(error),
  };
}

Map<String, Object?> _platformExceptionDetails(PlatformException error) {
  return {
    'code': error.code,
    'message': error.message ?? '',
    'details': error.details,
    'issue': _platformIssue(error),
  };
}

String? _localAuthIssue(LocalAuthException error) {
  if (Platform.isLinux &&
      error.code == LocalAuthExceptionCode.noCredentialsSet &&
      (error.description?.contains('Polkit policy') ?? false)) {
    return 'linux_setup_required';
  }
  if (!Platform.isWindows) {
    return null;
  }
  return _windowsIssue(error.code.name, error.description);
}

String? _platformIssue(PlatformException error) {
  if (!Platform.isWindows) {
    return null;
  }
  return _windowsIssue(error.code, error.message);
}

String? _windowsIssue(String code, String? description) {
  final normalizedCode = code.toLowerCase();
  final normalizedDescription = description?.toLowerCase() ?? '';
  if (normalizedCode.contains('notenrolled') ||
      normalizedCode.contains('nocredentialsset') ||
      normalizedCode.contains('nobiometricsenrolled')) {
    return 'not_configured';
  }
  if (normalizedCode.contains('nohardware') ||
      normalizedCode.contains('nobiometrichardware')) {
    return 'no_hardware';
  }
  if (normalizedCode.contains('devicebusy') ||
      normalizedCode.contains('authinprogress') ||
      normalizedCode.contains('temporarilyunavailable')) {
    return 'busy';
  }
  if (normalizedCode.contains('disabledbypolicy') ||
      normalizedDescription.contains('group policy')) {
    return 'disabled_by_policy';
  }
  if (normalizedCode.contains('notavailable') ||
      normalizedCode.contains('unavailable') ||
      normalizedCode.contains('deviceerror') ||
      normalizedCode.contains('uiunavailable') ||
      normalizedCode.contains('unknownerror')) {
    return 'unavailable';
  }
  return null;
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
