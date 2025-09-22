import 'package:flutter/material.dart';

String? validateField(String key, String value, {bool validateVehicleNumber = false, bool validateAadharNumber = false}) {
  final validators = {
    'name': (String value) =>
        value.trim().isEmpty ? 'Name is required' : null,
    'phone': (String value) =>
        value.trim().isEmpty
            ? 'Phone number is required'
            : !RegExp(r'^\d{10}$').hasMatch(value.trim())
                ? 'Phone number must be exactly 10 digits'
                : null,
    'address': (String value) =>
        value.trim().isEmpty ? 'Address is required' : null,
    'age': (String value) {
      if (value.trim().isEmpty) return 'Age is required';
      final age = int.tryParse(value.trim());
      return age == null || age < 19
          ? 'You must be 19 or older to become a delivery partner'
          : null;
    },
    'vehicleTypes': (String value) =>
        value.trim().isEmpty ? 'At least one vehicle type is required' : null,
    'aadharNumber': (String value) =>
        value.trim().isEmpty
            ? 'Aadhar number is required'
            : !RegExp(r'^\d{12}$').hasMatch(value.trim())
                ? 'Aadhar number must be exactly 12 digits'
                : null,
  };

  if (key.startsWith('vehicleNumber_') && validateVehicleNumber) {
    return value.trim().isEmpty
        ? 'Enter in correct format MH32TY8923'
        : !RegExp(r'^[A-Z]{2}\d{2}[A-Z]{1,2}\d{4}$').hasMatch(value.trim())
            ? 'Enter in correct format MH32TY8923'
            : null;
  }

  if (key == 'aadharNumber' && validateAadharNumber) {
    return value.trim().isEmpty
        ? 'Aadhar number is required'
        : !RegExp(r'^\d{12}$').hasMatch(value.trim())
            ? 'Aadhar number must be exactly 12 digits'
            : null;
  }

  final validator = validators[key];
  return validator != null ? validator(value) : null;
}