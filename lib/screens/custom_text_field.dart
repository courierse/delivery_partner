import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final IconData? prefixIcon;
  final TextInputType keyboardType;
  final String? prefixText;
  final String? errorText;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.prefixIcon,
    required this.keyboardType,
    this.prefixText,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        prefixText: prefixText,
        errorText: errorText,
        labelStyle: const TextStyle(color: Colors.blueAccent),
        prefixStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.blueAccent) : null,
        errorStyle: const TextStyle(color: Colors.red),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
          borderSide: BorderSide(color: Colors.black, width: 2.0),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
          borderSide: BorderSide(color: Colors.black, width: 2.0),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
          borderSide: BorderSide(color: Colors.black, width: 2.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
          borderSide: BorderSide(color: Colors.red, width: 2.0),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
          borderSide: BorderSide(color: Colors.red, width: 2.5),
        ),
        filled: true,
        fillColor: Colors.grey[100],
      ),
      keyboardType: keyboardType,
    );
  }
}