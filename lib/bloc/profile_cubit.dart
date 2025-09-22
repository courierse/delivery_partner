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
        aadharImage: state.aadharImage,
      ));
    }
  }

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    final errors = Map<String, String?>.from(state.errors);
    errors[key] = validateField(key, value, validateAadharNumber: key == 'aadharNumber');
    debugPrint('Updating field: $key = $value, error: ${errors[key]}, new fields: $fields');
    emit(state.copyWith(
      fields: fields,
      errors: errors,
      vehicleNumbers: state.vehicleNumbers,
      rcImageFiles: state.rcImageFiles,
      rcImages: state.rcImages,
      aadharImage: state.aadharImage,
    ));
  }

  void updateVehicleNumber(String vehicleType, String number) {
    final vehicleNumbers = Map<String, String>.from(state.vehicleNumbers)..[vehicleType] = number;
    final errors = Map<String, String?>.from(state.errors);
    errors['vehicleNumber_$vehicleType'] = validateField('vehicleNumber_$vehicleType', number, validateVehicleNumber: true);
    debugPrint('Updating vehicle number: $vehicleType = $number, error: ${errors['vehicleNumber_$vehicleType']}, new vehicleNumbers: $vehicleNumbers');
    emit(state.copyWith(
      vehicleNumbers: vehicleNumbers,
      errors: errors,
      fields: state.fields,
      rcImageFiles: state.rcImageFiles,
      rcImages: state.rcImages,
      aadharImage: state.aadharImage,
    ));
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
      aadharImage: state.aadharImage,
    ));
  }

  void updateAadharImage(XFile? image) {
    debugPrint('Stored Aadhar image: ${image?.path}');
    final errors = Map<String, String?>.from(state.errors);
    errors['aadharImage'] = image == null ? 'Aadhar image is required' : null;
    emit(state.copyWith(
      aadharImage: image,
      errors: errors,
      fields: state.fields,
      vehicleNumbers: state.vehicleNumbers,
      rcImageFiles: state.rcImageFiles,
      rcImages: state.rcImages,
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
      aadharImage: state.aadharImage,
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
        final error = validateField(key, value, validateAadharNumber: key == 'aadharNumber');
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

      // Validate Aadhar image
      if (state.aadharImage == null) {
        errors['aadharImage'] = 'Aadhar image is required';
        hasError = true;
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
        aadharImage: state.aadharImage,
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
        aadharImage: state.aadharImage,
      ));

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: submitPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('Verification completed automatically with credential');
          try {
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
                aadharImage: state.aadharImage,
              ));
            } else {
              debugPrint('Error: User is null after sign-in');
              emit(state.copyWith(
                statusMessage: 'Error: Authentication failed',
                fields: fields,
                vehicleNumbers: vehicleNumbers,
                rcImageFiles: rcImageFiles,
                rcImages: rcImages,
                aadharImage: state.aadharImage,
              ));
            }
          } catch (e) {
            debugPrint('Error during auto-verification sign-in: $e');
            emit(state.copyWith(
              statusMessage: 'Error: Authentication failed - $e',
              fields: fields,
              vehicleNumbers: vehicleNumbers,
              rcImageFiles: rcImageFiles,
              rcImages: rcImages,
              aadharImage: state.aadharImage,
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
            aadharImage: state.aadharImage,
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
            aadharImage: state.aadharImage,
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
        aadharImage: state.aadharImage,
      ));
    }
  }

  void verifyOtp(String smsCode, String verificationId, BuildContext context) async {
    try {
      debugPrint('Verifying OTP: smsCode=$smsCode, verificationId=$verificationId');
      emit(state.copyWith(
        statusMessage: 'Verifying OTP...',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
        aadharImage: state.aadharImage,
      ));

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
          debugPrint('Driver data exists, skipping save');
        } else {
          debugPrint('Saving new driver data for user: ${user.uid}');
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
          aadharImage: state.aadharImage,
        ));
        context.go('/home');
      } else {
        debugPrint('Error: User is null after OTP verification');
        emit(state.copyWith(
          statusMessage: 'Error: Authentication failed',
          fields: state.fields,
          vehicleNumbers: state.vehicleNumbers,
          rcImageFiles: state.rcImageFiles,
          rcImages: state.rcImages,
          aadharImage: state.aadharImage,
        ));
      }
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      emit(state.copyWith(
        statusMessage: 'Error: $e',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
        aadharImage: state.aadharImage,
      ));
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
      emit(state.copyWith(
        statusMessage: 'Error logging out: $e',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
        aadharImage: state.aadharImage,
      ));
    }
  }

  Future<void> _saveUserDataToFirestore(String uid) async {
    try {
      debugPrint('Attempting to save user data to Firestore: uid=$uid, fields=${state.fields}, vehicleNumbers=${state.vehicleNumbers}, rcImageFiles=${state.rcImageFiles.keys}, aadharImage=${state.aadharImage?.path}');
      
      // Save profile data first, regardless of image upload success
      final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
      final data = {
        'name': state.fields['name'] ?? '',
        'phone': state.fields['phone']!.startsWith('+91') ? state.fields['phone']! : '+91${state.fields['phone']}',
        'address': state.fields['address'] ?? '',
        'age': state.fields['age'] ?? '',
        'vehicleNumbers': state.vehicleNumbers,
        'vehicleTypes': state.fields['vehicleTypes'] ?? '',
        'aadharNumber': state.fields['aadharNumber'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      debugPrint('Saving initial profile data to Firestore: $data');
      await driverRef.set(data, SetOptions(merge: true));
      debugPrint('Initial profile data saved to Firestore successfully');

      // Attempt to upload RC images
      final rcImages = <String, String>{};
      for (var entry in state.rcImageFiles.entries) {
        final vehicleType = entry.key;
        final image = entry.value;
        if (image != null) {
          try {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('drivers/$uid/rc_images/$vehicleType-${DateTime.now().millisecondsSinceEpoch}.jpg');
            debugPrint('Uploading RC image for $vehicleType to ${storageRef.fullPath}');
            await storageRef.putFile(File(image.path));
            final downloadUrl = await storageRef.getDownloadURL();
            rcImages[vehicleType] = downloadUrl;
            debugPrint('Uploaded RC image for $vehicleType: $downloadUrl');
          } catch (e) {
            debugPrint('Error uploading RC image for $vehicleType: $e');
            // Continue to next image instead of failing entirely
          }
        }
      }

      // Attempt to upload Aadhar image
      String? aadharImageUrl;
      if (state.aadharImage != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('drivers/$uid/aadhar_image/aadhar-${DateTime.now().millisecondsSinceEpoch}.jpg');
          debugPrint('Uploading Aadhar image to ${storageRef.fullPath}');
          await storageRef.putFile(File(state.aadharImage!.path));
          aadharImageUrl = await storageRef.getDownloadURL();
          debugPrint('Uploaded Aadhar image: $aadharImageUrl');
        } catch (e) {
          debugPrint('Error uploading Aadhar image: $e');
          // Continue instead of failing entirely
        }
      }

      // Update Firestore with image URLs if available
      if (rcImages.isNotEmpty || aadharImageUrl != null) {
        final updateData = {
          if (rcImages.isNotEmpty) 'rcImages': rcImages,
          if (aadharImageUrl != null) 'aadharImage': aadharImageUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        debugPrint('Updating Firestore with image URLs: $updateData');
        await driverRef.set(updateData, SetOptions(merge: true));
        debugPrint('Image URLs saved to Firestore successfully');
      }

      emit(state.copyWith(
        rcImages: rcImages,
        statusMessage: 'User data saved successfully',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        aadharImage: state.aadharImage,
      ));
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      emit(state.copyWith(
        statusMessage: 'Error saving data: $e',
        fields: state.fields,
        vehicleNumbers: state.vehicleNumbers,
        rcImageFiles: state.rcImageFiles,
        rcImages: state.rcImages,
        aadharImage: state.aadharImage,
      ));
    }
  }
}