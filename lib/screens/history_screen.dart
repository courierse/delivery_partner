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
                  isAccepted ? 'Accepted Delivery' : 'Rejected Delivery',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: isAccepted ? Colors.green.shade700 : Colors.red.shade600,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: isAccepted ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    isAccepted ? 'Accepted' : 'Rejected',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: isAccepted ? Colors.green.shade700 : Colors.red.shade600,
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
            // _buildInfoRow(Icons.scale, 'Weight: ${order.weightRange}'),
            _buildInfoRow(Icons.directions_car, 'Vehicle: ${order.vehicleType}'),
            _buildInfoRow(Icons.map, 'Total Distance: ${order.distance.toStringAsFixed(2)} km'),
            _buildInfoRow(Icons.monetization_on, 'Cost: ₹${order.deliveryCost.toStringAsFixed(2)}'),
            if (isAccepted && order.acceptedAt != null)
              _buildInfoRow(
                Icons.check_circle,
                'Accepted At: ${order.acceptedAt!.toDate().toString().substring(0, 16)}',
              ),
            if (!isAccepted && rejectedAt != null)
              _buildInfoRow(
                Icons.cancel,
                'Rejected At: ${rejectedAt.toDate().toString().substring(0, 16)}',
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
                child: Text(
                  'Delivery History',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: user == null
                    ? Center(
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
                                  'Please log in to view delivery history',
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
                      )
                    : StreamBuilder<QuerySnapshot>(
                        stream: _ordersCollection
                            .where('driverId', isEqualTo: user.uid)
                            .where('status', isEqualTo: 'accepted')
                            .snapshots(),
                        builder: (context, acceptedSnapshot) {
                          if (acceptedSnapshot.hasError) {
                            final error = acceptedSnapshot.error.toString();
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
                                        'Error loading accepted orders: $error',
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
                                          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                          elevation: 2,
                                        ),
                                        child: Text(
                                          'Retry',
                                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                                            'Error loading rejected orders: ${rejectedSnapshot.error}',
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
                                              padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                              elevation: 2,
                                            ),
                                            child: Text(
                                              'Retry',
                                              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }

                              if (!acceptedSnapshot.hasData && !rejectedSnapshot.hasData) {
                                return Center(
                                  child: CircularProgressIndicator(color: Colors.blue.shade700),
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

                              if (rejectedOrderIds.isEmpty) {
                                if (acceptedOrders.isEmpty) {
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
                                              'No delivery history available.',
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
                                return ListView.builder(
                                  padding: EdgeInsets.symmetric(vertical: 8.h),
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
                                      child: CircularProgressIndicator(color: Colors.blue.shade700),
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
                                                'No delivery history available.',
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
                                    padding: EdgeInsets.symmetric(vertical: 8.h),
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
          ),
        ),
      ),
    );
  }
}