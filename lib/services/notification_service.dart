import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:phone_authentication/firebase_options.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permission
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('Notification permission denied');
        return;
      }

      // Initialize local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final orderId = response.payload;
          if (orderId != null) {
            print('Notification tapped: Order ID = $orderId');
          }
        },
      );

      // Create channel
      const channel = AndroidNotificationChannel(
        'order_channel',
        'Delivery Alerts',
        description: 'New delivery requests',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alert'),
        enableVibration: true,
      );

      final androidPlugin =
          _localNotifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await androidPlugin?.createNotificationChannel(channel);

      // Get FCM token and persist to driver profile if logged in
      _fcmToken = await _fcm.getToken();
      print('FCM Token: $_fcmToken');
      await _persistTokenToDriver(_fcmToken);

      // Token refresh
      _fcm.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        print('FCM Token refreshed: $token');
        await _persistTokenToDriver(token);
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((message) {
        print('Foreground FCM: ${message.data}');
        _showFromData(message.data);
      });

      // App opened from notification
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        print('App opened from FCM: ${message.data}');
        _showFromData(message.data);
      });

      // Initial message
      final initial = await _fcm.getInitialMessage();
      if (initial != null) {
        _showFromData(initial.data);
      }

      _isInitialized = true;
    } catch (e) {
      print('Notification init error: $e');
    }
  }

  void _showFromData(Map<String, dynamic> data) {
    if (data.isEmpty) return;

    final orderId = data['orderId'] ?? 'unknown';
    final title = data['title'] ?? 'New Delivery Request';
    final body = data['body'] ?? 'Check app for details';

    showOrderNotification(
      orderId: orderId,
      title: title,
      body: body,
      pickupLocation: data['pickupAddress'] ?? 'Unknown',
      dropLocation: data['dropAddress'] ?? 'Unknown',
      distance: data['distance'] ?? '0.0',
      vehicleType: data['vehicleType'] ?? 'Unknown',
    );
  }

  Future<void> showOrderNotification({
    required String orderId,
    required String title,
    required String body,
    required String pickupLocation,
    required String dropLocation,
    required String distance,
    required String vehicleType,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'order_channel',
      'Delivery Alerts',
      channelDescription: 'New delivery requests',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alert'),
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      orderId.hashCode,
      title,
      body,
      details,
      payload: orderId,
    );
  }

  String? get fcmToken => _fcmToken;
}

// BACKGROUND HANDLER (MUST BE TOP-LEVEL)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await firebase_core.Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('Background FCM: ${message.data}');

  // If a notification payload is present, Android will show it in the system tray.
  // Avoid creating a duplicate local notification.
  if (message.notification != null) {
    return;
  }

  final data = message.data;
  if (data.isEmpty) return;

  final service = NotificationService();
  await service.initialize();

  await service.showOrderNotification(
    orderId: data['orderId'] ?? 'unknown',
    title: data['title'] ?? 'New Delivery Request',
    body: data['body'] ?? 'Pickup: Unknown\nDrop: Unknown',
    pickupLocation: data['pickupAddress'] ?? 'Unknown',
    dropLocation: data['dropAddress'] ?? 'Unknown',
    distance: data['distance'] ?? '0.0',
    vehicleType: data['vehicleType'] ?? 'Unknown',
  );
}

Future<void> _persistTokenToDriver(String? token) async {
  if (token == null || token.isEmpty) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
    // Swallow errors to avoid breaking init flow
    // Consider adding your own logging infrastructure here
    // print('Failed to persist FCM token: $e');
  }
}
