import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sos_app/router.dart';
import 'package:telephony/telephony.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:phone_state/phone_state.dart';

import 'contacts_screen.dart';
import 'calling_screen.dart';
import 'emergency_contacts.dart';

// --- State Management ---

final sequentialCallProvider =
    StateNotifierProvider<SequentialCallNotifier, List<Map<String, String>>>(
        (ref) {
  return SequentialCallNotifier();
});

class SequentialCallNotifier extends StateNotifier<List<Map<String, String>>> {
  StreamSubscription<PhoneState>? _callStateSubscription;
  bool _isCalling = false;
  bool _wasInCall = false;
  Timer? _nextCallTimer;

  SequentialCallNotifier() : super([]);

  void startSOS(List<Map<String, String>> contacts) {
    if (contacts.isEmpty) return;
    state = List.from(contacts);
    _listenToCallStates();
    _callCurrentNumber();
  }

  void _callCurrentNumber() async {
    if (state.isEmpty) {
      stopSOS();
      return;
    }

    final numberToCall = state.first['phone']!;
    debugPrint('📞 Attempting to call number: $numberToCall');
    try {
      _isCalling = true;
      _wasInCall = false;
      await FlutterPhoneDirectCaller.callNumber(numberToCall);
    } catch (e) {
      debugPrint('❌ Error calling $numberToCall: $e');
      _advanceToNext();
    }
  }

  void _advanceToNext() {
    debugPrint('✅ Call finished with ${state.first['name']}');
    _isCalling = false;

    // Remove the contact that was just called
    final updatedContacts = List<Map<String, String>>.from(state);
    if (updatedContacts.isNotEmpty) {
      updatedContacts.removeAt(0);
    }
    state = updatedContacts;

    if (state.isNotEmpty) {
      debugPrint('➡️ Moving to next number in 2 seconds...');
      _nextCallTimer = Timer(const Duration(seconds: 2), _callCurrentNumber);
    } else {
      debugPrint('🏁 Finished all calls.');
      stopSOS();
    }
  }

  void _listenToCallStates() {
    _callStateSubscription?.cancel();
    _callStateSubscription = PhoneState.stream.listen((phoneState) {
      debugPrint('📲 Received call state: ${phoneState.status}');

      if (!_isCalling) return;

      if (phoneState.status == PhoneStateStatus.CALL_STARTED) {
        _wasInCall = true;
      }

      if (phoneState.status == PhoneStateStatus.CALL_ENDED && _wasInCall) {
        _wasInCall = false;
        _advanceToNext();
      }
    });
  }

  void stopSOS() {
    debugPrint('🛑 Stopping SOS, cancelling call listener.');
    _callStateSubscription?.cancel();
    _nextCallTimer?.cancel(); // <-- cancel future scheduled calls
    state = [];
    _isCalling = false;
    _wasInCall = false;
  }

  @override
  void dispose() {
    _callStateSubscription?.cancel();
    _nextCallTimer?.cancel();
    super.dispose();
  }
}

// --- UI and App Setup ---

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SOS',
      theme: ThemeData(
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
      routerConfig: router,
    );
  }
}

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  Future<bool> _requestPermissions(BuildContext context) async {
    final permissions = [Permission.sms, Permission.location, Permission.phone];
    Map<Permission, PermissionStatus> statuses = await permissions.request();
    bool allGranted = true;
    statuses.forEach((permission, status) {
      debugPrint(
        'Permission: ${permission.toString()}, Status: ${status.toString()}',
      );
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    if (!allGranted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All permissions are required. Please check app settings.',
          ),
        ),
      );
      await openAppSettings();
    }
    return allGranted;
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied)
        return Future.error('Location permissions are denied');
    }
    if (permission == LocationPermission.deniedForever)
      return Future.error('Location permissions are permanently denied.');
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _handleSOS(BuildContext context, WidgetRef ref) async {
    final hasPermissions = await _requestPermissions(context);
    if (!hasPermissions) return;

    try {
      final position = await _determinePosition();
      final locationMessage =
          "Emergency! I need help. My current location is: https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";

      final telephony = Telephony.instance;
      for (var contact in emergencyContacts) {
        await telephony.sendSms(
            to: contact['phone']!, message: locationMessage);
      }

      // Start the sequential caller
      ref.read(sequentialCallProvider.notifier).startSOS(emergencyContacts);

      // NOW that all the work has started, navigate to the calling screen.
      if (context.mounted) {
        context.go('/calling');
      }
    } catch (e) {
      debugPrint('An error occurred during SOS setup: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/sgito_360.png', // your logo path
          height: 30, // adjust as needed
        ),
        backgroundColor: const Color(0xFFF52324A),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts, color: Colors.white),
            onPressed: () => context.go('/contacts'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _handleSOS(context, ref),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer circle
                  Container(
                    width: 245,
                    height: 245,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFFBFA7C2,
                      ).withOpacity(0.3), // faint background
                    ),
                  ),

                  // Middle circle
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFF805C75,
                      ).withOpacity(0.6), // darker ring
                    ),
                  ),

                  // Inner circle with gradient
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.8,
                        colors: [
                          Color(0xFF52324A), // lighter / inner
                          Color(0xFF805C75), // darker / outer
                        ],
                        stops: [0.3, 1.0],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'SOS',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 50),
            const Text(
              'Tapping SOS will call all emergency contacts and send them your location.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 50), // <-- pushes logo to bottom

            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Image.asset(
                'assets/images/sgito_360.png', // place your logo file here
                height: 60, // adjust size
              ),
            ),
          ],
        ),
      ),
    );
  }
}
