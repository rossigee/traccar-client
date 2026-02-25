import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:traccar_client/main.dart';
import 'package:traccar_client/password_service.dart';
import 'package:traccar_client/preferences.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'l10n/app_localizations.dart';
import 'status_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  Future<void> _onDestinationSelected(int index) async {
    if (index == 2) {
      if (await PasswordService.authenticate(context) && mounted) {
        setState(() => _selectedIndex = index);
      }
    } else {
      if (_selectedIndex != index) {
        setState(() => _selectedIndex = index);
      }
      if (index == 0) {
        // Refresh home tab by reloading last known location
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [_HomeTab(), StatusScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.satellite_alt_outlined),
            selectedIcon: const Icon(Icons.satellite_alt),
            label: l10n.trackingTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: l10n.statusTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({super.key});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  bool _trackingEnabled = false;
  bool? _isMoving;
  double? _latitude;
  double? _longitude;
  double? _speed;
  double? _heading;
  bool? _syncSuccess;
  int? _syncStatus;
  bool _syncInFlight = false;
  DateTime? _lastSyncTime;
  DateTime? _syncStartedAt;
  Timer? _refreshTimer;

  // Stored callback references so they can be individually removed in dispose().
  void Function(bool)? _onEnabledChange;
  void Function(bg.Location)? _onMotionChange;
  void Function(bg.Location)? _onLocation;
  void Function(bg.HttpEvent)? _onHttp;

  @override
  void initState() {
    super.initState();
    _loadLastKnownLocation();
    _initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        // Check for sync timeout
        if (_syncInFlight && _syncStartedAt != null) {
          final elapsed = DateTime.now().difference(_syncStartedAt!);
          if (elapsed.inSeconds > 30) {
            setState(() {
              _syncInFlight = false;
              _syncSuccess = false;
              _syncStatus = 0;
              _lastSyncTime = DateTime.now();
            });
            _syncStartedAt = null;
          }
        }
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_onEnabledChange != null) {
      bg.BackgroundGeolocation.removeListener(_onEnabledChange!);
    }
    if (_onMotionChange != null) {
      bg.BackgroundGeolocation.removeListener(_onMotionChange!);
    }
    if (_onLocation != null) {
      bg.BackgroundGeolocation.removeListener(_onLocation!);
    }
    if (_onHttp != null) {
      bg.BackgroundGeolocation.removeListener(_onHttp!);
    }
    super.dispose();
  }

  void _loadLastKnownLocation() {
    final lastLat = Preferences.instance.getDouble(Preferences.lastLatitude);
    final lastLon = Preferences.instance.getDouble(Preferences.lastLongitude);
    final lastSync = Preferences.instance.getString('lastSyncTime');
    if (lastLat != null && lastLon != null) {
      _latitude = lastLat;
      _longitude = lastLon;
    }
    if (lastSync != null) {
      _lastSyncTime = DateTime.tryParse(lastSync);
    }
  }

  void _initState() async {
    final state = await bg.BackgroundGeolocation.state;
    if (!mounted) return;
    setState(() {
      _trackingEnabled = state.enabled;
      _isMoving = state.isMoving;
    });

    _onEnabledChange = (bool enabled) {
      if (mounted) setState(() => _trackingEnabled = enabled);
    };
    _onMotionChange = (bg.Location location) {
      if (mounted) setState(() => _isMoving = location.isMoving);
    };
    _onLocation = (bg.Location location) {
      if (mounted) {
        setState(() {
          _latitude = location.coords.latitude;
          _longitude = location.coords.longitude;
          _speed = location.coords.speed;
          _heading = location.coords.heading;
          _syncInFlight = true;
          _syncStartedAt = DateTime.now();
        });
        Preferences.instance.setDouble(
          Preferences.lastLatitude,
          location.coords.latitude,
        );
        Preferences.instance.setDouble(
          Preferences.lastLongitude,
          location.coords.longitude,
        );
      }
    };
    _onHttp = (bg.HttpEvent event) {
      if (mounted) {
        setState(() {
          _syncSuccess = event.success;
          _syncStatus = event.status;
          _syncInFlight = false;
          _syncStartedAt = null;
          _lastSyncTime = DateTime.now();
        });
        Preferences.instance.setString(
          'lastSyncTime',
          _lastSyncTime!.toIso8601String(),
        );
      }
    };

    bg.BackgroundGeolocation.onEnabledChange(_onEnabledChange!);
    bg.BackgroundGeolocation.onMotionChange(_onMotionChange!);
    bg.BackgroundGeolocation.onLocation(_onLocation!);
    bg.BackgroundGeolocation.onHttp(_onHttp!);
  }

  Future<void> _checkBatteryOptimizations(BuildContext context) async {
    try {
      if (!await bg.DeviceSettings.isIgnoringBatteryOptimizations) {
        final request =
            await bg.DeviceSettings.showIgnoreBatteryOptimizations();
        if (!request.seen && context.mounted) {
          showDialog(
            context: context,
            builder:
                (_) => AlertDialog(
                  scrollable: true,
                  content: Text(
                    AppLocalizations.of(context)!.optimizationMessage,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        bg.DeviceSettings.show(request);
                      },
                      child: Text(AppLocalizations.of(context)!.okButton),
                    ),
                  ],
                ),
          );
        }
      }
    } catch (error) {
      debugPrint(error.toString());
    }
  }

  Future<void> _toggleTracking(bool value) async {
    if (await PasswordService.authenticate(context) && mounted) {
      if (value) {
        try {
          if (firebaseEnabled) {
            FirebaseCrashlytics.instance.log('tracking_toggle_start');
          }
          await bg.BackgroundGeolocation.start();
          if (mounted) {
            _checkBatteryOptimizations(context);
          }
        } on PlatformException catch (error) {
          final providerState = await bg.BackgroundGeolocation.providerState;
          final isPermissionError =
              providerState.status ==
                  bg.ProviderChangeEvent.AUTHORIZATION_STATUS_DENIED ||
              providerState.status ==
                  bg.ProviderChangeEvent.AUTHORIZATION_STATUS_RESTRICTED;
          if (!mounted) return;
          messengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(error.message ?? error.code),
              duration: const Duration(seconds: 4),
              action:
                  isPermissionError
                      ? SnackBarAction(
                        label: AppLocalizations.of(context)!.settingsTitle,
                        onPressed:
                            () => AppSettings.openAppSettings(
                              type: AppSettingsType.settings,
                            ),
                      )
                      : null,
            ),
          );
        }
      } else {
        if (firebaseEnabled) {
          FirebaseCrashlytics.instance.log('tracking_toggle_stop');
        }
        await bg.BackgroundGeolocation.stop();
      }
    }
  }

  Color _heroColor(ColorScheme cs) {
    if (!_trackingEnabled) return cs.surfaceContainerHighest;
    if (_isMoving == true) return cs.secondaryContainer;
    return cs.primaryContainer;
  }

  Color _heroContentColor(ColorScheme cs) {
    if (!_trackingEnabled) return cs.onSurfaceVariant;
    if (_isMoving == true) return cs.onSecondaryContainer;
    return cs.onPrimaryContainer;
  }

  String _heroStatusText() {
    if (!_trackingEnabled) return 'Tracking Inactive';
    if (_isMoving == true) return 'Tracking Active · Moving';
    return 'Tracking Active · Stationary';
  }

  String _getHeadingDirection(double heading) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _getSyncStatus() {
    final intervalSeconds = Preferences.instance.getInt(Preferences.interval) ?? 300;

    if (_syncInFlight && _syncStartedAt != null) {
      final elapsed = DateTime.now().difference(_syncStartedAt!);
      return 'Sending... (${30 - elapsed.inSeconds}s)';
    }

    final t = _lastSyncTime;
    if (t == null) return 'Never synced - Next: ~${intervalSeconds}s';

    final elapsed = DateTime.now().difference(t);
    final ago = _formatDuration(elapsed);
    final nextIn = intervalSeconds - elapsed.inSeconds;

    if (_syncSuccess == true) return 'OK - $ago | Next: ~${nextIn}s';
    if (_syncSuccess == false && _syncStatus == 0)
      return 'TIMEOUT - $ago | Next: ~${nextIn}s';
    if (_syncSuccess == false)
      return 'FAILED ($_syncStatus) - $ago | Next: ~${nextIn}s';
    return 'Unknown - $ago | Next: ~${nextIn}s';
  }

    final t = _lastSyncTime;
    if (t == null) return 'Never synced - Next in ~${intervalSeconds}s';

    final elapsed = DateTime.now().difference(t);
    final ago = _formatDuration(elapsed);
    final nextIn = intervalSeconds - elapsed.inSeconds;

    if (_syncSuccess == true) return 'Last: OK - $ago | Next: ~${nextIn}s';
    if (_syncSuccess == false && _syncStatus == 0)
      return 'Last: TIMEOUT - $ago | Next: ~${nextIn}s';
    if (_syncSuccess == false)
      return 'Last: FAILED ($_syncStatus) - $ago | Next: ~${nextIn}s';
    return 'Last: Unknown - $ago | Next: ~${nextIn}s';
  }



  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final contentColor = _heroContentColor(cs);

    return Scaffold(
      appBar: AppBar(title: const Text('Traccar Client')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: _heroColor(cs),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    _trackingEnabled
                        ? Icons.satellite_alt
                        : Icons.satellite_alt_outlined,
                    key: ValueKey(_trackingEnabled),
                    size: 32,
                    color: contentColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _heroStatusText(),
                  style: tt.titleMedium?.copyWith(color: contentColor),
                ),
                const SizedBox(height: 8),
                Switch(value: _trackingEnabled, onChanged: _toggleTracking),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoRow(
                            label: l10n.idLabel,
                            value:
                                Preferences.instance.getString(
                                  Preferences.id,
                                ) ??
                                '',
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            label: l10n.urlLabel,
                            value:
                                Preferences.instance.getString(
                                  Preferences.url,
                                ) ??
                                '',
                          ),
                          if (_latitude != null && _longitude != null) ...[
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Coordinates',
                              value:
                                  '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                            ),
                          ],
                          if (_speed != null) ...[
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Speed',
                              value:
                                  '${(_speed! * 3.6).toStringAsFixed(1)} km/h',
                            ),
                          ],
                          if (_heading != null) ...[
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Heading',
                              value:
                                  '${_heading!.toStringAsFixed(0)}° ${_getHeadingDirection(_heading!)}',
                            ),
                          ],
                          if (_syncInFlight || _lastSyncTime != null) ...[
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Server Sync',
                              value: _getSyncStatus(),
                            ),
                          ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () async {
                      try {
                        await bg.BackgroundGeolocation.getCurrentPosition(
                          samples: 1,
                          persist: true,
                          extras: {'manual': true},
                        );
                      } on PlatformException catch (error) {
                        messengerKey.currentState?.showSnackBar(
                          SnackBar(content: Text(error.message ?? error.code)),
                        );
                      }
                    },
                    child: Text(l10n.locationButton),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(
          value,
          style: tt.bodyMedium,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}
