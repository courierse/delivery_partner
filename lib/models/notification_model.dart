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
    final data = snapshot.data() as Map<String, dynamic>;
    return DeliveryNotification(
      id: snapshot.id,
      driverId: data['driverId'] ?? '',
      orderId: data['orderId'] ?? '',
      title: data['title'] ?? 'New Delivery Request',
      body: data['body'] ?? '',
      pickupLocation: data['pickupLocation'] ?? 'Unknown',
      dropLocation: data['dropLocation'] ?? 'Unknown',
      distance: data['distance'] ?? '0.0',
      vehicleType: data['vehicleType'] ?? 'Unknown',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      isRead: data['isRead'] ?? false,
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


