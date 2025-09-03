import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/constants/colors.dart';
import 'package:phone_authentication/models/order_model.dart' as order_model;

class DeliveryHistoryScreen extends StatefulWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance.collection('orders');

  Widget _buildHistoryCard(order_model.Order order, bool isAccepted, {Timestamp? rejectedAt}) {
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
              isAccepted ? 'Accepted Delivery' : 'Rejected Delivery',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: isAccepted ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(height: 8.h),
            Text('Pickup: ${order.pickupLocation}', style: TextStyle(fontSize: 14.sp)),
            Text('Pickup Contact: ${order.pickupName} - ${order.pickupPhone}', style: TextStyle(fontSize: 14.sp)),
            Text('Drop-off: ${order.dropLocation}', style: TextStyle(fontSize: 14.sp)),
            Text('Drop-off Contact: ${order.dropName} - ${order.dropPhone}', style: TextStyle(fontSize: 14.sp)),
            Text('Weight: ${order.weightRange}', style: TextStyle(fontSize: 14.sp)),
            Text('Total Distance: ${order.distance.toStringAsFixed(2)} km', style: TextStyle(fontSize: 14.sp)),
            Text('Delivery Cost: \₹${order.deliveryCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 14.sp)),
            if (isAccepted && order.acceptedAt != null)
              Text(
                'Accepted At: ${order.acceptedAt!.toDate().toString().substring(0, 16)}',
                style: TextStyle(fontSize: 14.sp, color: AppColors.textColor),
              ),
            if (!isAccepted && rejectedAt != null)
              Text(
                'Rejected At: ${rejectedAt.toDate().toString().substring(0, 16)}',
                style: TextStyle(fontSize: 14.sp, color: AppColors.textColor),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text(
          'Please log in to view delivery history',
          style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Text(
            'Delivery History',
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
                .where('driverId', isEqualTo: user.uid)
                .where('status', isEqualTo: 'accepted')
                .snapshots(),
            builder: (context, acceptedSnapshot) {
              if (acceptedSnapshot.hasError) {
                final error = acceptedSnapshot.error.toString();
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error loading accepted orders: $error',
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

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(user.uid)
                    .collection('rejected_orders')
                    .snapshots(),
                builder: (context, rejectedSnapshot) {
                  if (rejectedSnapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Error loading rejected orders: ${rejectedSnapshot.error}',
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

                  if (!acceptedSnapshot.hasData && !rejectedSnapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: AppColors.buttonColour),
                    );
                  }

                  final acceptedOrders = acceptedSnapshot.hasData
                      ? acceptedSnapshot.data!.docs
                          .map((doc) {
                            try {
                              return order_model.Order.fromSnapshot(doc);
                            } catch (e) {
                              print('Error parsing accepted order ${doc.id}: $e');
                              return null;
                            }
                          })
                          .where((order) => order != null)
                          .cast<order_model.Order>()
                          .toList()
                      : [];

                  final rejectedOrderIds = rejectedSnapshot.hasData
                      ? rejectedSnapshot.data!.docs
                          .map((doc) => {
                                'orderId': doc['orderId'] as String,
                                'rejectedAt': doc['rejectedAt'] as Timestamp,
                              })
                          .toList()
                      : [];

                  // Fetch details of rejected orders
                  if (rejectedOrderIds.isEmpty) {
                    if (acceptedOrders.isEmpty) {
                      return Center(
                        child: Text(
                          'No delivery history available.',
                          style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: acceptedOrders.length,
                      itemBuilder: (context, index) {
                        final order = acceptedOrders[index];
                        return _buildHistoryCard(order, true);
                      },
                    );
                  }

                  return FutureBuilder<List<order_model.Order?>>(
                    future: Future.wait(
                      rejectedOrderIds.map((rejected) async {
                        try {
                          final doc = await _ordersCollection.doc(rejected['orderId']).get();
                          if (doc.exists) {
                            return order_model.Order.fromSnapshot(doc);
                          }
                          return null;
                        } catch (e) {
                          print('Error fetching rejected order ${rejected['orderId']}: $e');
                          return null;
                        }
                      }),
                    ),
                    builder: (context, futureSnapshot) {
                      if (!futureSnapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(color: AppColors.buttonColour),
                        );
                      }

                      final rejectedOrders = futureSnapshot.data!
                          .asMap()
                          .entries
                          .where((entry) => entry.value != null)
                          .map((entry) => {
                                'order': entry.value as order_model.Order,
                                'rejectedAt': rejectedOrderIds[entry.key]['rejectedAt'] as Timestamp,
                              })
                          .toList();

                      final allOrders = [
                        ...acceptedOrders.map((order) => {'order': order, 'isAccepted': true}),
                        ...rejectedOrders.map((entry) => {
                              'order': entry['order'] as order_model.Order,
                              'isAccepted': false,
                              'rejectedAt': entry['rejectedAt'] as Timestamp,
                            }),
                      ];

                      if (allOrders.isEmpty) {
                        return Center(
                          child: Text(
                            'No delivery history available.',
                            style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                          ),
                        );
                      }

                      allOrders.sort((a, b) {
                        final aTime = a['isAccepted']
                            ? (a['order'] as order_model.Order).acceptedAt ?? Timestamp.now()
                            : a['rejectedAt'] as Timestamp;
                        final bTime = b['isAccepted']
                            ? (b['order'] as order_model.Order).acceptedAt ?? Timestamp.now()
                            : b['rejectedAt'] as Timestamp;
                        return bTime.compareTo(aTime); // Sort by most recent
                      });

                      return ListView.builder(
                        itemCount: allOrders.length,
                        itemBuilder: (context, index) {
                          final entry = allOrders[index];
                          final order = entry['order'] as order_model.Order;
                          final isAccepted = entry['isAccepted'] as bool;
                          final rejectedAt = entry['rejectedAt'] as Timestamp?;
                          return _buildHistoryCard(order, isAccepted, rejectedAt: rejectedAt);
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
  }
}