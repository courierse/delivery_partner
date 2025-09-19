import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class DriverLocationService {
  StreamSubscription<Position>? _positionStreamSubscription;

  Future<bool> _requestLocationPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled');
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions denied');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      print('Location permissions permanently denied');
      return false;
    }
    return true;
  }

  Future<void> startLocationUpdates(String orderId) async {
    final hasPermission = await _requestLocationPermissions();
    if (!hasPermission) {
      print('Cannot start location updates due to missing permissions');
      return;
    }

    await stopLocationUpdates();

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) async {
      try {
        await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
          'driverLatitude': position.latitude.toDouble(),
          'driverLongitude': position.longitude.toDouble(),
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('Updated driver location for order $orderId: Lat=${position.latitude}, Lng=${position.longitude}');
      } catch (e) {
        print('Error updating location for order $orderId: $e');
      }
    }, onError: (e) {
      print('Location stream error: $e');
    });
  }

  Future<void> stopLocationUpdates() async {
    if (_positionStreamSubscription != null) {
      await _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
      print('Stopped location updates');
    }
  }
}