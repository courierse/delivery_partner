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
  final CollectionReference _ordersCollection = FirebaseFirestore.instance
      .collection('orders');
  final Map<String, bool> _expandedCards = {};

  double _calculateEarnings(double deliveryCost) {
    return deliveryCost * 0.8; // 80% of delivery cost
  }

  void _toggleCardExpansion(String orderId) {
    setState(() {
      _expandedCards[orderId] = !(_expandedCards[orderId] ?? false);
    });
  }

  Widget _buildEarningCard(order_model.Order order) {
    final earnings = _calculateEarnings(order.deliveryCost);
    final completedDate =
        order.completedAt?.toDate() ?? order.createdAt.toDate();
    final isExpanded = _expandedCards[order.id] ?? false;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Earnings
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.shade50,
                      Colors.green.shade100.withOpacity(0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Earnings',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            '₹${earnings.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _toggleCardExpansion(order.id),
                      borderRadius: BorderRadius.circular(20.r),
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        child: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey.shade700,
                          size: 24.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Pickup and Drop-off Locations
              Padding(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pickup Location
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.blue.shade700,
                            size: 18.sp,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pickup',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                order.pickupLocation,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade900,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 10.h),

                    // Divider with arrow
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6.w),
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6.w),
                            child: Icon(
                              Icons.arrow_downward,
                              color: Colors.grey.shade400,
                              size: 16.sp,
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 10.h),

                    // Drop-off Location
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: Colors.red.shade700,
                            size: 18.sp,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Drop-off',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                order.dropLocation,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade900,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Expandable Details Section
              if (isExpanded)
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        Icons.map,
                        'Distance',
                        '${order.distance.toStringAsFixed(2)} km',
                        Colors.orange.shade700,
                      ),
                      SizedBox(height: 8.h),
                      _buildDetailRow(
                        Icons.monetization_on,
                        'Delivery Cost',
                        '₹${order.deliveryCost.toStringAsFixed(2)}',
                        Colors.purple.shade700,
                      ),
                      SizedBox(height: 8.h),
                      _buildDetailRow(
                        Icons.account_balance_wallet,
                        'Your Earnings (80%)',
                        '₹${earnings.toStringAsFixed(2)}',
                        Colors.green.shade700,
                      ),
                      SizedBox(height: 8.h),
                      _buildDetailRow(
                        Icons.check_circle,
                        'Completed',
                        completedDate.toString().substring(0, 16),
                        Colors.blue.shade700,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(5.w),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Icon(icon, size: 16.sp, color: iconColor),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
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
                  stream:
                      _ordersCollection
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
                                      'Retry',
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
                    }

                    if (!snapshot.hasData) {
                      return Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue.shade700,
                          ),
                        ),
                      );
                    }

                    final orders =
                        snapshot.data!.docs
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
                              borderRadius: BorderRadius.circular(16.r),
                            ),
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
                            margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade600,
                                  Colors.green.shade700,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.shade700.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.w,
                                vertical: 14.h,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet,
                                        color: Colors.white,
                                        size: 22.sp,
                                      ),
                                      SizedBox(width: 8.w),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Total Earnings',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: Colors.white.withOpacity(
                                                0.9,
                                              ),
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          SizedBox(height: 4.h),
                                          Text(
                                            '₹${totalEarnings.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 24.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12.w,
                                      vertical: 6.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Text(
                                      '${orders.length} ${orders.length == 1 ? 'delivery' : 'deliveries'}',
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
