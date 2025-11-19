import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryNotification {
  final String id;
  final String driverId;
  final String orderId;
  final String title;
  final String body;
  final String pickupLocation;
  final String dropLocation;
  final String distance;
  final String vehicleType;
  final Timestamp createdAt;
  final bool isRead;

  DeliveryNotification({
    required this.id,
    required this.driverId,
    required this.orderId,
    required this.title,
    required this.body,
    required this.pickupLocation,
    required this.dropLocation,
    required this.distance,
    required this.vehicleType,
    required this.createdAt,
    this.isRead = false,
  });

  factory DeliveryNotification.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data();
    if (data == null || data is! Map<String, dynamic>) {
      throw Exception('Invalid notification data for document ${snapshot.id}');
    }
    
    // Handle createdAt - it might be a Timestamp or null
    Timestamp createdAtValue;
    if (data['createdAt'] is Timestamp) {
      createdAtValue = data['createdAt'] as Timestamp;
    } else if (data['createdAt'] != null) {
      // Try to convert if it's a different type
      createdAtValue = Timestamp.now();
    } else {
      createdAtValue = Timestamp.now();
    }
    
    return DeliveryNotification(
      id: snapshot.id,
      driverId: data['driverId']?.toString() ?? '',
      orderId: data['orderId']?.toString() ?? '',
      title: data['title']?.toString() ?? 'New Delivery Request',
      body: data['body']?.toString() ?? '',
      pickupLocation: data['pickupLocation']?.toString() ?? 'Unknown',
      dropLocation: data['dropLocation']?.toString() ?? 'Unknown',
      distance: data['distance']?.toString() ?? '0.0',
      vehicleType: data['vehicleType']?.toString() ?? 'Unknown',
      createdAt: createdAtValue,
      isRead: data['isRead'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'orderId': orderId,
      'title': title,
      'body': body,
      'pickupLocation': pickupLocation,
      'dropLocation': dropLocation,
      'distance': distance,
      'vehicleType': vehicleType,
      'createdAt': createdAt,
      'isRead': isRead,
    };
  }
}


