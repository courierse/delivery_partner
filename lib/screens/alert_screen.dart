import 'dart:async';
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

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});
  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance.collection('orders');
  final CollectionReference _driversCollection = FirebaseFirestore.instance.collection('drivers');
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pendingOrdersSubscription;
  StreamSubscription<QuerySnapshot>? _acceptedCancelledOrdersSubscription;
  bool _hasPendingOrders = false;
  bool _isAudioPlayerInitialized = false;
  bool _isOnDuty = false;
  Timer? _waitingTimer;

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

  Future<void> _startWaitingTimer(String orderId, String vehicleType, double initialFare) async {
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
    _waitingTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) async {
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
        }
      }
    } catch (e) {
      print('Error loading duty status: $e');
    }
  }

  Future<bool> _canGoOffDuty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final pendingSnapshot = await _ordersCollection
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))))
          .get();
      final locationState = context.read<LocationCubit>().state;
      if (locationState is! CurrentLocationUpdated) return false;
      final driverLocation = LatLng(locationState.latitude, locationState.longitude);
      final driverSnapshot = await _driversCollection.doc(user.uid).get();
      final driverData = driverSnapshot.data() as Map<String, dynamic>?;
      final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];
      final hasPendingOrders = pendingSnapshot.docs.any((doc) {
        final order = order_model.Order.fromSnapshot(doc);
        if (order.vehicleType == null || order.vehicleType!.isEmpty || !vehicleTypes.contains(order.vehicleType))
          return false;
        if (order.pickupLat == null || order.pickupLng == null) return false;
        final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
        final distance = _calculateDistance(driverLocation, pickupLoc);
        return distance <= 5.0;
      });
      final activeSnapshot = await _ordersCollection
          .where('driverId', isEqualTo: user.uid)
          .where('status', whereIn: ['accepted', 'driver_reached', 'order_picked', 'on_the_way'])
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
            const SnackBar(content: Text('Cannot go OFF Duty while there are pending or active orders')),
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are now ON Duty')));
        } else {
          _pendingOrdersSubscription?.cancel();
          _acceptedCancelledOrdersSubscription?.cancel();
          _pendingOrdersSubscription = null;
          _acceptedCancelledOrdersSubscription = null;
          await _safeStopAudio();
          await _stopWaitingTimer();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are now OFF Duty')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update duty status: $e')));
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
    if (_pendingOrdersSubscription != null || _acceptedCancelledOrdersSubscription != null) {
      print('AlertScreen: Already listening for orders');
      return;
    }
    _pendingOrdersSubscription = _ordersCollection
        .where('status', isEqualTo: 'pending')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))))
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      final locationState = context.read<LocationCubit>().state;
      if (locationState is! CurrentLocationUpdated) return;
      final driverLocation = LatLng(locationState.latitude, locationState.longitude);
      final driverSnapshot = await _driversCollection.doc(user.uid).get();
      final driverData = driverSnapshot.data() as Map<String, dynamic>?;
      final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];
      final newPendingOrders = snapshot.docs.where((doc) {
        final order = order_model.Order.fromSnapshot(doc);
        if (order.vehicleType == null || order.vehicleType!.isEmpty || !vehicleTypes.contains(order.vehicleType))
          return false;
        if (order.pickupLat == null || order.pickupLng == null) return false;
        final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
        final distance = _calculateDistance(driverLocation, pickupLoc);
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
    }, onError: (error) {
      print('Error listening to pending orders: $error');
    });
    _acceptedCancelledOrdersSubscription = _ordersCollection
        .where('driverId', isEqualTo: user.uid)
        .where('status', whereIn: ['accepted', 'driver_reached', 'order_picked', 'on_the_way', 'delivered', 'cancelled'])
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      for (var doc in snapshot.docChanges) {
        final order = order_model.Order.fromSnapshot(doc.doc);
        if (order.status == 'cancelled' && order.cancelledByUser == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order ${order.id} has been cancelled by the user.'), duration: const Duration(seconds: 5)),
          );
          await _safeStopAudio();
          await _stopWaitingTimer();
        } else if (order.status != 'driver_reached') {
          await _stopWaitingTimer();
        }
      }
    }, onError: (error) {
      print('Error listening to cancellations: $error');
    });
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371;
    final double lat1 = start.latitude * pi / 180;
    final double lon1 = start.longitude * pi / 180;
    final double lat2 = end.latitude * pi / 180;
    final double lon2 = end.longitude * pi / 180;
    final double dLat = lat2 - lat1;
    final double dLon = lon2 - lon1;
    final double a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // UPDATED: Now includes title & body
  Future<void> _sendOrderNotification(Map<String, dynamic> orderData, LatLng driverLocation) async {
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
      body: 'Pickup: ${order.pickupLocation ?? "—"}\nDrop: ${order.dropLocation ?? "—"}\n$distanceStr km',
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
        if (data['status'] != 'pending') throw Exception('Order is not pending');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order accepted!')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept order: $e')));
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
        if (data['driverId'] != user.uid) throw Exception('Order not assigned to this driver');
        if (!_isValidStatusTransition(data['status'], newStatus)) throw Exception('Invalid status transition');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order status updated to $newStatus')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update order status: $e')));
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
      await _driversCollection.doc(user.uid).collection('rejected_orders').doc(orderId).set({
        'orderId': orderId,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order rejected.')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reject order: $e')));
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
        if (!['accepted', 'driver_reached', 'order_picked', 'on_the_way'].contains(data['status']) || data['driverId'] != user.uid) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled by driver!')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel order: $e')));
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

  Future<void> _openGoogleMaps(LatLng driverLocation, LatLng destination, String locationType) async {
    try {
      if (destination.latitude == 0.0 || destination.longitude == 0.0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid $locationType location coordinates')));
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Maps')));
        }
      }
    } catch (e) {
      print('Error launching Google Maps for $locationType: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening Google Maps for $locationType: $e')));
      }
    }
  }

  Widget _buildOrderCard(order_model.Order order, bool isPending, LatLng driverLocation) {
    final distanceToPickup = _calculateDistance(driverLocation, LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0));
    final pickupLocation = LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0);
    final dropLocation = LatLng(order.dropLat ?? 0.0, order.dropLng ?? 0.0);
    final isWaiting = order.status == 'driver_reached';
    return StreamBuilder<DocumentSnapshot>(
      stream: _ordersCollection.doc(order.id).snapshots(),
      builder: (context, snapshot) {
        double currentFare = order.deliveryCost;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          currentFare = (data?['deliveryCost'] as double?) ?? order.deliveryCost;
          print('Order ${order.id} fare updated to: $currentFare');
        }
        if (order.status == 'cancelled' && order.cancelledByUser == true) {
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.2),
            child: Padding(
              padding: EdgeInsets.all(20.w),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: Colors.red, size: 30.sp),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'The Delivery has been cancelled by user',
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.2),
          child: Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPending ? 'New Delivery Request' : _getStatusTitle(order.status),
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: isPending ? Colors.blue.shade900 : Colors.green.shade700,
                      ),
                    ),
                    if (isPending)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8.r)),
                        child: Text(
                          'New',
                          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12.h),
                _buildInfoRow(Icons.location_on, 'Pickup: ${order.pickupLocation}'),
                _buildInfoRow(Icons.person, 'Contact: ${order.pickupName} - ${order.pickupPhone}'),
                _buildInfoRow(Icons.local_shipping, 'Drop-off: ${order.dropLocation}'),
                _buildInfoRow(Icons.person, 'Contact: ${order.dropName} - ${order.dropPhone}'),
                _buildInfoRow(Icons.directions_car, 'Vehicle: ${order.vehicleType ?? 'N/A'}'),
                _buildInfoRow(Icons.social_distance, 'Distance to Pickup: ${distanceToPickup.toStringAsFixed(2)} km'),
                _buildInfoRow(Icons.map, 'Total Distance: ${order.distance.toStringAsFixed(2)} km'),
                _buildInfoRow(Icons.monetization_on, 'Cost: ₹${currentFare.toStringAsFixed(2)}'),
                if (isWaiting)
                  _buildInfoRow(
                    Icons.timer,
                    'Waiting Time Active',
                    'Fare updating every ${_waitingRules[order.vehicleType ?? 'Unknown']?['intervalMinutes']} minute(s)',
                  ),
                SizedBox(height: 16.h),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => _openGoogleMaps(driverLocation, pickupLocation, 'pickup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade500,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        elevation: 2,
                        minimumSize: Size(double.infinity, 48.h),
                      ),
                      child: Text('See Pickup on Google Maps', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(height: 12.h),
                    ElevatedButton(
                      onPressed: () => _openGoogleMaps(driverLocation, dropLocation, 'drop-off'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        elevation: 2,
                        minimumSize: Size(double.infinity, 48.h),
                      ),
                      child: Text('See Drop-off on Google Maps', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                if (isPending)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _acceptOrder(order.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                          ),
                          child: Text('Accept', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _rejectOrder(order.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.grey.shade800,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                          ),
                          child: Text('Reject', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: _getStatusColor(order.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          _getStatusDisplayText(order.status),
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: _getStatusColor(order.status)),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      if (order.status == 'accepted')
                        ElevatedButton(
                          onPressed: () => _updateOrderStatus(order.id, 'driver_reached'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                            minimumSize: Size(double.infinity, 48.h),
                          ),
                          child: Text('Driver Reached', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      if (order.status == 'driver_reached')
                        ElevatedButton(
                          onPressed: () => _updateOrderStatus(order.id, 'order_picked'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                            minimumSize: Size(double.infinity, 48.h),
                          ),
                          child: Text('Order Picked', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      if (order.status == 'order_picked')
                        ElevatedButton(
                          onPressed: () => _updateOrderStatus(order.id, 'on_the_way'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                            minimumSize: Size(double.infinity, 48.h),
                          ),
                          child: Text('On The Way', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      if (order.status == 'on_the_way')
                        ElevatedButton(
                          onPressed: () => _updateOrderStatus(order.id, 'delivered'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                            elevation: 2,
                            minimumSize: Size(double.infinity, 48.h),
                          ),
                          child: Text('Order Delivered', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        ),
                      if (order.status != 'delivered' && order.status != 'completed')
                        Column(
                          children: [
                            SizedBox(height: 12.h),
                            ElevatedButton(
                              onPressed: () => _showCancelConfirmation(order.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                elevation: 2,
                                minimumSize: Size(double.infinity, 48.h),
                              ),
                              child: Text('Cancel Delivery', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getStatusTitle(String status) {
    switch (status) {
      case 'accepted': return 'Accepted Delivery';
      case 'driver_reached': return 'Reached Pickup Location';
      case 'order_picked': return 'Order Picked Up';
      case 'on_the_way': return 'Driver is on the way to deliver the order';
      case 'delivered': return 'Order Delivered';
      case 'completed': return 'Delivery Completed';
      default: return 'Delivery Status';
    }
  }

  String _getStatusDisplayText(String status) {
    switch (status) {
      case 'accepted': return 'Accepted';
      case 'driver_reached': return 'Driver Reached';
      case 'order_picked': return 'Order Picked Up';
      case 'on_the_way': return 'On The Way';
      case 'delivered': return 'Delivered';
      case 'completed': return 'Completed';
      default: return status.capitalize();
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

  Widget _buildInfoRow(IconData icon, String text, [String? subText]) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, size: 20.sp, color: Colors.blue.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade800)),
                if (subText != null)
                  Text(subText, style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
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
                        backgroundColor: _isOnDuty ? Colors.red.shade600 : Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        elevation: 2,
                      ),
                      child: Text(
                        _isOnDuty ? 'OFF Duty' : 'ON Duty',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                    child: Padding(
                      padding: EdgeInsets.all(24.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline, size: 48.sp, color: Colors.blue.shade700),
                          SizedBox(height: 16.h),
                          Text(
                            'You are OFF Duty. Turn ON Duty to receive delivery alerts.',
                            style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade600),
                                    SizedBox(height: 16.h),
                                    Text(
                                      'Location Error: ${locationState.message}',
                                      style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 16.h),
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (locationState.message.contains('permanently denied')) {
                                          await Geolocator.openAppSettings();
                                        } else {
                                          context.read<LocationCubit>().getCurrentLocation();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade700,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                        elevation: 2,
                                      ),
                                      child: Text(
                                        locationState.message.contains('permanently denied') ? 'Open Settings' : 'Retry',
                                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } else if (locationState is! CurrentLocationUpdated) {
                        return Center(child: CircularProgressIndicator(color: Colors.blue.shade700));
                      }
                      final driverLocation = LatLng(locationState.latitude, locationState.longitude);
                      final recentThreshold = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1)));
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        return Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.w),
                            child: Card(
                              elevation: 12,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                              child: Padding(
                                padding: EdgeInsets.all(24.w),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline, size: 48.sp, color: Colors.red.shade600),
                                    SizedBox(height: 16.h),
                                    Text(
                                      'Please log in to view deliveries',
                                      style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
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
                        stream: FirebaseFirestore.instance
                            .collection('orders')
                            .where('status', isEqualTo: 'pending')
                            .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Card(
                                elevation: 12,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                                child: Padding(
                                  padding: EdgeInsets.all(24.w),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade600),
                                      SizedBox(height: 16.h),
                                      Text(
                                        'Error loading pending orders: ${snapshot.error}',
                                        style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return Center(child: CircularProgressIndicator(color: Colors.blue.shade700));
                          }
                          final pendingDocs = snapshot.data!.docs;
                          final acceptedSnapshot = FirebaseFirestore.instance
                              .collection('orders')
                              .where('status', whereIn: ['accepted', 'driver_reached', 'order_picked', 'on_the_way', 'delivered'])
                              .where('driverId', isEqualTo: user.uid)
                              .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                              .get();
                          final rejectedSnapshot = _driversCollection.doc(user.uid).collection('rejected_orders').get();
                          return FutureBuilder<List<dynamic>>(
                            future: Future.wait([acceptedSnapshot, rejectedSnapshot]),
                            builder: (context, combinedSnapshot) {
                              if (combinedSnapshot.hasError) {
                                return Center(
                                  child: Card(
                                    elevation: 12,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                                    child: Padding(
                                      padding: EdgeInsets.all(24.w),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade600),
                                          SizedBox(height: 16.h),
                                          Text(
                                            'Error loading orders: ${combinedSnapshot.error}',
                                            style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              if (!combinedSnapshot.hasData) {
                                return Center(child: CircularProgressIndicator(color: Colors.blue.shade700));
                              }
                              final acceptedDocs = combinedSnapshot.data![0] as QuerySnapshot;
                              final rejectedDocs = combinedSnapshot.data![1] as QuerySnapshot;
                              final rejectedOrderIds = rejectedDocs.docs.map((doc) => doc['orderId'] as String).toSet();
                              final driverSnapshot = _driversCollection.doc(user.uid).get();
                              return FutureBuilder<DocumentSnapshot>(
                                future: driverSnapshot,
                                builder: (context, driverSnapshot) {
                                  if (driverSnapshot.hasError) {
                                    return Center(
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade600),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'Error loading driver data: ${driverSnapshot.error}',
                                                style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (!driverSnapshot.hasData || !driverSnapshot.data!.exists) {
                                    return Center(
                                      child: Card(
                                        elevation:  12,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade600),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'Driver profile not found',
                                                style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final driverData = driverSnapshot.data!.data() as Map<String, dynamic>?;
                                  final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];
                                  final orders = [
                                    ...pendingDocs.map((doc) => order_model.Order.fromSnapshot(doc)),
                                    ...acceptedDocs.docs.map((doc) => order_model.Order.fromSnapshot(doc)),
                                  ].where((order) {
                                    if (order.status == 'accepted' && order.driverId == user.uid) return true;
                                    if (order.status == 'driver_reached' && order.driverId == user.uid) return true;
                                    if (order.status == 'order_picked' && order.driverId == user.uid) return true;
                                    if (order.status == 'on_the_way' && order.driverId == user.uid) return true;
                                    if (order.status == 'delivered' && order.driverId == user.uid) return true;
                                    if (order.status != 'pending') return false;
                                    if (order.vehicleType == null || order.vehicleType!.isEmpty || !vehicleTypes.contains(order.vehicleType)) return false;
                                    if (order.pickupLat == null || order.pickupLng == null) return false;
                                    final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
                                    final distance = _calculateDistance(driverLocation, pickupLoc);
                                    return distance <= 5.0 && !rejectedOrderIds.contains(order.id);
                                  }).toList();
                                  final pendingOrders = orders.where((order) => order.status == 'pending').toList();
                                  final acceptedOrders = orders.where((order) => ['accepted', 'driver_reached', 'order_picked', 'on_the_way', 'delivered'].contains(order.status) && order.driverId == user.uid).toList();
                                  final cancelledOrders = orders.where((order) => order.status == 'cancelled' && order.cancelledByUser == true && order.driverId == user.uid).toList();
                                  order_model.Order? latestAcceptedOrder;
                                  if (acceptedOrders.isNotEmpty) {
                                    acceptedOrders.sort((a, b) => (b.statusUpdatedAt ?? b.acceptedAt ?? Timestamp.now()).compareTo(a.statusUpdatedAt ?? a.acceptedAt ?? Timestamp.now()));
                                    latestAcceptedOrder = acceptedOrders.first;
                                  }
                                  final finalOrders = [
                                    ...pendingOrders,
                                    if (latestAcceptedOrder != null) latestAcceptedOrder,
                                    ...cancelledOrders,
                                  ];
                                  if (finalOrders.isEmpty) {
                                    _safeStopAudio();
                                    return Center(
                                      child: Card(
                                        elevation: 12,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                                        child: Padding(
                                          padding: EdgeInsets.all(24.w),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.info_outline, size: 48.sp, color: Colors.blue.shade700),
                                              SizedBox(height: 16.h),
                                              Text(
                                                'No matching delivery requests within 5km.',
                                                style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  finalOrders.sort((a, b) {
                                    if (a.status == 'pending' && !['pending', 'cancelled'].contains(b.status)) return -1;
                                    if (!['pending', 'cancelled'].contains(a.status) && b.status == 'pending') return 1;
                                    if (a.status == 'cancelled' && b.status != 'cancelled') return 1;
                                    if (a.status != 'cancelled' && b.status == 'cancelled') return -1;
                                    return 0;
                                  });
                                  return ListView.builder(
                                    padding: EdgeInsets.symmetric(vertical: 8.h),
                                    itemCount: finalOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = finalOrders[index];
                                      final isPending = order.status == 'pending';
                                      return _buildOrderCard(order, isPending, driverLocation);
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