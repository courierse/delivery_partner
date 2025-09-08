import 'package:flutter/material.dart';

String? validateField(String key, String value) {
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
  };

  if (key.startsWith('vehicleNumber_')) {
    return value.trim().isEmpty
        ? 'Vehicle number is required'
        : !RegExp(r'^[A-Z]{2}\d{2}[A-Z]{1,2}\d{4}$').hasMatch(value.trim())
            ? 'Enter a valid vehicle number (e.g., MH12AB1234)'
            : null;
  }

  final validator = validators[key];
  return validator != null ? validator(value) : null;
}