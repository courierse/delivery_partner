import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/constants/colors.dart';
import 'package:phone_authentication/models/notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final CollectionReference _notificationsCollection =
      FirebaseFirestore.instance.collection('driver_notifications');

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _notificationsCollection.doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead(String driverId) async {
    try {
      final snapshot = await _notificationsCollection
          .where('driverId', isEqualTo: driverId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  Widget _buildNotificationCard(DeliveryNotification notification) {
    final isUnread = !notification.isRead;
    final dateTime = notification.createdAt.toDate();

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      elevation: isUnread ? 8 : 4,
      shadowColor: isUnread
          ? AppColors.buttonColour.withOpacity(0.3)
          : Colors.black.withOpacity(0.1),
      color: isUnread ? Colors.blue.shade50 : Colors.white,
      child: InkWell(
        onTap: () {
          if (isUnread) {
            _markAsRead(notification.id);
          }
        },
        borderRadius: BorderRadius.circular(16.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.buttonColour.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(
                      Icons.local_shipping,
                      color: AppColors.buttonColour,
                      size: 24.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                            if (isUnread)
                              Container(
                                width: 10.w,
                                height: 10.h,
                                decoration: BoxDecoration(
                                  color: AppColors.buttonColour,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          _formatDateTime(dateTime),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Divider(color: Colors.grey.shade300),
              SizedBox(height: 12.h),
              _buildInfoRow(
                Icons.location_on,
                'Pickup: ${notification.pickupLocation}',
                Colors.blue.shade700,
              ),
              SizedBox(height: 8.h),
              _buildInfoRow(
                Icons.location_city,
                'Drop-off: ${notification.dropLocation}',
                Colors.green.shade700,
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  _buildInfoRow(
                    Icons.straighten,
                    'Distance: ${notification.distance} km',
                    Colors.orange.shade700,
                  ),
                  SizedBox(width: 16.w),
                  _buildInfoRow(
                    Icons.directions_car,
                    notification.vehicleType,
                    Colors.purple.shade700,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 18.sp, color: iconColor),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      }
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.buttonTextColor,
            fontSize: 20.sp,
          ),
        ),
        backgroundColor: AppColors.buttonColour,
        elevation: 0,
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: () => _markAllAsRead(user.uid),
              tooltip: 'Mark all as read',
            ),
        ],
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
          child: user != null
              ? StreamBuilder<QuerySnapshot>(
                  stream: _notificationsCollection
                      .where('driverId', isEqualTo: user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      final error = snapshot.error;
                      print('Notification loading error: $error');
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
                                  'Error loading notifications',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  error.toString().contains('index')
                                      ? 'Firestore index required. Please check console for link.'
                                      : error.toString(),
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.grey.shade600,
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
                        child: CircularProgressIndicator(
                            color: Colors.blue.shade700),
                      );
                    }

                    final notifications = <DeliveryNotification>[];
                    for (var doc in snapshot.data!.docs) {
                      try {
                        notifications.add(DeliveryNotification.fromSnapshot(doc));
                      } catch (e) {
                        print('Error parsing notification ${doc.id}: $e');
                        // Skip invalid notifications
                      }
                    }
                    
                    // Sort by createdAt in descending order (newest first)
                    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    if (notifications.isEmpty) {
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
                                  Icons.notifications_none,
                                  size: 48.sp,
                                  color: Colors.blue.shade700,
                                ),
                                SizedBox(height: 16.h),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  'You\'ll see delivery notifications here',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final unreadCount = notifications
                        .where((n) => !n.isRead)
                        .length;

                    return Column(
                      children: [
                        if (unreadCount > 0)
                          Container(
                            margin: EdgeInsets.all(16.w),
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 12.h),
                            decoration: BoxDecoration(
                              color: AppColors.buttonColour,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppColors.buttonTextColor,
                                  size: 20.sp,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: AppColors.buttonTextColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            itemCount: notifications.length,
                            itemBuilder: (context, index) {
                              return _buildNotificationCard(
                                  notifications[index]);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Center(
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
                            'Please log in to view notifications',
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
      ),
    );
  }
}


