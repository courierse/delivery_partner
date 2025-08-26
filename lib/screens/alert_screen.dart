import 'dart:math';
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

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance.collection('orders');

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
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Order does not exist');
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        print('Order $orderId data: $data'); // Debug log
        if (data == null) {
          throw Exception('Order data is null');
        }
        if (data['status'] != 'pending') {
          throw Exception('Order is not pending');
        }
        transaction.update(docRef, {
          'status': 'accepted',
          'driverId': user.uid,
          'acceptedAt': FieldValue.serverTimestamp(),
        });

        // Update driver location in Firestore
        final driverRef = FirebaseFirestore.instance.collection('drivers').doc(user.uid);
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
      // Store rejected order in driver's rejected_orders subcollection
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject order: $e')),
      );
    }
  }

  Widget _buildOrderCard(order_model.Order order, bool isPending, LatLng driverLocation) {
    final distanceToPickup = _calculateDistance(
      driverLocation,
      LatLng(order.pickupLat ?? 0.0, order.pickupLng ?? 0.0),
    );
    return Card(
      margin: EdgeInsets.all(8.w),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      elevation: 4,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPending ? 'Delivery Request' : 'Accepted Delivery',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: isPending ? AppColors.textColor : Colors.green,
              ),
            ),
            SizedBox(height: 8.h),
            Text('Pickup: ${order.pickupLocation}', style: TextStyle(fontSize: 14.sp)),
            Text('Pickup Contact: ${order.pickupName} - ${order.pickupPhone}', style: TextStyle(fontSize: 14.sp)),
            Text('Drop-off: ${order.dropLocation}', style: TextStyle(fontSize: 14.sp)),
            Text('Drop-off Contact: ${order.dropName} - ${order.dropPhone}', style: TextStyle(fontSize: 14.sp)),
            Text('Weight: ${order.weightRange}', style: TextStyle(fontSize: 14.sp)),
            Text('Distance to Pickup: ${distanceToPickup.toStringAsFixed(2)} km', style: TextStyle(fontSize: 14.sp)),
            Text('Total Distance: ${order.distance.toStringAsFixed(2)} km', style: TextStyle(fontSize: 14.sp)),
            Text('Delivery Cost: \$${order.deliveryCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 14.sp)),
            SizedBox(height: 16.h),
            if (isPending)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _acceptOrder(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonColour,
                      foregroundColor: AppColors.buttonTextColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    ),
                    child: Text('Accept', style: TextStyle(fontSize: 14.sp)),
                  ),
                  ElevatedButton(
                    onPressed: () => _rejectOrder(order.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.grey,
                      foregroundColor: AppColors.textColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                    ),
                    child: Text('Reject', style: TextStyle(fontSize: 14.sp)),
                  ),
                ],
              )
            else
              Text(
                'You have accepted this delivery.',
                style: TextStyle(fontSize: 14.sp, color: Colors.green),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocationCubit, LocationState>(
      builder: (context, locationState) {
        if (locationState is LocationError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Location Error: ${locationState.message}',
                  style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
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
                    backgroundColor: AppColors.buttonColour,
                    foregroundColor: AppColors.buttonTextColor,
                  ),
                  child: Text(
                    locationState.message.contains('permanently denied')
                        ? 'Open Settings'
                        : 'Retry',
                    style: TextStyle(fontSize: 14.sp),
                  ),
                ),
              ],
            ),
          );
        } else if (locationState is! CurrentLocationUpdated) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.buttonColour),
          );
        }

        final driverLocation = LatLng(locationState.latitude, locationState.longitude);
        print('Driver location: ${driverLocation.latitude}, ${driverLocation.longitude}'); // Debug log
        final recentThreshold = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1)));
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) {
          return Center(
            child: Text(
              'Please log in to view deliveries',
              style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text(
                'Available Deliveries',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textColor,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _ordersCollection
                    .where('status', whereIn: ['pending', 'accepted'])
                    .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error.toString();
                    print('Firestore error: $error'); // Debug log
                    String errorMessage = 'Error loading orders: $error';
                    if (error.contains('requires an index')) {
                      errorMessage = 'Error: Firestore query requires an index. Check the console for a link to create it.';
                    }
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            errorMessage,
                            style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16.h),
                          ElevatedButton(
                            onPressed: () => setState(() {}), // Refresh UI
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.buttonColour,
                              foregroundColor: AppColors.buttonTextColor,
                            ),
                            child: Text('Retry', style: TextStyle(fontSize: 14.sp)),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: AppColors.buttonColour),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  print('Fetched ${docs.length} orders'); // Debug log
                  for (var doc in docs) {
                    print('Order ${doc.id}: ${doc.data()}'); // Debug log
                  }

                  // Fetch rejected orders for the current driver
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('drivers')
                        .doc(user.uid)
                        .collection('rejected_orders')
                        .snapshots(),
                    builder: (context, rejectedSnapshot) {
                      if (rejectedSnapshot.hasError) {
                        print('Rejected orders error: ${rejectedSnapshot.error}'); // Debug log
                        return Center(
                          child: Text(
                            'Error loading rejected orders',
                            style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                          ),
                        );
                      }
                      if (!rejectedSnapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(color: AppColors.buttonColour),
                        );
                      }

                      final rejectedOrderIds = rejectedSnapshot.data!.docs
                          .map((doc) => doc['orderId'] as String)
                          .toSet();

                      // Filter orders: include pending orders and the most recent accepted order by this driver
                      final orders = docs
                          .map((doc) {
                            try {
                              return order_model.Order.fromSnapshot(doc);
                            } catch (e) {
                              print('Error parsing order ${doc.id}: $e');
                              return null;
                            }
                          })
                          .where((order) => order != null)
                          .cast<order_model.Order>()
                          .where((order) => !rejectedOrderIds.contains(order.id))
                          .where((order) {
                            if (order.status == 'accepted' && order.driverId != user.uid) {
                              return false; // Exclude orders accepted by other drivers
                            }
                            if (order.pickupLat == null || order.pickupLng == null) {
                              print('Invalid coordinates for order ${order.id}: pickupLat=${order.pickupLat}, pickupLng=${order.pickupLng}'); // Debug log
                              return false;
                            }
                            final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
                            final distance = _calculateDistance(driverLocation, pickupLoc);
                            print('Order ${order.id} distance: $distance km, pickupLoc=${pickupLoc.latitude},${pickupLoc.longitude}'); // Debug log
                            return distance <= 5.0;
                          })
                          .toList();

                      // Separate pending and accepted orders
                      final pendingOrders = orders.where((order) => order.status == 'pending').toList();
                      final acceptedOrders = orders
                          .where((order) => order.status == 'accepted' && order.driverId == user.uid)
                          .toList();

                      // Select only the most recent accepted order (if any)
                      order_model.Order? latestAcceptedOrder;
                      if (acceptedOrders.isNotEmpty) {
                        acceptedOrders.sort((a, b) => (b.acceptedAt ?? Timestamp.now())
                            .compareTo(a.acceptedAt ?? Timestamp.now()));
                        latestAcceptedOrder = acceptedOrders.first;
                      }

                      // Combine pending orders with the latest accepted order (if exists)
                      final finalOrders = [
                        ...pendingOrders,
                        if (latestAcceptedOrder != null) latestAcceptedOrder,
                      ];

                      print('Filtered orders count: ${finalOrders.length}'); // Debug log
                      if (finalOrders.isEmpty) {
                        return Center(
                          child: Text(
                            'No delivery requests within 5km.',
                            style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                          ),
                        );
                      }

                      // Sort to ensure pending orders are at the top
                      finalOrders.sort((a, b) {
                        if (a.status == 'pending' && b.status != 'pending') {
                          return -1; // Pending orders come first
                        } else if (a.status != 'pending' && b.status == 'pending') {
                          return 1;
                        }
                        return 0; // Maintain order for same status
                      });

                      return ListView.builder(
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
              ),
            ),
          ],
        );
      },
    );
  }
}