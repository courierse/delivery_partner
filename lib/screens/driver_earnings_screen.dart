import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/constants/colors.dart';
import 'package:phone_authentication/models/order_model.dart' as order_model;

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  final CollectionReference _ordersCollection =
      FirebaseFirestore.instance.collection('orders');

  double _calculateEarnings(double deliveryCost) {
    return deliveryCost * 0.8; // 80% of delivery cost
  }

  Widget _buildEarningCard(order_model.Order order) {
    final earnings = _calculateEarnings(order.deliveryCost);
    final completedDate = order.completedAt?.toDate() ?? order.createdAt.toDate();

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
                Expanded(
                  child: Text(
                    'Completed Delivery',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '₹${earnings.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            _buildInfoRow(Icons.location_on, 'Pickup: ${order.pickupLocation}'),
            _buildInfoRow(Icons.local_shipping, 'Drop-off: ${order.dropLocation}'),
            _buildInfoRow(
                Icons.map, 'Distance: ${order.distance.toStringAsFixed(2)} km'),
            _buildInfoRow(
                Icons.monetization_on,
                'Delivery Cost: ₹${order.deliveryCost.toStringAsFixed(2)}'),
            _buildInfoRow(
                Icons.account_balance_wallet,
                'Your Earnings (80%): ₹${earnings.toStringAsFixed(2)}'),
            _buildInfoRow(
              Icons.check_circle,
              'Completed: ${completedDate.toString().substring(0, 16)}',
            ),
          ],
        ),
      ),
    );
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
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Driver Earnings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.buttonTextColor,
            fontSize: 20.sp,
          ),
        ),
        backgroundColor: AppColors.buttonColour,
        elevation: 0,
      ),
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
              if (user != null)
                StreamBuilder<QuerySnapshot>(
                  stream: _ordersCollection
                      .where('driverId', isEqualTo: user.uid)
                      .where('status', isEqualTo: 'delivered')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final error = snapshot.error.toString();
                      return Expanded(
                        child: Center(
                          child: Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r)),
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
                                    'Error loading earnings: $error',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 16.h),
                                  ElevatedButton(
                                    onPressed: () => setState(() {}),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 32.w, vertical: 12.h),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r)),
                                      elevation: 2,
                                    ),
                                    child: Text(
                                      'Retry',
                                      style: TextStyle(
                                          fontSize: 16.sp, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Expanded(
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.blue.shade700),
                        ),
                      );
                    }

                    final orders = snapshot.data!.docs
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
                        .toList()
                      ..sort((a, b) {
                        final aTime = a.completedAt ?? a.createdAt;
                        final bTime = b.completedAt ?? b.createdAt;
                        return bTime.compareTo(aTime);
                      });

                    double totalEarnings = 0.0;
                    for (var order in orders) {
                      totalEarnings += _calculateEarnings(order.deliveryCost);
                    }

                    if (orders.isEmpty) {
                      return Expanded(
                        child: Center(
                          child: Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r)),
                            child: Padding(
                              padding: EdgeInsets.all(24.w),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    size: 48.sp,
                                    color: Colors.blue.shade700,
                                  ),
                                  SizedBox(height: 16.h),
                                  Text(
                                    'No earnings yet.\nComplete deliveries to see your earnings here.',
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

                    return Expanded(
                      child: Column(
                        children: [
                          // Total Earnings Summary Card
                          Container(
                            margin: EdgeInsets.all(16.w),
                            padding: EdgeInsets.all(20.w),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Total Earnings',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  '₹${totalEarnings.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 32.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  'From ${orders.length} ${orders.length == 1 ? 'delivery' : 'deliveries'}',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Earnings List
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.symmetric(vertical: 8.h),
                              itemCount: orders.length,
                              itemBuilder: (context, index) {
                                return _buildEarningCard(orders[index]);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else
                Expanded(
                  child: Center(
                    child: Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r)),
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
                              'Please log in to view earnings',
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

