import 'package:equatable/equatable.dart';

abstract class LocationState extends Equatable {
  const LocationState();

  @override
  List<Object?> get props => [];
}

class LocationInitial extends LocationState {}

class CurrentLocationUpdated extends LocationState {
  final double latitude;
  final double longitude;

  const CurrentLocationUpdated(this.latitude, this.longitude);

  @override
  List<Object?> get props => [latitude, longitude];
}

class LocationError extends LocationState {
  final String message;

  const LocationError(this.message);

  @override
  List<Object?> get props => [message];
}