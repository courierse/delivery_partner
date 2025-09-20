import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
      ));
    }
  }

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    final errors = Map<String, String?>.from(state.errors);
    errors[key] = validateField(key, value);
    debugPrint('Updating field: $key = $value, error: ${errors[key]}, new fields: $fields');
    emit(state.copyWith(fields: fields, errors: errors, vehicleNumbers: state.vehicleNumbers, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));
  }

  void updateVehicleNumber(String vehicleType, String number) {
    final vehicleNumbers = Map<String, String>.from(state.vehicleNumbers)..[vehicleType] = number;
    final errors = Map<String, String?>.from(state.errors);
    errors['vehicleNumber_$vehicleType'] = validateField('vehicleNumber_$vehicleType', number, validateVehicleNumber: true);
    debugPrint('Updating vehicle number: $vehicleType = $number, error: ${errors['vehicleNumber_$vehicleType']}, new vehicleNumbers: $vehicleNumbers');
    emit(state.copyWith(vehicleNumbers: vehicleNumbers, errors: errors, fields: state.fields, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));
  }

  void updateRcImage(String vehicleType, XFile image) {
    final rcImageFiles = Map<String, XFile?>.from(state.rcImageFiles)..[vehicleType] = image;
    debugPrint('Stored RC image file for $vehicleType: ${image.path}');
    emit(state.copyWith(
      rcImageFiles: rcImageFiles,
      fields: state.fields,
      vehicleNumbers: state.vehicleNumbers,
      rcImages: state.rcImages,
      errors: state.errors,
    ));
  }

  void removeRcImage(String vehicleType) {
    final rcImageFiles = Map<String, XFile?>.from(state.rcImageFiles)..remove(vehicleType);
    final rcImages = Map<String, String>.from(state.rcImages)..remove(vehicleType);
    debugPrint('Removed RC image for $vehicleType');
    emit(state.copyWith(
      rcImageFiles: rcImageFiles,
      rcImages: rcImages,
      fields: state.fields,
      vehicleNumbers: state.vehicleNumbers,
      errors: state.errors,
    ));
  }

  String? validateVehicleNumber(String vehicleType, String number) {
    final error = validateField('vehicleNumber_$vehicleType', number, validateVehicleNumber: true);
    debugPrint('Validating vehicle number for $vehicleType: $number, error: $error');
    return error;
  }

  void submitForm({Map<String, String>? fallbackVehicleNumbers, String? phoneNumber}) async {
    final fields = Map<String, String>.from(state.fields);
    final vehicleNumbers = Map<String, String>.from(state.vehicleNumbers);
    final rcImageFiles = Map<String, XFile?>.from(state.rcImageFiles);
    final rcImages = Map<String, String>.from(state.rcImages);
    final errors = Map<String, String?>.from(state.errors);
    bool hasError = false;

    if (phoneNumber != null) {
      // Handle phone-only submission from MobileEntryPage
      final submitPhoneNumber = phoneNumber.startsWith('+91') ? phoneNumber : '+91$phoneNumber';
      // Skip validation for phone-only submission
      debugPrint('Submitting phone-only: $submitPhoneNumber');
    } else {
      // Full form submission from PhoneAuthPage
      if (fallbackVehicleNumbers != null) {
        fallbackVehicleNumbers.forEach((key, value) {
          if (value.isNotEmpty) {
            vehicleNumbers[key] = value;
            debugPrint('Applied fallback vehicle number: $key = $value');
          }
        });
      }

      fields.forEach((key, value) {
        final error = validateField(key, value);
        errors[key] = error;
        if (error != null) {
          debugPrint('Validation error for $key: $error');
          hasError = true;
        }
      });

      final selectedVehicles = fields['vehicleTypes']?.split(', ').where((v) => v.isNotEmpty).toList() ?? [];
      for (var vehicleType in selectedVehicles) {
        final number = vehicleNumbers[vehicleType] ?? '';
        debugPrint('Validating vehicle number for $vehicleType: $number');
        final error = validateField('vehicleNumber_$vehicleType', number, validateVehicleNumber: true);
        errors['vehicleNumber_$vehicleType'] = error;
        if (error != null) {
          debugPrint('Validation error for vehicleNumber_$vehicleType: $error');
          hasError = true;
        }
        if (!rcImageFiles.containsKey(vehicleType) || rcImageFiles[vehicleType] == null) {
          errors['rcImage_$vehicleType'] = 'RC image is required for $vehicleType';
          hasError = true;
        }
      }
    }

    if (hasError) {
      debugPrint('Form has errors: $errors');
      emit(state.copyWith(
        errors: errors,
        statusMessage: 'Please fix the errors in the form.',
        fields: fields,
        vehicleNumbers: vehicleNumbers,
        rcImageFiles: rcImageFiles,
        rcImages: rcImages,
      ));
      return;
    }

    final submitPhoneNumber = phoneNumber != null
        ? (phoneNumber.startsWith('+91') ? phoneNumber : '+91$phoneNumber')
        : (fields['phone']!.startsWith('+91') ? fields['phone']! : '+91${fields['phone']}');
    debugPrint('Submitting form with phone number: $submitPhoneNumber');

    try {
      emit(state.copyWith(
        statusMessage: 'Sending verification code...',
        errors: errors,
        fields: fields,
        vehicleNumbers: vehicleNumbers,
        rcImageFiles: rcImageFiles,
        rcImages: rcImages,
      ));

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: submitPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('Verification completed automatically with credential');
          await FirebaseAuth.instance.signInWithCredential(credential);
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            debugPrint('User signed in: ${user.uid}');
            if (phoneNumber == null) {
              // Only save data if coming from PhoneAuthPage (full form)
              await _saveUserDataToFirestore(user.uid);
            }
            emit(state.copyWith(
              user: user,
              statusMessage: 'Authentication successful',
              isCodeSent: false,
              phoneNumber: null,
              verificationId: null,
              fields: fields,
              vehicleNumbers: vehicleNumbers,
              rcImageFiles: rcImageFiles,
              rcImages: rcImages,
            ));
          } else {
            debugPrint('Error: User is null after sign-in');
            emit(state.copyWith(
              statusMessage: 'Error: Authentication failed',
              fields: fields,
              vehicleNumbers: vehicleNumbers,
              rcImageFiles: rcImageFiles,
              rcImages: rcImages,
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
            rcImageFiles: rcImageFiles,
            rcImages: rcImages,
          ));
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('Code sent: verificationId=$verificationId, resendToken=$resendToken');
          emit(state.copyWith(
            isCodeSent: true,
            phoneNumber: submitPhoneNumber,
            verificationId: verificationId,
            statusMessage: 'Verification code sent to $submitPhoneNumber',
            fields: fields,
            vehicleNumbers: vehicleNumbers,
            rcImageFiles: rcImageFiles,
            rcImages: rcImages,
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
        rcImageFiles: rcImageFiles,
        rcImages: rcImages,
      ));
    }
  }

  void verifyOtp(String smsCode, String verificationId, BuildContext context) async {
    try {
      debugPrint('Verifying OTP: smsCode=$smsCode, verificationId=$verificationId');
      emit(state.copyWith(statusMessage: 'Verifying OTP...', fields: state.fields, vehicleNumbers: state.vehicleNumbers, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        debugPrint('OTP verified, user signed in: ${user.uid}');
        final driverRef = FirebaseFirestore.instance.collection('drivers').doc(user.uid);
        final driverDoc = await driverRef.get();
        if (driverDoc.exists) {
          // If driver data exists, skip saving new data
          debugPrint('Driver data exists, skipping save');
        } else {
          // Save data if it was a new registration
          await _saveUserDataToFirestore(user.uid);
        }
        emit(state.copyWith(
          user: user,
          statusMessage: 'Authentication successful',
          isCodeSent: false,
          phoneNumber: null,
          verificationId: null,
          fields: state.fields,
          vehicleNumbers: state.vehicleNumbers,
          rcImageFiles: state.rcImageFiles,
          rcImages: state.rcImages,
        ));
        context.go('/home');
      } else {
        debugPrint('Error: User is null after OTP verification');
        emit(state.copyWith(statusMessage: 'Error: Authentication failed', fields: state.fields, vehicleNumbers: state.vehicleNumbers, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      emit(state.copyWith(statusMessage: 'Error: $e', fields: state.fields, vehicleNumbers: state.vehicleNumbers, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));
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
      emit(state.copyWith(statusMessage: 'Error logging out: $e', fields: state.fields, vehicleNumbers: state.vehicleNumbers, rcImageFiles: state.rcImageFiles, rcImages: state.rcImages));
    }
  }

  Future<void> _saveUserDataToFirestore(String uid) async {
    try {
      debugPrint('Saving user data to Firestore: uid=$uid, fields=${state.fields}, vehicleNumbers=${state.vehicleNumbers}, rcImageFiles=${state.rcImageFiles}');
      final rcImages = <String, String>{};
      for (var entry in state.rcImageFiles.entries) {
        final vehicleType = entry.key;
        final image = entry.value;
        if (image != null) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('drivers/$uid/rc_images/$vehicleType-${DateTime.now().millisecondsSinceEpoch}.jpg');
          await storageRef.putFile(File(image.path));
          final downloadUrl = await storageRef.getDownloadURL();
          rcImages[vehicleType] = downloadUrl;
          debugPrint('Uploaded RC image for $vehicleType: $downloadUrl');
        }
      }

      final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
      await driverRef.set({
        'name': state.fields['name'] ?? '',
        'phone': state.fields['phone']!.startsWith('+91') ? state.fields['phone']! : '+91${state.fields['phone']}',
        'address': state.fields['address'] ?? '',
        'age': state.fields['age'] ?? '',
        'vehicleNumbers': state.vehicleNumbers,
        'vehicleTypes': state.fields['vehicleTypes'] ?? '',
        'rcImages': rcImages,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('User data saved to Firestore');
      emit(state.copyWith(
        rcImages: rcImages,
        statusMessage: 'User data saved successfully',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
      ));
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      emit(state.copyWith(
        statusMessage: 'Error saving data: $e',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
      ));
    }
  }
}