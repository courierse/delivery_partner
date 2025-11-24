import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ADD THIS
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:phone_authentication/bloc/location_cubit/location_cubit.dart';
import 'package:phone_authentication/bloc/location_cubit/location_state.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phone_authentication/models/order_model.dart' as order_model;
import 'package:url_launcher/url_launcher.dart';
import 'package:phone_authentication/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});
  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance
      .collection('orders');
  final CollectionReference _driversCollection = FirebaseFirestore.instance
      .collection('drivers');
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pendingOrdersSubscription;
  StreamSubscription<QuerySnapshot>? _acceptedCancelledOrdersSubscription;
  StreamSubscription<Position>? _locationStreamSubscription;
  Timer? _locationUpdateTimer;
  Timer? _fcmTokenRefreshTimer;
  bool _hasPendingOrders = false;
  bool _isAudioPlayerInitialized = false;
  bool _isOnDuty = false;
  Timer? _waitingTimer;
  order_model.Order? _savedAcceptedOrder;

  @override
  void initState() {
    super.initState();
    print('AlertScreen: initState called');
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _loadDutyStatus();
  }

  @override
  void dispose() {
    print('AlertScreen: dispose called');
    _pendingOrdersSubscription?.cancel();
    _acceptedCancelledOrdersSubscription?.cancel();
    _locationStreamSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _fcmTokenRefreshTimer?.cancel();
    _waitingTimer?.cancel();
    if (_isAudioPlayerInitialized) {
      try {
        print('Disposing AlertScreen: Stopping audio player');
        _audioPlayer.stop().catchError((e) {
          print('Error stopping audio during dispose: $e');
          return null;
        });
        print('Disposing AlertScreen: Disposing audio player');
        _audioPlayer.dispose().catchError((e) {
          print('Error disposing audio player: $e');
          return null;
        });
        _isAudioPlayerInitialized = false;
      } catch (e) {
        print('Unexpected error during audio player dispose: $e');
      }
    }
    super.dispose();
  }

  // Waiting time rules for each vehicle type
  final Map<String, Map<String, dynamic>> _waitingRules = {
    '2 Wheeler': {'intervalMinutes': 1, 'fareIncrement': 2.0},
    'E-Loader': {'intervalMinutes': 2, 'fareIncrement': 3.0},
    '3 Wheeler': {'intervalMinutes': 1, 'fareIncrement': 2.5},
    'Tata Ace': {'intervalMinutes': 1, 'fareIncrement': 3.5},
    '8 Feet': {'intervalMinutes': 90, 'fareIncrement': 5.0},
    '10 Feet': {'intervalMinutes': 100, 'fareIncrement': 6.0},
    '14 Feet': {'intervalMinutes': 200, 'fareIncrement': 7.0},
    '17 Feet': {'intervalMinutes': 300, 'fareIncrement': 7.0},
  };

  Future<void> _startWaitingTimer(
    String orderId,
    String vehicleType,
    double initialFare,
  ) async {
    if (_waitingTimer != null) {
      _waitingTimer!.cancel();
    }
    final rule = _waitingRules[vehicleType];
    if (rule == null) {
      print('No waiting rules found for vehicle type: $vehicleType');
      return;
    }
    final intervalSeconds = rule['intervalMinutes'] * 60;
    final fareIncrement = rule['fareIncrement'] as double;
    _waitingTimer = Timer.periodic(Duration(seconds: intervalSeconds), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final docRef = _ordersCollection.doc(orderId);
          final snapshot = await transaction.get(docRef);
          if (!snapshot.exists) {
            timer.cancel();
            return;
          }
          final data = snapshot.data() as Map<String, dynamic>?;
          if (data == null || data['status'] != 'driver_reached') {
            timer.cancel();
            return;
          }
          final currentFare = (data['deliveryCost'] as double?) ?? initialFare;
          final newFare = currentFare + fareIncrement;
          print('Updating fare for order $orderId: $currentFare -> $newFare');
          transaction.update(docRef, {
            'deliveryCost': newFare,
            'fareUpdatedAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        print('Error updating fare for order $orderId: $e');
      }
    });
  }

  Future<void> _stopWaitingTimer() async {
    if (_waitingTimer != null) {
      _waitingTimer!.cancel();
      _waitingTimer = null;
    }
  }

  // Start continuous location updates when on duty
  Future<void> _startLocationUpdates() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Stop any existing location updates
    await _stopLocationUpdates();

    try {
      // Request location permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions permanently denied');
        return;
      }

      // Start location stream
      _locationStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 50, // Update every 50 meters
        ),
      ).listen(
        (Position position) async {
          if (!mounted || !_isOnDuty) return;

          try {
            await _driversCollection.doc(user.uid).set({
              'latitude': position.latitude,
              'longitude': position.longitude,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            print(
              'Updated driver location: Lat=${position.latitude}, Lng=${position.longitude}',
            );
          } catch (e) {
            print('Error updating driver location: $e');
          }
        },
        onError: (e) {
          print('Location stream error: $e');
        },
      );

      // Also update location periodically as a backup (every 30 seconds)
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (
        timer,
      ) async {
        if (!mounted || !_isOnDuty) {
          timer.cancel();
          return;
        }
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          await _driversCollection.doc(user.uid).set({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print(
            'Periodic location update: Lat=${position.latitude}, Lng=${position.longitude}',
          );
        } catch (e) {
          print('Error in periodic location update: $e');
        }
      });

      // Refresh FCM token periodically (every 5 minutes)
      _fcmTokenRefreshTimer = Timer.periodic(const Duration(minutes: 5), (
        timer,
      ) async {
        if (!mounted || !_isOnDuty) {
          timer.cancel();
          return;
        }
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await _driversCollection.doc(user.uid).set({
              'fcmToken': fcmToken,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            print('FCM token refreshed: $fcmToken');
          }
        } catch (e) {
          print('Error refreshing FCM token: $e');
        }
      });

      print('Started location updates for driver');
    } catch (e) {
      print('Error starting location updates: $e');
    }
  }

  // Stop location updates
  Future<void> _stopLocationUpdates() async {
    _locationStreamSubscription?.cancel();
    _locationStreamSubscription = null;
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _fcmTokenRefreshTimer?.cancel();
    _fcmTokenRefreshTimer = null;
    print('Stopped location updates');
  }

  Future<void> _loadDutyStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final driverDoc = await _driversCollection.doc(user.uid).get();
      if (driverDoc.exists && mounted) {
        final data = driverDoc.data() as Map<String, dynamic>?;
        setState(() {
          _isOnDuty = data?['isOnDuty'] ?? false;
        });
        if (_isOnDuty) {
          _startListeningForOrders();
          _startLocationUpdates(); // Start location updates if already on duty
        }
      }
      // Load saved accepted order
      await _loadSavedAcceptedOrder();
    } catch (e) {
      print('Error loading duty status: $e');
    }
  }

  // Save accepted order to local storage
  Future<void> _saveAcceptedOrder(order_model.Order order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderData = {
        'id': order.id,
        'pickupLocation': order.pickupLocation,
        'pickupLat': order.pickupLat,
        'pickupLng': order.pickupLng,
        'dropLocation': order.dropLocation,
        'dropLat': order.dropLat,
        'dropLng': order.dropLng,
        'pickupName': order.pickupName,
        'pickupPhone': order.pickupPhone,
        'dropName': order.dropName,
        'dropPhone': order.dropPhone,
        'weightRange': order.weightRange,
        'userId': order.userId,
        'status': order.status,
        'distance': order.distance,
        'deliveryCost': order.deliveryCost,
        'createdAt': order.createdAt.millisecondsSinceEpoch,
        'driverId': order.driverId,
        'acceptedAt': order.acceptedAt?.millisecondsSinceEpoch,
        'completedAt': order.completedAt?.millisecondsSinceEpoch,
        'cancelledAt': order.cancelledAt?.millisecondsSinceEpoch,
        'vehicleType': order.vehicleType,
        'cancelledByUser': order.cancelledByUser,
        'statusUpdatedAt': order.statusUpdatedAt?.millisecondsSinceEpoch,
      };
      await prefs.setString('last_accepted_order', jsonEncode(orderData));
      print('Saved accepted order to local storage: ${order.id}');
    } catch (e) {
      print('Error saving accepted order: $e');
    }
  }

  // Load saved accepted order from local storage
  Future<void> _loadSavedAcceptedOrder() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      final orderJson = prefs.getString('last_accepted_order');
      if (orderJson != null) {
        final orderData = jsonDecode(orderJson) as Map<String, dynamic>;
        // Check if the order still exists in Firestore and is still active
        final orderId = orderData['id'] as String;
        final orderDoc = await _ordersCollection.doc(orderId).get();
        if (orderDoc.exists) {
          final firestoreData = orderDoc.data() as Map<String, dynamic>?;
          final status = firestoreData?['status'] as String?;
          final driverId = firestoreData?['driverId'] as String?;
          // Only load if order is still in an active state and assigned to this driver
          if (status != null &&
              driverId == user.uid &&
              [
                'accepted',
                'driver_reached',
                'order_picked',
                'on_the_way',
              ].contains(status)) {
            final order = order_model.Order.fromSnapshot(orderDoc);
            if (mounted) {
              setState(() {
                _savedAcceptedOrder = order;
              });
              print('Loaded saved accepted order: ${order.id}');
            }
          } else {
            // Order is no longer active or not assigned to this driver, clear saved order
            await prefs.remove('last_accepted_order');
            if (mounted) {
              setState(() {
                _savedAcceptedOrder = null;
              });
            }
          }
        } else {
          // Order doesn't exist in Firestore, clear saved order
          await prefs.remove('last_accepted_order');
          if (mounted) {
            setState(() {
              _savedAcceptedOrder = null;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading saved accepted order: $e');
    }
  }

  // Clear saved accepted order
  Future<void> _clearSavedAcceptedOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_accepted_order');
      if (mounted) {
        setState(() {
          _savedAcceptedOrder = null;
        });
      }
      print('Cleared saved accepted order');
    } catch (e) {
      print('Error clearing saved accepted order: $e');
    }
  }

  Future<bool> _canGoOffDuty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final pendingSnapshot =
          await _ordersCollection
              .where('status', isEqualTo: 'pending')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 1)),
                ),
              )
              .get();
      final locationState = context.read<LocationCubit>().state;
      if (locationState is! CurrentLocationUpdated) return false;
      final driverLocation = LatLng(
        locationState.latitude,
        locationState.longitude,
      );
      final driverSnapshot = await _driversCollection.doc(user.uid).get();
      final driverData = driverSnapshot.data() as Map<String, dynamic>?;
      final vehicleTypes =
          (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];
      final hasPendingOrders = pendingSnapshot.docs.any((doc) {
        final order = order_model.Order.fromSnapshot(doc);
        if (order.vehicleType == null ||
            order.vehicleType!.isEmpty ||
            !vehicleTypes.contains(order.vehicleType))
          return false;
        if (order.pickupLat == null || order.pickupLng == null) return false;
        final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
        final distance = _calculateDistance(driverLocation, pickupLoc);
        return distance <= 5.0;
      });
      final activeSnapshot =
          await _ordersCollection
              .where('driverId', isEqualTo: user.uid)
              .where(
                'status',
                whereIn: [
                  'accepted',
                  'driver_reached',
                  'order_picked',
                  'on_the_way',
                ],
              )
              .get();
      return !hasPendingOrders && activeSnapshot.docs.isEmpty;
    } catch (e) {
      print('Error checking off-duty eligibility: $e');
      return false;
    }
  }

  // UPDATED: Save FCM token + location when ON DUTY
  Future<void> _toggleDutyStatus(bool newValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to change duty status')),
        );
      }
      return;
    }
    if (!newValue) {
      final canGoOffDuty = await _canGoOffDuty();
      if (!canGoOffDuty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot go OFF Duty while there are pending or active orders',
              ),
            ),
          );
        }
        return;
      }
    }
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      final locationState = context.read<LocationCubit>().state;

      if (newValue && locationState is CurrentLocationUpdated) {
        await _driversCollection.doc(user.uid).set({
          'fcmToken': fcmToken,
          'isOnDuty': true,
          'latitude': locationState.latitude,
          'longitude': locationState.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await _driversCollection.doc(user.uid).set({
          'isOnDuty': newValue,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        setState(() {
          _isOnDuty = newValue;
          _hasPendingOrders = false;
        });
        if (_isOnDuty) {
          _startListeningForOrders();
          _startLocationUpdates(); // Start continuous location updates
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('You are now ON Duty')));
        } else {
          _pendingOrdersSubscription?.cancel();
          _acceptedCancelledOrdersSubscription?.cancel();
          _pendingOrdersSubscription = null;
          _acceptedCancelledOrdersSubscription = null;
          await _stopLocationUpdates(); // Stop location updates
          await _safeStopAudio();
          await _stopWaitingTimer();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('You are now OFF Duty')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update duty status: $e')),
        );
      }
    }
  }

  Future<void> _safePlayAudio() async {
    if (!_isAudioPlayerInitialized) {
      try {
        print('Attempting to play audio for pending orders');
        await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
        _isAudioPlayerInitialized = true;
        print('Audio played successfully');
      } catch (e) {
        print('Error playing audio: $e');
        _isAudioPlayerInitialized = false;
      }
    }
  }

  Future<void> _safeStopAudio() async {
    if (_isAudioPlayerInitialized) {
      try {
        print('Attempting to stop audio');
        await _audioPlayer.stop();
        _isAudioPlayerInitialized = false;
        print('Audio stopped successfully');
      } catch (e) {
        print('Error stopping audio: $e');
        _isAudioPlayerInitialized = false;
      }
    }
  }

  void _startListeningForOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_pendingOrdersSubscription != null ||
        _acceptedCancelledOrdersSubscription != null) {
      print('AlertScreen: Already listening for orders');
      return;
    }
    _pendingOrdersSubscription = _ordersCollection
        .where('status', isEqualTo: 'pending')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 1)),
          ),
        )
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;
            final locationState = context.read<LocationCubit>().state;
            if (locationState is! CurrentLocationUpdated) return;
            final driverLocation = LatLng(
              locationState.latitude,
              locationState.longitude,
            );
            final driverSnapshot = await _driversCollection.doc(user.uid).get();
            final driverData = driverSnapshot.data() as Map<String, dynamic>?;
            final vehicleTypes =
                (driverData?['vehicleTypes'] as String?)
                    ?.split(', ')
                    ?.toList() ??
                [];
            final newPendingOrders =
                snapshot.docs.where((doc) {
                  final order = order_model.Order.fromSnapshot(doc);
                  if (order.vehicleType == null ||
                      order.vehicleType!.isEmpty ||
                      !vehicleTypes.contains(order.vehicleType))
                    return false;
                  if (order.pickupLat == null || order.pickupLng == null)
                    return false;
                  final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
                  final distance = _calculateDistance(
                    driverLocation,
                    pickupLoc,
                  );
                  return distance <= 5.0;
                }).toList();
            final hasPendingOrders = newPendingOrders.isNotEmpty;
            if (hasPendingOrders != _hasPendingOrders && mounted) {
              setState(() {
                _hasPendingOrders = hasPendingOrders;
              });
              if (hasPendingOrders) {
                await _safePlayAudio();
                // FCM will deliver notifications; avoid duplicate local notifications here.
              } else {
                await _safeStopAudio();
              }
            }
          },
          onError: (error) {
            print('Error listening to pending orders: $error');
          },
        );
    _acceptedCancelledOrdersSubscription = _ordersCollection
        .where('driverId', isEqualTo: user.uid)
        .where(
          'status',
          whereIn: [
            'accepted',
            'driver_reached',
            'order_picked',
            'on_the_way',
            'delivered',
            'cancelled',
          ],
        )
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;
            for (var doc in snapshot.docChanges) {
              final order = order_model.Order.fromSnapshot(doc.doc);
              if (order.status == 'cancelled' &&
                  order.cancelledByUser == true &&
                  mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Order ${order.id} has been cancelled by the user.',
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
                await _safeStopAudio();
                await _stopWaitingTimer();
              } else if (order.status != 'driver_reached') {
                await _stopWaitingTimer();
              }
            }
          },
          onError: (error) {
            print('Error listening to cancellations: $error');
          },
        );
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371;
    final double lat1 = start.latitude * pi / 180;
    final double lon1 = start.longitude * pi / 180;
    final double lat2 = end.latitude * pi / 180;
    final double lon2 = end.longitude * pi / 180;
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // UPDATED: Now includes title & body
  Future<void> _sendOrderNotification(
    Map<String, dynamic> orderData,
    LatLng driverLocation,
  ) async {
    try {
      final order = order_model.Order.fromFirestore(orderData);
      if (order.pickupLat == null || order.pickupLng == null) {
        print('Order has no pickup location, skipping notification');
        return;
      }
      final pickupLocation = LatLng(order.pickupLat!, order.pickupLng!);
      final distance = _calculateDistance(driverLocation, pickupLocation);
      final distanceStr = distance.toStringAsFixed(2);

      await NotificationService().showOrderNotification(
        orderId: order.id,
        title: 'New Delivery Request',
        body:
            'Pickup: ${order.pickupLocation ?? "—"}\nDrop: ${order.dropLocation ?? "—"}\n$distanceStr km',
        pickupLocation: order.pickupLocation ?? 'Unknown',
        dropLocation: order.dropLocation ?? 'Unknown',
        distance: distanceStr,
        vehicleType: order.vehicleType ?? 'Unknown',
      );
      print('Notification sent for order ${order.id}');
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to accept orders')),
        );
      }
      return;
    }
    final locationState = context.read<LocationCubit>().state;
    if (locationState is! CurrentLocationUpdated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver location unavailable')),
        );
      }
      return;
    }
    final driverLocation = LatLng(
      locationState.latitude,
      locationState.longitude,
    );
    try {
      await _safeStopAudio();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception('Order does not exist');
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) throw Exception('Order data is null');
        if (data['status'] != 'pending')
          throw Exception('Order is not pending');
        final driverRef = _driversCollection.doc(user.uid);
        final driverSnap = await transaction.get(driverRef);
        if (!driverSnap.exists) throw Exception('Driver data not found');
        final driverData = driverSnap.data() as Map<String, dynamic>;
        transaction.update(docRef, {
          'status': 'accepted',
          'driverId': user.uid,
          'driverName': driverData['name'] ?? 'Unknown',
          'driverPhone': driverData['phone'] ?? 'Unknown',
          'driverVehicle': data['vehicleType'] ?? 'Unknown',
          'driverLatitude': driverLocation.latitude,
          'driverLongitude': driverLocation.longitude,
          'acceptedAt': FieldValue.serverTimestamp(),
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(driverRef, {
          'latitude': driverLocation.latitude,
          'longitude': driverLocation.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      // Fetch the accepted order and save it to local storage
      final acceptedOrderDoc = await _ordersCollection.doc(orderId).get();
      if (acceptedOrderDoc.exists) {
        final acceptedOrder = order_model.Order.fromSnapshot(acceptedOrderDoc);
        await _saveAcceptedOrder(acceptedOrder);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order accepted!')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to accept order: $e')));
      }
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to update order status')),
        );
      }
      return;
    }
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception('Order does not exist');
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) throw Exception('Order data is null');
        if (data['driverId'] != user.uid)
          throw Exception('Order not assigned to this driver');
        if (!_isValidStatusTransition(data['status'], newStatus))
          throw Exception('Invalid status transition');
        transaction.update(docRef, {
          'status': newStatus,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (newStatus == 'driver_reached') {
        final doc = await _ordersCollection.doc(orderId).get();
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final vehicleType = data['vehicleType'] as String? ?? 'Unknown';
          final initialFare = (data['deliveryCost'] as double?) ?? 0.0;
          await _startWaitingTimer(orderId, vehicleType, initialFare);
        }
      } else if (newStatus != 'driver_reached') {
        await _stopWaitingTimer();
      }
      // Update or clear saved order based on new status
      if (newStatus == 'delivered' || newStatus == 'cancelled') {
        // Clear saved order if delivered or cancelled
        if (_savedAcceptedOrder?.id == orderId) {
          await _clearSavedAcceptedOrder();
        }
      } else if ([
        'accepted',
        'driver_reached',
        'order_picked',
        'on_the_way',
      ].contains(newStatus)) {
        // Update saved order if still active
        final updatedOrderDoc = await _ordersCollection.doc(orderId).get();
        if (updatedOrderDoc.exists && _savedAcceptedOrder?.id == orderId) {
          final updatedOrder = order_model.Order.fromSnapshot(updatedOrderDoc);
          await _saveAcceptedOrder(updatedOrder);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order status updated to $newStatus')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update order status: $e')),
        );
      }
    }
  }

  bool _isValidStatusTransition(String currentStatus, String newStatus) {
    const validTransitions = {
      'accepted': ['driver_reached', 'cancelled'],
      'driver_reached': ['order_picked', 'cancelled'],
      'order_picked': ['on_the_way', 'cancelled'],
      'on_the_way': ['delivered', 'cancelled'],
      'delivered': ['completed'],
    };
    return validTransitions[currentStatus]?.contains(newStatus) ?? false;
  }

  Future<void> _rejectOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to reject orders')),
        );
      }
      return;
    }
    try {
      await _safeStopAudio();
      await _driversCollection
          .doc(user.uid)
          .collection('rejected_orders')
          .doc(orderId)
          .set({
            'orderId': orderId,
            'rejectedAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order rejected.')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to reject order: $e')));
      }
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to cancel orders')),
        );
      }
      return;
    }
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception('Order does not exist');
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) throw Exception('Order data is null');
        if (![
              'accepted',
              'driver_reached',
              'order_picked',
              'on_the_way',
            ].contains(data['status']) ||
            data['driverId'] != user.uid) {
          throw Exception('Order cannot be cancelled by driver');
        }
        transaction.update(docRef, {
          'status': 'cancelled',
          'cancelledByDriver': true,
          'cancelledAt': FieldValue.serverTimestamp(),
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      });
      await _safeStopAudio();
      await _stopWaitingTimer();
      // Clear saved order if this is the saved one
      if (_savedAcceptedOrder?.id == orderId) {
        await _clearSavedAcceptedOrder();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled by driver!')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to cancel order: $e')));
      }
    }
  }

  Future<void> _showCancelConfirmation(String orderId) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Cancellation'),
          content: const Text('Are you sure you want to cancel the delivery?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () async {
                Navigator.of(context).pop();
                await _cancelOrder(orderId);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGoogleMaps(
    LatLng driverLocation,
    LatLng destination,
    String locationType,
  ) async {
    try {
      if (destination.latitude == 0.0 || destination.longitude == 0.0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid $locationType location coordinates'),
            ),
          );
        }
        return;
      }
      final String googleMapsUrl =
          'https://www.google.com/maps/dir/?api=1&origin=${driverLocation.latitude},${driverLocation.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving';
      final Uri url = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      }
    } catch (e) {
      print('Error launching Google Maps for $locationType: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening Google Maps for $locationType: $e'),
          ),
        );
      }
    }
  }

  Widget _buildOrderCard(
    order_model.Order order,
    bool isPending,
    LatLng driverLocation,
  ) {
    final distanceToPickup = _calculateDistance(
      driverLocation,
      LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0),
    );
    final pickupLocation = LatLng(
      order.pickupLat ?? 0.0,
      order.pickupLng ?? 0.0,
    );
    final dropLocation = LatLng(order.dropLat ?? 0.0, order.dropLng ?? 0.0);
    return StreamBuilder<DocumentSnapshot>(
      stream: _ordersCollection.doc(order.id).snapshots(),
      builder: (context, snapshot) {
        double currentFare = order.deliveryCost;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final updatedFare = data?['deliveryCost'];
          if (updatedFare is num) {
            currentFare = updatedFare.toDouble();
          } else {
            currentFare =
                (data?['deliveryCost'] as double?) ?? order.deliveryCost;
          }
          print('Order ${order.id} fare updated to: $currentFare');
          try {
            order = order_model.Order.fromSnapshot(snapshot.data!);
          } catch (e) {
            print('Error parsing live order ${order.id}: $e');
          }
        }
        final isWaiting = order.status == 'driver_reached';
        final bool isCancelledByUser =
            order.status == 'cancelled' && order.cancelledByUser == true;
        if (isCancelledByUser) {
          return Container(
            margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.r),
              gradient: LinearGradient(
                colors: [Colors.red.shade50, Colors.red.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cancel_outlined,
                      color: Colors.red.shade700,
                      size: 28.sp,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Cancelled',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'The delivery has been cancelled by user',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24.r),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color:
                    isPending
                        ? Colors.blue.withOpacity(0.15)
                        : Colors.grey.withOpacity(0.2),
                blurRadius: 20,
                offset: Offset(0, 8),
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section with Gradient
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24.r),
                    topRight: Radius.circular(24.r),
                  ),
                  gradient: LinearGradient(
                    colors:
                        isPending
                            ? [Colors.blue.shade600, Colors.blue.shade400]
                            : [Colors.green.shade600, Colors.green.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: Icon(
                              isPending
                                  ? Icons.notifications_active
                                  : Icons.local_shipping,
                              color: Colors.white,
                              size: 20.sp,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              isPending
                                  ? 'New Delivery Request'
                                  : _getStatusTitle(order.status),
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isPending)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6.w,
                              height: 6.w,
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // Content Section - Compact Layout
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Compact Location Info - Side by Side
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pickup Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 16.sp,
                                    color: Colors.blue.shade700,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Pickup',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4.h),
                              GestureDetector(
                                onTap:
                                    () => _openGoogleMaps(
                                      driverLocation,
                                      pickupLocation,
                                      'pickup',
                                    ),
                                child: Text(
                                  order.pickupLocation ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14.sp,
                                    color: Colors.grey.shade700,
                                  ),
                                  SizedBox(width: 4.w),
                                  Expanded(
                                    child: Text(
                                      '${order.pickupName ?? 'N/A'}',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4.h),
                              GestureDetector(
                                onTap: () async {
                                  final phone = order.pickupPhone ?? '';
                                  if (phone.isNotEmpty) {
                                    final uri = Uri.parse('tel:$phone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.phone,
                                        size: 14.sp,
                                        color: Colors.blue.shade700,
                                      ),
                                      SizedBox(width: 4.w),
                                      Text(
                                        order.pickupPhone ?? 'N/A',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        // Drop-off Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_shipping,
                                    size: 16.sp,
                                    color: Colors.green.shade700,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Drop-off',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4.h),
                              GestureDetector(
                                onTap:
                                    () => _openGoogleMaps(
                                      driverLocation,
                                      dropLocation,
                                      'drop-off',
                                    ),
                                child: Text(
                                  order.dropLocation ?? 'N/A',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14.sp,
                                    color: Colors.grey.shade700,
                                  ),
                                  SizedBox(width: 4.w),
                                  Expanded(
                                    child: Text(
                                      '${order.dropName ?? 'N/A'}',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4.h),
                              GestureDetector(
                                onTap: () async {
                                  final phone = order.dropPhone ?? '';
                                  if (phone.isNotEmpty) {
                                    final uri = Uri.parse('tel:$phone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.phone,
                                        size: 14.sp,
                                        color: Colors.green.shade700,
                                      ),
                                      SizedBox(width: 4.w),
                                      Text(
                                        order.dropPhone ?? 'N/A',
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    // Compact Details Row
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildCompactDetail(
                            Icons.directions_car,
                            order.vehicleType ?? 'N/A',
                            Colors.purple.shade700,
                          ),
                          Container(
                            width: 1,
                            height: 30.h,
                            color: Colors.grey.shade300,
                          ),
                          _buildCompactDetail(
                            Icons.social_distance,
                            '${distanceToPickup.toStringAsFixed(1)} km',
                            Colors.blue.shade700,
                          ),
                          Container(
                            width: 1,
                            height: 30.h,
                            color: Colors.grey.shade300,
                          ),
                          _buildCompactDetail(
                            Icons.monetization_on,
                            '₹${currentFare.toStringAsFixed(0)}',
                            Colors.amber.shade700,
                          ),
                        ],
                      ),
                    ),
                    if (isWaiting) ...[
                      SizedBox(height: 8.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 6.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: Colors.orange.shade700,
                              size: 16.sp,
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Text(
                                'Waiting: +₹${_waitingRules[order.vehicleType ?? 'Unknown']?['fareIncrement']} every ${_waitingRules[order.vehicleType ?? 'Unknown']?['intervalMinutes']} min',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 12.h),
                    // Action Buttons
                    if (isPending)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 46.h,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade600,
                                    Colors.blue.shade700,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () => _acceptOrder(order.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.white,
                                      size: 20.sp,
                                    ),
                                    SizedBox(width: 6.w),
                                    Text(
                                      'Accept',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Container(
                              height: 46.h,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                color: Colors.grey.shade100,
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: ElevatedButton(
                                onPressed: () => _rejectOrder(order.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close,
                                      color: Colors.grey.shade700,
                                      size: 20.sp,
                                    ),
                                    SizedBox(width: 6.w),
                                    Text(
                                      'Reject',
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              vertical: 8.h,
                              horizontal: 12.w,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(
                                order.status,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10.r),
                              border: Border.all(
                                color: _getStatusColor(
                                  order.status,
                                ).withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8.w,
                                  height: 8.w,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(order.status),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  _getStatusDisplayText(
                                    order.status,
                                  ).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(order.status),
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12.h),
                          if (order.status == 'accepted')
                            _buildActionButton(
                              'Driver Reached',
                              Icons.location_on,
                              Colors.green.shade600,
                              () => _updateOrderStatus(
                                order.id,
                                'driver_reached',
                              ),
                            ),
                          if (order.status == 'driver_reached')
                            _buildActionButton(
                              'Order Picked',
                              Icons.check_circle,
                              Colors.green.shade600,
                              () =>
                                  _updateOrderStatus(order.id, 'order_picked'),
                            ),
                          if (order.status == 'order_picked')
                            _buildActionButton(
                              'On The Way',
                              Icons.directions,
                              Colors.green.shade600,
                              () => _updateOrderStatus(order.id, 'on_the_way'),
                            ),
                          if (order.status == 'on_the_way')
                            _buildActionButton(
                              'Order Delivered',
                              Icons.done_all,
                              Colors.green.shade600,
                              () => _updateOrderStatus(order.id, 'delivered'),
                            ),
                          if (order.status != 'delivered' &&
                              order.status != 'completed') ...[
                            SizedBox(height: 10.h),
                            _buildActionButton(
                              'Cancel Delivery',
                              Icons.cancel_outlined,
                              Colors.red.shade600,
                              () => _showCancelConfirmation(order.id),
                              isDestructive: true,
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStatusTitle(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted Delivery';
      case 'driver_reached':
        return 'Reached Pickup Location';
      case 'order_picked':
        return 'Order Picked Up';
      case 'on_the_way':
        return 'Driver is on the way to deliver the order';
      case 'delivered':
        return 'Order Delivered';
      case 'completed':
        return 'Delivery Completed';
      default:
        return 'Delivery Status';
    }
  }

  String _getStatusDisplayText(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'driver_reached':
        return 'Driver Reached';
      case 'order_picked':
        return 'Order Picked Up';
      case 'on_the_way':
        return 'On The Way';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      default:
        return status.capitalize();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
      case 'driver_reached':
      case 'order_picked':
      case 'on_the_way':
      case 'delivered':
      case 'completed':
        return Colors.green.shade700;
      default:
        return Colors.blue.shade700;
    }
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: 18.sp, color: color),
        ),
        SizedBox(width: 10.w),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactDetail(IconData icon, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18.sp, color: color),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(
    IconData icon,
    String label,
    String value,
    Color bgColor,
    Color iconColor,
  ) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18.sp, color: iconColor),
              SizedBox(width: 6.w),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: iconColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    bool isDestructive = false,
  }) {
    return Container(
      height: 46.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        gradient:
            isDestructive
                ? LinearGradient(
                  colors: [Colors.red.shade600, Colors.red.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : LinearGradient(
                  colors: [color, color.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        boxShadow: [
          BoxShadow(
            color: (isDestructive ? Colors.red : color).withOpacity(0.4),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20.sp),
            SizedBox(width: 6.w),
            Text(
              text,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String text, [
    String? subText,
    Color? iconColor,
  ]) {
    final color = iconColor ?? Colors.grey.shade700;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 18.sp, color: color),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subText != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    subText,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClickableInfoRow(
    IconData icon,
    String text,
    VoidCallback onTap,
    Color color,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, size: 18.sp, color: color),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14.sp, color: color),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade800, Colors.blue.shade200],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => _toggleDutyStatus(!_isOnDuty),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isOnDuty
                                ? Colors.red.shade600
                                : Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 12.h,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        _isOnDuty ? 'OFF Duty' : 'ON Duty',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isOnDuty)
                Padding(
                  padding: EdgeInsets.all(24.w),
                  child: Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(24.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48.sp,
                            color: Colors.blue.shade700,
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            'You are OFF Duty. Turn ON Duty to receive delivery alerts.',
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_isOnDuty)
                Expanded(
                  child: BlocBuilder<LocationCubit, LocationState>(
                    builder: (context, locationState) {
                      if (locationState is LocationError) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.w),
                            child: Card(
                              elevation: 12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 48.sp,
                                      color: Colors.red.shade600,
                                    ),
                                    SizedBox(height: 16.h),
                                    Text(
                                      'Location Error: ${locationState.message}',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 16.h),
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (locationState.message.contains(
                                          'permanently denied',
                                        )) {
                                          await Geolocator.openAppSettings();
                                        } else {
                                          context
                                              .read<LocationCubit>()
                                              .getCurrentLocation();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade700,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 32.w,
                                          vertical: 12.h,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12.r,
                                          ),
                                        ),
                                        elevation: 2,
                                      ),
                                      child: Text(
                                        locationState.message.contains(
                                              'permanently denied',
                                            )
                                            ? 'Open Settings'
                                            : 'Retry',
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } else if (locationState is! CurrentLocationUpdated) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue.shade700,
                          ),
                        );
                      }
                      final driverLocation = LatLng(
                        locationState.latitude,
                        locationState.longitude,
                      );
                      final recentThreshold = Timestamp.fromDate(
                        DateTime.now().subtract(const Duration(hours: 1)),
                      );
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.w),
                            child: Card(
                              elevation: 12,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 48.sp,
                                      color: Colors.red.shade600,
                                    ),
                                    SizedBox(height: 16.h),
                                    Text(
                                      'Please log in to view deliveries',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<QuerySnapshot>(
                        stream:
                            FirebaseFirestore.instance
                                .collection('orders')
                                .where('status', isEqualTo: 'pending')
                                .where(
                                  'createdAt',
                                  isGreaterThanOrEqualTo: recentThreshold,
                                )
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Card(
                                elevation: 12,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(24.w),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 48.sp,
                                        color: Colors.red.shade600,
                                      ),
                                      SizedBox(height: 16.h),
                                      Text(
                                        'Error loading pending orders: ${snapshot.error}',
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: Colors.blue.shade700,
                              ),
                            );
                          }
                          final pendingDocs = snapshot.data!.docs;
                          final acceptedSnapshot =
                              FirebaseFirestore.instance
                                  .collection('orders')
                                  .where(
                                    'status',
                                    whereIn: [
                                      'accepted',
                                      'driver_reached',
                                      'order_picked',
                                      'on_the_way',
                                      'delivered',
                                    ],
                                  )
                                  .where('driverId', isEqualTo: user.uid)
                                  .where(
                                    'createdAt',
                                    isGreaterThanOrEqualTo: recentThreshold,
                                  )
                                  .get();
                          final rejectedSnapshot =
                              _driversCollection
                                  .doc(user.uid)
                                  .collection('rejected_orders')
                                  .get();
                          return FutureBuilder<List<dynamic>>(
                            future: Future.wait([
                              acceptedSnapshot,
                              rejectedSnapshot,
                            ]),
                            builder: (context, combinedSnapshot) {
                              if (combinedSnapshot.hasError) {
                                return Center(
                                  child: Card(
                                    elevation: 12,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16.r),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(24.w),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            size: 48.sp,
                                            color: Colors.red.shade600,
                                          ),
                                          SizedBox(height: 16.h),
                                          Text(
                                            'Error loading orders: ${combinedSnapshot.error}',
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              color: Colors.grey.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              if (!combinedSnapshot.hasData) {
                                return Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.blue.shade700,
                                  ),
                                );
                              }
                              final acceptedDocs =
                                  combinedSnapshot.data![0] as QuerySnapshot;
                              final rejectedDocs =
                                  combinedSnapshot.data![1] as QuerySnapshot;
                              final rejectedOrderIds =
                                  rejectedDocs.docs
                                      .map((doc) => doc['orderId'] as String)
                                      .toSet();
                              final driverSnapshot =
                                  _driversCollection.doc(user.uid).get();
                              return FutureBuilder<DocumentSnapshot>(
                                future: driverSnapshot,
                                builder: (context, driverSnapshot) {
                                  if (driverSnapshot.hasError) {
                                    return Center(
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16.r,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                size: 48.sp,
                                                color: Colors.red.shade600,
                                              ),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'Error loading driver data: ${driverSnapshot.error}',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (!driverSnapshot.hasData ||
                                      !driverSnapshot.data!.exists) {
                                    return Center(
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16.r,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                size: 48.sp,
                                                color: Colors.red.shade600,
                                              ),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'Driver profile not found',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final driverData =
                                      driverSnapshot.data!.data()
                                          as Map<String, dynamic>?;
                                  final vehicleTypes =
                                      (driverData?['vehicleTypes'] as String?)
                                          ?.split(', ')
                                          ?.toList() ??
                                      [];
                                  final orders =
                                      [
                                        ...pendingDocs.map(
                                          (doc) => order_model
                                              .Order.fromSnapshot(doc),
                                        ),
                                        ...acceptedDocs.docs.map(
                                          (doc) => order_model
                                              .Order.fromSnapshot(doc),
                                        ),
                                      ].where((order) {
                                        if (order.status == 'accepted' &&
                                            order.driverId == user.uid)
                                          return true;
                                        if (order.status == 'driver_reached' &&
                                            order.driverId == user.uid)
                                          return true;
                                        if (order.status == 'order_picked' &&
                                            order.driverId == user.uid)
                                          return true;
                                        if (order.status == 'on_the_way' &&
                                            order.driverId == user.uid)
                                          return true;
                                        if (order.status == 'delivered' &&
                                            order.driverId == user.uid)
                                          return true;
                                        if (order.status != 'pending')
                                          return false;
                                        if (order.vehicleType == null ||
                                            order.vehicleType!.isEmpty ||
                                            !vehicleTypes.contains(
                                              order.vehicleType,
                                            ))
                                          return false;
                                        if (order.pickupLat == null ||
                                            order.pickupLng == null)
                                          return false;
                                        final pickupLoc = LatLng(
                                          order.pickupLat!,
                                          order.pickupLng!,
                                        );
                                        final distance = _calculateDistance(
                                          driverLocation,
                                          pickupLoc,
                                        );
                                        return distance <= 5.0 &&
                                            !rejectedOrderIds.contains(
                                              order.id,
                                            );
                                      }).toList();
                                  final pendingOrders =
                                      orders
                                          .where(
                                            (order) =>
                                                order.status == 'pending',
                                          )
                                          .toList();
                                  final acceptedOrders =
                                      orders
                                          .where(
                                            (order) =>
                                                [
                                                  'accepted',
                                                  'driver_reached',
                                                  'order_picked',
                                                  'on_the_way',
                                                  'delivered',
                                                ].contains(order.status) &&
                                                order.driverId == user.uid,
                                          )
                                          .toList();
                                  final cancelledOrders =
                                      orders
                                          .where(
                                            (order) =>
                                                order.status == 'cancelled' &&
                                                order.cancelledByUser == true &&
                                                order.driverId == user.uid,
                                          )
                                          .toList();
                                  order_model.Order? latestAcceptedOrder;
                                  if (acceptedOrders.isNotEmpty) {
                                    acceptedOrders.sort(
                                      (a, b) => (b.statusUpdatedAt ??
                                              b.acceptedAt ??
                                              Timestamp.now())
                                          .compareTo(
                                            a.statusUpdatedAt ??
                                                a.acceptedAt ??
                                                Timestamp.now(),
                                          ),
                                    );
                                    latestAcceptedOrder = acceptedOrders.first;
                                  }
                                  // Include saved accepted order if it exists and is not already in the list
                                  if (_savedAcceptedOrder != null) {
                                    final savedOrderInList = acceptedOrders.any(
                                      (order) =>
                                          order.id == _savedAcceptedOrder!.id,
                                    );
                                    // If saved order is not in the list and is still active, use it
                                    if (!savedOrderInList &&
                                        [
                                          'accepted',
                                          'driver_reached',
                                          'order_picked',
                                          'on_the_way',
                                        ].contains(
                                          _savedAcceptedOrder!.status,
                                        )) {
                                      // If no latest accepted order from Firestore, use saved one
                                      if (latestAcceptedOrder == null) {
                                        latestAcceptedOrder =
                                            _savedAcceptedOrder;
                                      } else {
                                        // Compare timestamps - use the more recent one
                                        final savedTimestamp =
                                            _savedAcceptedOrder!
                                                .statusUpdatedAt ??
                                            _savedAcceptedOrder!.acceptedAt ??
                                            Timestamp.now();
                                        final latestTimestamp =
                                            latestAcceptedOrder!
                                                .statusUpdatedAt ??
                                            latestAcceptedOrder!.acceptedAt ??
                                            Timestamp.now();
                                        if (savedTimestamp.compareTo(
                                              latestTimestamp,
                                            ) >
                                            0) {
                                          latestAcceptedOrder =
                                              _savedAcceptedOrder;
                                        }
                                      }
                                    }
                                  }
                                  final finalOrders = [
                                    ...pendingOrders,
                                    if (latestAcceptedOrder != null)
                                      latestAcceptedOrder,
                                    ...cancelledOrders,
                                  ];
                                  if (finalOrders.isEmpty) {
                                    _safeStopAudio();
                                    return Center(
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16.r,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 48.sp,
                                                color: Colors.blue.shade700,
                                              ),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'No matching delivery requests within 5km.',
                                                style: TextStyle(
                                                  fontSize: 16.sp,
                                                  color: Colors.grey.shade800,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  finalOrders.sort((a, b) {
                                    if (a.status == 'pending' &&
                                        ![
                                          'pending',
                                          'cancelled',
                                        ].contains(b.status))
                                      return -1;
                                    if (![
                                          'pending',
                                          'cancelled',
                                        ].contains(a.status) &&
                                        b.status == 'pending')
                                      return 1;
                                    if (a.status == 'cancelled' &&
                                        b.status != 'cancelled')
                                      return 1;
                                    if (a.status != 'cancelled' &&
                                        b.status == 'cancelled')
                                      return -1;
                                    return 0;
                                  });
                                  return ListView.builder(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 8.h,
                                    ),
                                    itemCount: finalOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = finalOrders[index];
                                      final isPending =
                                          order.status == 'pending';
                                      return _buildOrderCard(
                                        order,
                                        isPending,
                                        driverLocation,
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
