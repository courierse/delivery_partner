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
  final Set<String> _dismissedOrders = {};

  Widget _buildHistoryCard(order_model.Order order) {
    final isAccepted = order.status == 'accepted' && order.driverId == FirebaseAuth.instance.currentUser?.uid;
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
            Text('Delivery Cost: \$${order.deliveryCost.toStringAsFixed(2)}', style: TextStyle(fontSize: 14.sp)),
            if (order.acceptedAt != null && isAccepted)
              Text(
                'Accepted At: ${order.acceptedAt!.toDate().toString().substring(0, 16)}',
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
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error.toString();
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error loading history: $error',
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

              final docs = snapshot.data!.docs;
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
                  .toList();

              // Include dismissed orders (rejected)
              final rejectedOrders = _dismissedOrders
                  .map((orderId) => _ordersCollection.doc(orderId).get())
                  .toList();
              if (rejectedOrders.isNotEmpty) {
                return FutureBuilder<List<DocumentSnapshot>>(
                  future: Future.wait(rejectedOrders),
                  builder: (context, futureSnapshot) {
                    if (!futureSnapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: AppColors.buttonColour),
                      );
                    }
                    final allOrders = [
                      ...orders,
                      ...futureSnapshot.data!
                          .map((doc) => order_model.Order.fromSnapshot(doc))
                          .where((order) => order != null)
                    ];

                    if (allOrders.isEmpty) {
                      return Center(
                        child: Text(
                          'No delivery history available.',
                          style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: allOrders.length,
                      itemBuilder: (context, index) {
                        final order = allOrders[index];
                        return _buildHistoryCard(order);
                      },
                    );
                  },
                );
              }

              if (orders.isEmpty) {
                return Center(
                  child: Text(
                    'No delivery history available.',
                    style: TextStyle(fontSize: 16.sp, color: AppColors.textColor),
                  ),
                );
              }

              return ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return _buildHistoryCard(order);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}