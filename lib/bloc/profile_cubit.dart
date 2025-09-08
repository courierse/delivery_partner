import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/core/validators.dart';

part 'profile_state.dart';

class PhoneAuthCubit extends Cubit<PhoneAuthState> {
  PhoneAuthCubit() : super(const PhoneAuthState()) {
    _checkAuthState();
  }

  void _checkAuthState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint('User already authenticated: ${user.uid}');
      emit(state.copyWith(
        user: user,
        statusMessage: 'Authenticated',
        isCodeSent: false,
        phoneNumber: null,
        verificationId: null,
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
      ));
    }
  }

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    final errors = Map<String, String?>.from(state.errors);
    errors[key] = validateField(key, value);
    debugPrint('Updating field: $key = $value, error: ${errors[key]}, new fields: $fields');
    emit(state.copyWith(fields: fields, errors: errors, vehicleNumbers: state.vehicleNumbers));
  }

  void updateVehicleNumber(String vehicleType, String number) {
    final vehicleNumbers = Map<String, String>.from(state.vehicleNumbers)..[vehicleType] = number;
    final errors = Map<String, String?>.from(state.errors);
    errors['vehicleNumber_$vehicleType'] = validateField('vehicleNumber_$vehicleType', number);
    // debugPrint('Updating vehicle number: $vehicleType = $number, error: ${errors['vehicleNumber_$vehicleType]}, new vehicleNumbers: $vehicleNumbers');
    emit(state.copyWith(vehicleNumbers: vehicleNumbers, errors: errors, fields: state.fields));
  }

  void submitForm() async {
    final fields = Map<String, String>.from(state.fields);
    final vehicleNumbers = Map<String, String>.from(state.vehicleNumbers);
    final errors = Map<String, String?>.from(state.errors);
    bool hasError = false;

    // Validate all fields
    fields.forEach((key, value) {
      final error = validateField(key, value);
      errors[key] = error;
      if (error != null) {
        debugPrint('Validation error for $key: $error');
        hasError = true;
      }
    });

    // Validate vehicle numbers
    final selectedVehicles = fields['vehicleTypes']?.split(', ').where((v) => v.isNotEmpty).toList() ?? [];
    for (var vehicleType in selectedVehicles) {
      final number = vehicleNumbers[vehicleType] ?? '';
      final error = validateField('vehicleNumber_$vehicleType', number);
      errors['vehicleNumber_$vehicleType'] = error;
      if (error != null) {
        debugPrint('Validation error for vehicleNumber_$vehicleType: $error');
        hasError = true;
      }
    }

    debugPrint('Submitting form with fields: $fields, vehicleNumbers: $vehicleNumbers');
    if (hasError) {
      debugPrint('Form has errors: $errors');
      emit(state.copyWith(
        errors: errors,
        statusMessage: 'Please fix the errors in the form.',
        fields: fields,
        vehicleNumbers: vehicleNumbers,
      ));
      return;
    }

    final phoneNumber = fields['phone']!.startsWith('+91')
        ? fields['phone']!
        : '+91${fields['phone']}';
    debugPrint('Submitting form with phone number: $phoneNumber');

    try {
      emit(state.copyWith(
        statusMessage: 'Sending verification code...',
        errors: errors,
        fields: fields,
        vehicleNumbers: vehicleNumbers,
      ));

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('Verification completed automatically with credential');
          await FirebaseAuth.instance.signInWithCredential(credential);
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint('User signed in: ${user.uid}');
            await _saveUserDataToFirestore(user.uid);
            emit(state.copyWith(
              user: user,
              statusMessage: 'Authentication successful',
              isCodeSent: false,
              phoneNumber: null,
              verificationId: null,
              fields: fields,
              vehicleNumbers: vehicleNumbers,
            ));
          } else {
            debugPrint('Error: User is null after sign-in');
            emit(state.copyWith(
              statusMessage: 'Error: Authentication failed',
              fields: fields,
              vehicleNumbers: vehicleNumbers,
            ));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Verification failed: ${e.message}, code: ${e.code}');
          emit(state.copyWith(
            statusMessage: 'Error: ${e.message}',
            isCodeSent: false,
            phoneNumber: null,
            verificationId: null,
            fields: fields,
            vehicleNumbers: vehicleNumbers,
          ));
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('Code sent: verificationId=$verificationId, resendToken=$resendToken');
          emit(state.copyWith(
            isCodeSent: true,
            phoneNumber: phoneNumber,
            verificationId: verificationId,
            statusMessage: 'Verification code sent to $phoneNumber',
            fields: fields,
            vehicleNumbers: vehicleNumbers,
          ));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('Code auto-retrieval timeout: verificationId=$verificationId');
        },
      );
    } catch (e) {
      debugPrint('Error in verifyPhoneNumber: $e');
      emit(state.copyWith(
        statusMessage: 'Error: $e',
        fields: fields,
        vehicleNumbers: vehicleNumbers,
      ));
    }
  }

  void verifyOtp(String smsCode, String verificationId, BuildContext context) async {
    try {
      debugPrint('Verifying OTP: smsCode=$smsCode, verificationId=$verificationId');
      emit(state.copyWith(statusMessage: 'Verifying OTP...', fields: state.fields, vehicleNumbers: state.vehicleNumbers));

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        debugPrint('OTP verified, user signed in: ${user.uid}');
        await _saveUserDataToFirestore(user.uid);
        emit(state.copyWith(
          user: user,
          statusMessage: 'Authentication successful',
          isCodeSent: false,
          phoneNumber: null,
          verificationId: null,
          fields: state.fields,
          vehicleNumbers: state.vehicleNumbers,
        ));
        context.go('/home');
      } else {
        debugPrint('Error: User is null after OTP verification');
        emit(state.copyWith(statusMessage: 'Error: Authentication failed', fields: state.fields, vehicleNumbers: state.vehicleNumbers));
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      emit(state.copyWith(statusMessage: 'Error: $e', fields: state.fields, vehicleNumbers: state.vehicleNumbers));
    }
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      debugPrint('User signed out');
      emit(const PhoneAuthState(
        statusMessage: 'Logged out',
        isCodeSent: false,
        phoneNumber: null,
        verificationId: null,
        user: null,
      ));
    } catch (e) {
      debugPrint('Error signing out: $e');
      emit(state.copyWith(statusMessage: 'Error logging out: $e', fields: state.fields, vehicleNumbers: state.vehicleNumbers));
    }
  }

  Future<void> _saveUserDataToFirestore(String uid) async {
    try {
      debugPrint('Saving user data to Firestore: uid=$uid, fields=${state.fields}, vehicleNumbers=${state.vehicleNumbers}');
      final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
      await driverRef.set({
        'name': state.fields['name'] ?? '',
        'phone': state.fields['phone'] ?? '',
        'address': state.fields['address'] ?? '',
        'age': state.fields['age'] ?? '',
        'vehicleNumbers': state.vehicleNumbers,
        'vehicleTypes': state.fields['vehicleTypes'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('User data saved to Firestore');
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      emit(state.copyWith(statusMessage: 'Error saving data: $e', fields: state.fields, vehicleNumbers: state.vehicleNumbers));
    }
  }
}