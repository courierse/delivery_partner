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
  final CollectionReference _ordersCollection =
      FirebaseFirestore.instance.collection('orders');

  Widget _buildHistoryCard(order_model.Order order, String status,
      {Timestamp? customTime, bool? cancelledByUser}) {
    Color statusColor;
    String statusText;
    Timestamp displayTime;

    switch (status) {
      case 'accepted':
        statusColor = Colors.green.shade700;
        statusText = 'Accepted Delivery';
        displayTime = order.acceptedAt ?? order.createdAt ?? Timestamp.now();
        break;
      case 'completed':
        statusColor = Colors.green.shade700;
        statusText = 'Completed Delivery';
        displayTime = order.completedAt ?? order.acceptedAt ?? order.createdAt ?? Timestamp.now();
        break;
      case 'cancelled':
        statusColor = Colors.red.shade600;
        statusText =
            cancelledByUser == true ? 'Cancelled by User' : 'Cancelled by Driver';
        displayTime = order.cancelledAt ?? order.createdAt ?? Timestamp.now();
        break;
      case 'rejected':
        statusColor = Colors.red.shade600;
        statusText = 'Rejected Delivery';
        displayTime = customTime ?? order.createdAt ?? Timestamp.now();
        break;
      default:
        statusColor = Colors.grey.shade700;
        statusText = 'Unknown Status';
        displayTime = order.createdAt ?? Timestamp.now();
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
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            _buildInfoRow(Icons.location_on, 'Pickup: ${order.pickupLocation}'),
            _buildInfoRow(
                Icons.person, 'Contact: ${order.pickupName} - ${order.pickupPhone}'),
            _buildInfoRow(Icons.local_shipping, 'Drop-off: ${order.dropLocation}'),
            _buildInfoRow(
                Icons.person, 'Contact: ${order.dropName} - ${order.dropPhone}'),
            _buildInfoRow(Icons.directions_car, 'Vehicle: ${order.vehicleType}'),
            _buildInfoRow(
                Icons.map, 'Total Distance: ${order.distance.toStringAsFixed(2)} km'),
            _buildInfoRow(
                Icons.monetization_on, 'Cost: ₹${order.deliveryCost.toStringAsFixed(2)}'),
            _buildInfoRow(
              status == 'accepted' || status == 'rejected'
                  ? Icons.schedule
                  : status == 'completed'
                      ? Icons.check_circle
                      : Icons.cancel,
              '${status == 'accepted' ? 'Accepted' : status == 'completed' ? 'Completed' : status == 'rejected' ? 'Rejected' : 'Cancelled'} At: ${displayTime.toDate().toString().substring(0, 16)}',
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
                          shape:
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                            .where('status', whereIn: ['accepted', 'completed', 'cancelled'])
                            .snapshots(),
                        builder: (context, mainSnapshot) {
                          if (mainSnapshot.hasError) {
                            final error = mainSnapshot.error.toString();
                            return Center(
                              child: Card(
                                elevation: 12,
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
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
                                        'Error loading orders: $error',
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
                                          padding:
                                              EdgeInsets.symmetric(horizontal: 32.w, vertical: 12.h),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12.r)),
                                          elevation: 2,
                                        ),
                                        child: Text(
                                          'Retry',
                                          style:
                                              TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
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
                                );
                              }

                              if (!mainSnapshot.hasData && !rejectedSnapshot.hasData) {
                                return Center(
                                  child: CircularProgressIndicator(color: Colors.blue.shade700),
                                );
                              }

                              final mainOrders = mainSnapshot.hasData
                                  ? mainSnapshot.data!.docs
                                      .map((doc) {
                                        try {
                                          return order_model.Order.fromSnapshot(doc);
                                        } catch (e) {
                                          print('Error parsing main order ${doc.id}: $e');
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

                              if (rejectedOrderIds.isEmpty && mainOrders.isEmpty) {
                                return Center(
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

                              return FutureBuilder<List<order_model.Order?>>(
                                future: Future.wait(
                                  rejectedOrderIds.map((rejected) async {
                                    try {
                                      final doc =
                                          await _ordersCollection.doc(rejected['orderId']).get();
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
                                            'rejectedAt': rejectedOrderIds[entry.key]['rejectedAt']
                                                as Timestamp,
                                          })
                                      .toList();

                                  final allEntries = [
                                    ...mainOrders.map((order) => {
                                          'order': order,
                                          'status': order.status ?? 'unknown',
                                          'cancelledByUser': order.cancelledByUser,
                                          'time': _getOrderTimestamp(order),
                                        }),
                                    ...rejectedOrders.map((entry) => {
                                          'order': entry['order'] as order_model.Order,
                                          'status': 'rejected',
                                          'time': entry['rejectedAt'] as Timestamp,
                                        }),
                                  ];

                                  allEntries.sort((a, b) =>
                                      (b['time'] as Timestamp).compareTo(a['time'] as Timestamp));

                                  return ListView.builder(
                                    padding: EdgeInsets.symmetric(vertical: 8.h),
                                    itemCount: allEntries.length,
                                    itemBuilder: (context, index) {
                                      final entry = allEntries[index];
                                      final order = entry['order'] as order_model.Order;
                                      final status = entry['status'] as String;
                                      final cancelledByUser = entry['cancelledByUser'] as bool?;
                                      final customTime =
                                          status == 'rejected' ? entry['time'] as Timestamp : null;
                                      return _buildHistoryCard(order, status,
                                          customTime: customTime, cancelledByUser: cancelledByUser);
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

  Timestamp _getOrderTimestamp(order_model.Order order) {
    if (order.status == 'completed' && order.completedAt != null) {
      return order.completedAt!;
    } else if (order.status == 'cancelled' && order.cancelledAt != null) {
      return order.cancelledAt!;
    } else if (order.status == 'accepted' && order.acceptedAt != null) {
      return order.acceptedAt!;
    }
    return order.createdAt ?? Timestamp.now();
  }
}