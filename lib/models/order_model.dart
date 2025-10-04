import 'package:cloud_firestore/cloud_firestore.dart';

class Order {
  final String id;
  final String pickupLocation;
  final double? pickupLat;
  final double? pickupLng;
  final String dropLocation;
  final double? dropLat;
  final double? dropLng;
  final String pickupName;
  final String pickupPhone;
  final String dropName;
  final String dropPhone;
  final String weightRange;
  final String userId;
  final String status;
  final double distance;
  final double deliveryCost;
  final Timestamp createdAt;
  final String? driverId;
  final Timestamp? acceptedAt;
  final Timestamp? completedAt; // Added for completed orders
  final Timestamp? cancelledAt; // Added for cancelled orders
  final String? vehicleType;
  final bool? cancelledByUser;

  Order({
    required this.id,
    required this.pickupLocation,
    this.pickupLat,
    this.pickupLng,
    required this.dropLocation,
    this.dropLat,
    this.dropLng,
    required this.pickupName,
    required this.pickupPhone,
    required this.dropName,
    required this.dropPhone,
    required this.weightRange,
    required this.userId,
    required this.status,
    required this.distance,
    required this.deliveryCost,
    required this.createdAt,
    this.driverId,
    this.acceptedAt,
    this.completedAt, // Added to constructor
    this.cancelledAt, // Added to constructor
    this.vehicleType,
    this.cancelledByUser,
  });

  factory Order.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    return Order(
      id: snapshot.id,
      pickupLocation: data['pickupLocation'] ?? '',
      pickupLat: data['pickupLat']?.toDouble(),
      pickupLng: data['pickupLng']?.toDouble(),
      dropLocation: data['dropLocation'] ?? '',
      dropLat: data['dropLat']?.toDouble(),
      dropLng: data['dropLng']?.toDouble(),
      pickupName: data['pickupName'] ?? '',
      pickupPhone: data['pickupPhone'] ?? '',
      dropName: data['dropName'] ?? '',
      dropPhone: data['dropPhone'] ?? '',
      weightRange: data['weightRange'] ?? '',
      userId: data['userId'] ?? '',
      status: data['status'] ?? 'pending',
      distance: data['distance']?.toDouble() ?? 0.0,
      deliveryCost: data['deliveryCost']?.toDouble() ?? 0.0,
      createdAt: data['createdAt'] ?? Timestamp.now(),
      driverId: data['driverId'],
      acceptedAt: data['acceptedAt'],
      completedAt: data['completedAt'], // Added to parse completedAt
      cancelledAt: data['cancelledAt'], // Added to parse cancelledAt
      vehicleType: data['vehicleType'],
      cancelledByUser: data['cancelledByUser'] as bool?,
    );
  }
}