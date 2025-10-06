import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:phone_authentication/bloc/location_cubit/location_cubit.dart';
import 'package:phone_authentication/bloc/location_cubit/location_state.dart';
import 'package:phone_authentication/constants/colors.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phone_authentication/models/order_model.dart' as order_model;
import 'package:url_launcher/url_launcher.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance.collection('orders');
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot>? _pendingOrdersSubscription;
  StreamSubscription<QuerySnapshot>? _acceptedCancelledOrdersSubscription;
  bool _hasPendingOrders = false;
  bool _isAudioPlayerInitialized = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _startListeningForOrders();
  }

  @override
  void dispose() {
    _pendingOrdersSubscription?.cancel();
    _acceptedCancelledOrdersSubscription?.cancel();
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

    _pendingOrdersSubscription = _ordersCollection
        .where('status', isEqualTo: 'pending')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))))
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      final locationState = context.read<LocationCubit>().state;
      if (locationState is! CurrentLocationUpdated) return;

      final driverLocation = LatLng(locationState.latitude, locationState.longitude);
      final driverSnapshot = await FirebaseFirestore.instance.collection('drivers').doc(user.uid).get();
      final driverData = driverSnapshot.data() as Map<String, dynamic>?;
      final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];

      final newPendingOrders = snapshot.docs.where((doc) {
        final order = order_model.Order.fromSnapshot(doc);
        if (order.vehicleType == null || order.vehicleType!.isEmpty || !vehicleTypes.contains(order.vehicleType)) return false;
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
        } else {
          await _safeStopAudio();
        }
      }
    }, onError: (error) {
      print('Error listening to pending orders: $error');
    });

    _acceptedCancelledOrdersSubscription = _ordersCollection
        .where('driverId', isEqualTo: user.uid)
        .where('status', whereIn: ['accepted', 'cancelled', 'picked_up', 'on_the_way', 'reached', 'delivered'])
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      for (var doc in snapshot.docChanges) {
        final order = order_model.Order.fromSnapshot(doc.doc);
        if (order.status == 'cancelled' && order.cancelledByUser == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order ${order.id} has been cancelled by the user.'),
              duration: const Duration(seconds: 5),
            ),
          );
          await _safeStopAudio();
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

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  Future<void> _acceptOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to accept orders')),
      );
      return;
    }

    final locationState = context.read<LocationCubit>().state;
    if (locationState is! CurrentLocationUpdated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver location unavailable')),
      );
      return;
    }

    final driverLocation = LatLng(locationState.latitude, locationState.longitude);

    try {
      await _safeStopAudio();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Order does not exist');
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Order data is null');
        }
        if (data['status'] != 'pending') {
          throw Exception('Order is not pending');
        }

        final driverRef = FirebaseFirestore.instance.collection('drivers').doc(user.uid);
        final driverSnap = await transaction.get(driverRef);
        if (!driverSnap.exists) {
          throw Exception('Driver data not found');
        }
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
        });

        transaction.set(
          driverRef,
          {
            'latitude': driverLocation.latitude,
            'longitude': driverLocation.longitude,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order accepted!')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to accept order: $e')),
      );
    }
  }

  Future<void> _rejectOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to reject orders')),
      );
      return;
    }

    try {
      await _safeStopAudio();
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .collection('rejected_orders')
          .doc(orderId)
          .set({
        'orderId': orderId,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order rejected.')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject order: $e')),
      );
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to cancel orders')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Order does not exist');
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Order data is null');
        }
        if (data['status'] != 'accepted' && data['status'] != 'picked_up' && data['status'] != 'on_the_way' && data['status'] != 'reached') {
          throw Exception('Order cannot be cancelled by driver');
        }
        if (data['driverId'] != user.uid) {
          throw Exception('Order not assigned to this driver');
        }

        transaction.update(docRef, {
          'status': 'cancelled',
          'cancelledByDriver': true,
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      });
      await _safeStopAudio();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled by driver!')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel order: $e')),
      );
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to update order status')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Order does not exist');
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data == null) {
          throw Exception('Order data is null');
        }
        if (data['driverId'] != user.uid) {
          throw Exception('Order not assigned to this driver');
        }
        if (!_isValidStatusTransition(data['status'], newStatus)) {
          throw Exception('Invalid status transition from ${data['status']} to $newStatus');
        }

        final updateData = <String, dynamic>{
          'status': newStatus,
        };

        // Set the appropriate timestamp field based on the new status
        switch (newStatus) {
          case 'picked_up':
            updateData['pickedUpAt'] = FieldValue.serverTimestamp();
            break;
          case 'on_the_way':
            updateData['onTheWayAt'] = FieldValue.serverTimestamp();
            break;
          case 'reached':
            updateData['reachedAt'] = FieldValue.serverTimestamp();
            break;
          case 'delivered':
            updateData['deliveredAt'] = FieldValue.serverTimestamp();
            break;
        }

        print('Updating order $orderId with data: $updateData');
        transaction.update(docRef, updateData);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order updated to ${newStatus.replaceAll('_', ' ')}')),
      );
      setState(() {});
    } catch (e) {
      print('Failed to update order status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update order status: $e')),
      );
    }
  }

  bool _isValidStatusTransition(String? currentStatus, String newStatus) {
    switch (newStatus) {
      case 'picked_up':
        return currentStatus == 'accepted';
      case 'on_the_way':
        return currentStatus == 'picked_up';
      case 'reached':
        return currentStatus == 'on_the_way';
      case 'delivered':
        return currentStatus == 'reached';
      default:
        return false;
    }
  }

  Future<void> _showCancelConfirmation(String orderId) async {
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
              onPressed: () {
                Navigator.of(context).pop();
              },
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid $locationType location coordinates')),
        );
        return;
      }

      final String googleMapsUrl =
          'https://www.google.com/maps/dir/?api=1&origin=${driverLocation.latitude},${driverLocation.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=driving';
      final Uri url = Uri.parse(googleMapsUrl);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    } catch (e) {
      print('Error launching Google Maps for $locationType: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening Google Maps for $locationType: $e')),
      );
    }
  }

  Widget _buildOrderCard(order_model.Order order, bool isPending, LatLng driverLocation) {
    final distanceToPickup = _calculateDistance(
      driverLocation,
      LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0),
    );
    final pickupLocation = LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0);
    final dropLocation = LatLng(order.dropLat ?? 0.0, order.dropLng ?? 0.0);

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
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
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
                  isPending ? 'New Delivery Request' : _getStatusText(order.status),
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: isPending ? Colors.blue.shade900 : Colors.green.shade700,
                  ),
                ),
                if (isPending)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      'New',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
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
            _buildInfoRow(Icons.scale, 'Weight: ${order.weightRange}'),
            _buildInfoRow(Icons.social_distance, 'Distance to Pickup: ${distanceToPickup.toStringAsFixed(2)} km'),
            _buildInfoRow(Icons.map, 'Total Distance: ${order.distance.toStringAsFixed(2)} km'),
            _buildInfoRow(Icons.monetization_on, 'Cost: ₹${order.deliveryCost.toStringAsFixed(2)}'),
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
                  child: Text(
                    'See Pickup on Google Maps',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
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
                  child: Text(
                    'See Drop-off on Google Maps',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                  ),
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
                      child: Text(
                        'Accept',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
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
                      child: Text(
                        'Reject',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
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
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      _getStatusText(order.status),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  if (order.status != 'delivered') ...[
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
                      child: Text(
                        'Cancel Delivery',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: order.status == 'accepted'
                                ? () => _updateOrderStatus(order.id, 'picked_up')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: order.status == 'accepted' ? Colors.green.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              elevation: 2,
                            ),
                            child: Text(
                              'Order Picked Up',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: order.status == 'picked_up'
                                ? () => _updateOrderStatus(order.id, 'on_the_way')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: order.status == 'picked_up' ? Colors.green.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              elevation: 2,
                            ),
                            child: Text(
                              'Driver On the Way',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: order.status == 'on_the_way'
                                ? () => _updateOrderStatus(order.id, 'reached')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: order.status == 'on_the_way' ? Colors.green.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              elevation: 2,
                            ),
                            child: Text(
                              'Driver Reached',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: order.status == 'reached'
                                ? () => _updateOrderStatus(order.id, 'delivered')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: order.status == 'reached' ? Colors.green.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                              elevation: 2,
                            ),
                            child: Text(
                              'Order Delivered',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'picked_up':
        return 'Order Picked Up';
      case 'on_the_way':
        return 'Driver On the Way';
      case 'reached':
        return 'Driver Reached';
      case 'delivered':
        return 'Order Delivered';
      default:
        return 'Accepted';
    }
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(icon, size: 20.sp, color: Colors.blue.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade800),
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
                                if (locationState.message.contains('permanently denied')) {
                                  print('Opening app settings for location permission');
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
                return Center(
                  child: CircularProgressIndicator(color: Colors.blue.shade700),
                );
              }

              final driverLocation = LatLng(locationState.latitude, locationState.longitude);
              print('Driver location: ${driverLocation.latitude}, ${driverLocation.longitude}');
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

              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
                    child: Text(
                      'Available Deliveries',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('orders')
                          .where('status', isEqualTo: 'pending')
                          .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          print('Pending orders error: ${snapshot.error}');
                          return Center(
                            child: Card(
                              elevation: 12,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                            child: CircularProgressIndicator(color: Colors.blue.shade700),
                          );
                        }

                        final pendingDocs = snapshot.data!.docs;
                        final acceptedSnapshot = FirebaseFirestore.instance
                            .collection('orders')
                            .where('status', whereIn: ['accepted', 'picked_up', 'on_the_way', 'reached', 'delivered'])
                            .where('driverId', isEqualTo: user.uid)
                            .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                            .get();
                        final rejectedSnapshot = FirebaseFirestore.instance
                            .collection('drivers')
                            .doc(user.uid)
                            .collection('rejected_orders')
                            .get();

                        return FutureBuilder<List<dynamic>>(
                          future: Future.wait([acceptedSnapshot, rejectedSnapshot]),
                          builder: (context, combinedSnapshot) {
                            if (combinedSnapshot.hasError) {
                              print('Combined snapshot error: ${combinedSnapshot.error}');
                              return Center(
                                child: Card(
                                  elevation: 12,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                                child: CircularProgressIndicator(color: Colors.blue.shade700),
                              );
                            }

                            final acceptedDocs = combinedSnapshot.data![0] as QuerySnapshot;
                            final rejectedDocs = combinedSnapshot.data![1] as QuerySnapshot;
                            final rejectedOrderIds = rejectedDocs.docs.map((doc) => doc['orderId'] as String).toSet();

                            final driverSnapshot = FirebaseFirestore.instance.collection('drivers').doc(user.uid).get();
                            return FutureBuilder<DocumentSnapshot>(
                              future: driverSnapshot,
                              builder: (context, driverSnapshot) {
                                if (driverSnapshot.hasError) {
                                  print('Driver data error: ${driverSnapshot.error}');
                                  return Center(
                                    child: Card(
                                      elevation: 12,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                                if (!driverSnapshot.hasData || !driverSnapshot.data!.exists) {
                                  return Center(
                                    child: Card(
                                      elevation: 12,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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

                                final driverData = driverSnapshot.data!.data() as Map<String, dynamic>?;
                                final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];

                                final orders = [
                                  ...pendingDocs.map((doc) => order_model.Order.fromSnapshot(doc)),
                                  ...acceptedDocs.docs.map((doc) => order_model.Order.fromSnapshot(doc)),
                                ].where((order) {
                                  if (order.status != 'pending' && order.driverId == user.uid) return true;
                                  if (order.status != 'pending') return false;
                                  if (order.vehicleType == null || order.vehicleType!.isEmpty || !vehicleTypes.contains(order.vehicleType)) return false;
                                  if (order.pickupLat == null || order.pickupLng == null) return false;
                                  final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
                                  final distance = _calculateDistance(driverLocation, pickupLoc);
                                  return distance <= 5.0 && !rejectedOrderIds.contains(order.id);
                                }).toList();

                                final pendingOrders = orders.where((order) => order.status == 'pending').toList();
                                final acceptedOrders = orders.where((order) => order.status != 'pending' && order.driverId == user.uid).toList();
                                final cancelledOrders = orders.where((order) => order.status == 'cancelled' && order.cancelledByUser == true && order.driverId == user.uid).toList();

                                order_model.Order? latestAcceptedOrder;
                                if (acceptedOrders.isNotEmpty) {
                                  acceptedOrders.sort((a, b) => (b.acceptedAt ?? Timestamp.now()).compareTo(a.acceptedAt ?? Timestamp.now()));
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
                                  if (a.status == 'pending' && b.status != 'pending') return -1;
                                  if (a.status != 'pending' && b.status == 'pending') return 1;
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
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}