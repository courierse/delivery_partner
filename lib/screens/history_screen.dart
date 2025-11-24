import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/models/order_model.dart' as order_model;

class DeliveryHistoryScreen extends StatefulWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final CollectionReference _ordersCollection = FirebaseFirestore.instance
      .collection('orders');
  final Set<String> _expandedCards = <String>{};

  Widget _buildHistoryCard(
    order_model.Order order,
    String status, {
    Timestamp? customTime,
    bool? cancelledByUser,
  }) {
    Color statusColor;
    String statusText;
    Timestamp displayTime;

    switch (status) {
      case 'accepted':
        statusColor = Colors.blue.shade700;
        statusText = 'Accepted Delivery';
        displayTime = order.acceptedAt ?? order.createdAt;
        break;
      case 'driver_reached':
        statusColor = Colors.orange.shade700;
        statusText = 'Driver Reached';
        displayTime =
            order.statusUpdatedAt ?? order.acceptedAt ?? order.createdAt;
        break;
      case 'order_picked':
        statusColor = Colors.purple.shade700;
        statusText = 'Order Picked';
        displayTime =
            order.statusUpdatedAt ?? order.acceptedAt ?? order.createdAt;
        break;
      case 'on_the_way':
        statusColor = Colors.indigo.shade700;
        statusText = 'On The Way';
        displayTime =
            order.statusUpdatedAt ?? order.acceptedAt ?? order.createdAt;
        break;
      case 'delivered':
        statusColor = Colors.green.shade700;
        statusText = 'Delivered';
        displayTime =
            order.statusUpdatedAt ?? order.acceptedAt ?? order.createdAt;
        break;
      case 'completed':
        statusColor = Colors.green.shade700;
        statusText = 'Completed Delivery';
        displayTime =
            order.completedAt ??
            order.statusUpdatedAt ??
            order.acceptedAt ??
            order.createdAt;
        break;
      case 'cancelled':
        statusColor = Colors.red.shade600;
        statusText =
            cancelledByUser == true
                ? 'Cancelled by User'
                : 'Cancelled by Driver';
        displayTime = order.cancelledAt ?? order.createdAt;
        break;
      case 'rejected':
        statusColor = Colors.red.shade600;
        statusText = 'Rejected Delivery';
        displayTime = customTime ?? order.createdAt;
        break;
      default:
        statusColor = Colors.grey.shade700;
        statusText = 'Unknown Status';
        displayTime = order.createdAt;
    }

    final cardId = '${order.id}_${displayTime.millisecondsSinceEpoch}';
    final isExpanded = _expandedCards.contains(cardId);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedCards.remove(cardId);
            } else {
              _expandedCards.add(cardId);
            }
          });
        },
        borderRadius: BorderRadius.circular(16.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and expand icon
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: statusColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Spacer(),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade600,
                    size: 24.sp,
                  ),
                ],
              ),
              if (status == 'cancelled') ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: Colors.red.shade200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          cancelledByUser == true
                              ? Icons.person_off_outlined
                              : Icons.cancel_outlined,
                          color: Colors.red.shade700,
                          size: 20.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          cancelledByUser == true
                              ? 'This order was cancelled by the customer.'
                              : 'This order was cancelled by the driver.',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 16.h),

              // Pickup Location
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.blue.shade100, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: Colors.blue.shade700,
                        size: 20.sp,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pickup Location',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            order.pickupLocation,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12.h),

              // Drop-off Location
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.green.shade100, width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.green.shade700,
                        size: 20.sp,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Drop-off Location',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            order.dropLocation,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Expanded details
              if (isExpanded) ...[
                SizedBox(height: 16.h),
                Divider(color: Colors.grey.shade300, height: 1),
                SizedBox(height: 16.h),
                _buildExpandedDetailRow(
                  Icons.person_outline,
                  'Pickup Contact',
                  '${order.pickupName} - ${order.pickupPhone}',
                  Colors.blue.shade700,
                ),
                SizedBox(height: 12.h),
                _buildExpandedDetailRow(
                  Icons.person_outline,
                  'Drop-off Contact',
                  '${order.dropName} - ${order.dropPhone}',
                  Colors.green.shade700,
                ),
                SizedBox(height: 12.h),
                _buildExpandedDetailRow(
                  Icons.directions_car,
                  'Vehicle Type',
                  order.vehicleType ?? 'N/A',
                  Colors.purple.shade700,
                ),
                SizedBox(height: 12.h),
                _buildExpandedDetailRow(
                  Icons.map_outlined,
                  'Distance',
                  '${order.distance.toStringAsFixed(2)} km',
                  Colors.orange.shade700,
                ),
                SizedBox(height: 12.h),
                _buildExpandedDetailRow(
                  Icons.monetization_on_outlined,
                  'Delivery Cost',
                  '₹${order.deliveryCost.toStringAsFixed(2)}',
                  Colors.teal.shade700,
                ),
                SizedBox(height: 12.h),
                _buildExpandedDetailRow(
                  status == 'accepted' ||
                          status == 'rejected' ||
                          status == 'driver_reached' ||
                          status == 'order_picked' ||
                          status == 'on_the_way'
                      ? Icons.schedule
                      : status == 'completed' || status == 'delivered'
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  '${status == 'accepted'
                      ? 'Accepted'
                      : status == 'completed'
                      ? 'Completed'
                      : status == 'delivered'
                      ? 'Delivered'
                      : status == 'driver_reached'
                      ? 'Driver Reached'
                      : status == 'order_picked'
                      ? 'Order Picked'
                      : status == 'on_the_way'
                      ? 'On The Way'
                      : status == 'rejected'
                      ? 'Rejected'
                      : 'Cancelled'} At',
                  displayTime.toDate().toString().substring(0, 16),
                  statusColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetailRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(6.w),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Icon(icon, size: 18.sp, color: iconColor),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
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
                child:
                    user == null
                        ? Center(
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
                          stream:
                              _ordersCollection
                                  .where('driverId', isEqualTo: user.uid)
                                  .where(
                                    'status',
                                    whereIn: [
                                      'accepted',
                                      'driver_reached',
                                      'order_picked',
                                      'on_the_way',
                                      'delivered',
                                      'completed',
                                      'cancelled',
                                    ],
                                  )
                                  .snapshots(),
                          builder: (context, mainSnapshot) {
                            if (mainSnapshot.hasError) {
                              final error = mainSnapshot.error.toString();
                              return Center(
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
                                            backgroundColor:
                                                Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 32.w,
                                              vertical: 12.h,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12.r),
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
                              );
                            }

                            return StreamBuilder<QuerySnapshot>(
                              stream:
                                  FirebaseFirestore.instance
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
                                        borderRadius: BorderRadius.circular(
                                          16.r,
                                        ),
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
                                                backgroundColor:
                                                    Colors.blue.shade700,
                                                foregroundColor: Colors.white,
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 32.w,
                                                  vertical: 12.h,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
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
                                  );
                                }

                                if (!mainSnapshot.hasData &&
                                    !rejectedSnapshot.hasData) {
                                  return Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.blue.shade700,
                                    ),
                                  );
                                }

                                final mainOrders =
                                    mainSnapshot.hasData
                                        ? mainSnapshot.data!.docs
                                            .map((doc) {
                                              try {
                                                return order_model
                                                    .Order.fromSnapshot(doc);
                                              } catch (e) {
                                                print(
                                                  'Error parsing main order ${doc.id}: $e',
                                                );
                                                return null;
                                              }
                                            })
                                            .where((order) => order != null)
                                            .cast<order_model.Order>()
                                            .toList()
                                        : [];

                                final rejectedOrderIds =
                                    rejectedSnapshot.hasData
                                        ? rejectedSnapshot.data!.docs
                                            .map(
                                              (doc) => {
                                                'orderId':
                                                    doc['orderId'] as String,
                                                'rejectedAt':
                                                    doc['rejectedAt']
                                                        as Timestamp,
                                              },
                                            )
                                            .toList()
                                        : [];

                                if (rejectedOrderIds.isEmpty &&
                                    mainOrders.isEmpty) {
                                  return Center(
                                    child: Card(
                                      elevation: 12,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          16.r,
                                        ),
                                      ),
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
                                            await _ordersCollection
                                                .doc(rejected['orderId'])
                                                .get();
                                        if (doc.exists) {
                                          return order_model.Order.fromSnapshot(
                                            doc,
                                          );
                                        }
                                        return null;
                                      } catch (e) {
                                        print(
                                          'Error fetching rejected order ${rejected['orderId']}: $e',
                                        );
                                        return null;
                                      }
                                    }),
                                  ),
                                  builder: (context, futureSnapshot) {
                                    if (!futureSnapshot.hasData) {
                                      return Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.blue.shade700,
                                        ),
                                      );
                                    }

                                    final rejectedOrders =
                                        futureSnapshot.data!
                                            .asMap()
                                            .entries
                                            .where(
                                              (entry) => entry.value != null,
                                            )
                                            .map(
                                              (entry) => {
                                                'order':
                                                    entry.value
                                                        as order_model.Order,
                                                'rejectedAt':
                                                    rejectedOrderIds[entry
                                                            .key]['rejectedAt']
                                                        as Timestamp,
                                              },
                                            )
                                            .toList();

                                    final allEntries = [
                                      ...mainOrders.map(
                                        (order) => {
                                          'order': order,
                                          'status': order.status ?? 'unknown',
                                          'cancelledByUser':
                                              order.cancelledByUser,
                                          'time': _getOrderTimestamp(order),
                                        },
                                      ),
                                      ...rejectedOrders.map(
                                        (entry) => {
                                          'order':
                                              entry['order']
                                                  as order_model.Order,
                                          'status': 'rejected',
                                          'time':
                                              entry['rejectedAt'] as Timestamp,
                                        },
                                      ),
                                    ];

                                    allEntries.sort(
                                      (a, b) => (b['time'] as Timestamp)
                                          .compareTo(a['time'] as Timestamp),
                                    );

                                    return ListView.builder(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 8.h,
                                      ),
                                      itemCount: allEntries.length,
                                      itemBuilder: (context, index) {
                                        final entry = allEntries[index];
                                        final order =
                                            entry['order'] as order_model.Order;
                                        final status =
                                            entry['status'] as String;
                                        final cancelledByUser =
                                            entry['cancelledByUser'] as bool?;
                                        final customTime =
                                            status == 'rejected'
                                                ? entry['time'] as Timestamp
                                                : null;
                                        return _buildHistoryCard(
                                          order,
                                          status,
                                          customTime: customTime,
                                          cancelledByUser: cancelledByUser,
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

  Timestamp _getOrderTimestamp(order_model.Order order) {
    if (order.status == 'completed' && order.completedAt != null) {
      return order.completedAt!;
    } else if (order.status == 'delivered' && order.statusUpdatedAt != null) {
      return order.statusUpdatedAt!;
    } else if (order.status == 'cancelled' && order.cancelledAt != null) {
      return order.cancelledAt!;
    } else if (order.status == 'accepted' && order.acceptedAt != null) {
      return order.acceptedAt!;
    } else if (order.statusUpdatedAt != null) {
      return order.statusUpdatedAt!;
    }
    return order.createdAt;
  }
}
