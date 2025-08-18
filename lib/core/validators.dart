import 'package:flutter/material.dart';

class Validator {
  static final Map<String, String? Function(String?)> validators = {
    'name': (String? value) =>
        value == null || value.trim().isEmpty ? 'Name is required' : null,
    'phone': (String? value) => value == null || value.trim().isEmpty
        ? 'Phone number is required'
        : !RegExp(r'^\d{10}$').hasMatch(value.trim())
            ? 'Phone number must be exactly 10 digits'
            : null,
    'address': (String? value) =>
        value == null || value.trim().isEmpty ? 'Address is required' : null,
    'age': (String? value) {
      if (value == null || value.trim().isEmpty) return 'Age is required';
      final age = int.tryParse(value.trim());
      return age == null || age < 19
          ? 'You must be 19 or older to become a delivery partner'
          : null;
    },
    'vehicle': (String? value) =>
        value == null || value.trim().isEmpty ? 'Vehicle number is required' : null,
  };
}