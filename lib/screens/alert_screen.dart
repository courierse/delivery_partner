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

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance.collection('orders');
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
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
      await _audioPlayer.stop();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = _ordersCollection.doc(orderId);
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception('Order does not exist');
        }
        final data = snapshot.data() as Map<String, dynamic>?;
        print('Order $orderId data: $data');
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
          'driverVehicle': driverData['vehicle'] ?? 'Unknown',
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
      await _audioPlayer.stop();
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
            Text('Vehicle Type: ${order.vehicleType}', style: TextStyle(fontSize: 14.sp)),
            Text('Distance to Pickup: ${distanceToPickup.toStringAsFixed(2)} km', style: TextStyle(fontSize: 14.sp)),
            Text('Total Distance: ${order.distance.toStringAsFixed(2)} km', style: TextStyle(fontSize: 14.sp)),
            Text('Delivery Cost: \₹${order.deliveryCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 14.sp)),
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
        print('Driver location: ${driverLocation.latitude}, ${driverLocation.longitude}');
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
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('drivers').doc(user.uid).snapshots(),
                builder: (context, driverSnapshot) {
                  if (driverSnapshot.hasError) {
                    print('Driver data error: ${driverSnapshot.error}');
                    return Center(
                      child: Text(
                        'Error loading driver data',
                        style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                      ),
                    );
                  }
                  if (!driverSnapshot.hasData || !driverSnapshot.data!.exists) {
                    return Center(
                      child: Text(
                        'Driver profile not found',
                        style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                      ),
                    );
                  }

                  final driverData = driverSnapshot.data!.data() as Map<String, dynamic>?;
                  final vehicleTypes = (driverData?['vehicleTypes'] as String?)?.split(', ')?.toList() ?? [];
                  print('Driver vehicleTypes: $vehicleTypes');

                  return StreamBuilder<List<QuerySnapshot>>(
                    stream: Stream.fromFuture(Future.wait([
                      _ordersCollection
                          .where('status', isEqualTo: 'pending')
                          .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                          .get(),
                      _ordersCollection
                          .where('status', isEqualTo: 'accepted')
                          .where('driverId', isEqualTo: user.uid)
                          .where('createdAt', isGreaterThanOrEqualTo: recentThreshold)
                          .get(),
                    ])),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        final error = snapshot.error.toString();
                        print('Firestore error: $error');
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
                                onPressed: () => setState(() {}),
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

                      final pendingDocs = snapshot.data![0].docs;
                      final acceptedDocs = snapshot.data![1].docs;
                      final docs = [...pendingDocs, ...acceptedDocs];
                      print('Fetched ${docs.length} orders (pending: ${pendingDocs.length}, accepted: ${acceptedDocs.length})');
                      for (var doc in docs) {
                        print('Order ${doc.id}: ${doc.data()}');
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('drivers')
                            .doc(user.uid)
                            .collection('rejected_orders')
                            .snapshots(),
                        builder: (context, rejectedSnapshot) {
                          if (rejectedSnapshot.hasError) {
                            print('Rejected orders error: ${rejectedSnapshot.error}');
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
                                if (order.status == 'accepted' && order.driverId == user.uid) {
                                  return true; // Always include accepted orders by this driver
                                }
                                if (order.status != 'pending') {
                                  return false; // Exclude non-pending orders not accepted by this driver
                                }
                                if (order.vehicleType == null || order.vehicleType!.isEmpty) {
                                  print('Order ${order.id} has no vehicleType');
                                  return false;
                                }
                                if (!vehicleTypes.contains(order.vehicleType)) {
                                  print('Order ${order.id} vehicleType ${order.vehicleType} not in driver vehicleTypes $vehicleTypes');
                                  return false;
                                }
                                if (order.pickupLat == null || order.pickupLng == null) {
                                  print('Invalid coordinates for order ${order.id}: pickupLat=${order.pickupLat}, pickupLng=${order.pickupLng}');
                                  return false;
                                }
                                final pickupLoc = LatLng(order.pickupLat!, order.pickupLng!);
                                final distance = _calculateDistance(driverLocation, pickupLoc);
                                print('Order ${order.id} distance: $distance km, vehicleType: ${order.vehicleType}');
                                return distance <= 5.0;
                              })
                              .toList();

                          final pendingOrders = orders.where((order) => order.status == 'pending').toList();
                          final acceptedOrders = orders
                              .where((order) => order.status == 'accepted' && order.driverId == user.uid)
                              .toList();

                          if (pendingOrders.isNotEmpty) {
                            _audioPlayer.play(AssetSource('sounds/alert.mp3'));
                          } else {
                            _audioPlayer.stop();
                          }

                          order_model.Order? latestAcceptedOrder;
                          if (acceptedOrders.isNotEmpty) {
                            acceptedOrders.sort((a, b) => (b.acceptedAt ?? Timestamp.now())
                                .compareTo(a.acceptedAt ?? Timestamp.now()));
                            latestAcceptedOrder = acceptedOrders.first;
                          }

                          final finalOrders = [
                            ...pendingOrders,
                            if (latestAcceptedOrder != null) latestAcceptedOrder,
                          ];

                          print('Filtered orders count: ${finalOrders.length}');
                          if (finalOrders.isEmpty) {
                            _audioPlayer.stop();
                            return Center(
                              child: Text(
                                'No matching delivery requests within 5km.',
                                style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                              ),
                            );
                          }

                          finalOrders.sort((a, b) {
                            if (a.status == 'pending' && b.status != 'pending') {
                              return -1;
                            } else if (a.status != 'pending' && b.status == 'pending') {
                              return 1;
                            }
                            return 0;
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