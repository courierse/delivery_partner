import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';
import 'package:phone_authentication/screens/custom_text_field.dart';

class MobileEntryPage extends StatefulWidget {
  const MobileEntryPage({super.key});

  @override
  _MobileEntryPageState createState() => _MobileEntryPageState();
}

class _MobileEntryPageState extends State<MobileEntryPage> {
  final TextEditingController _phoneController = TextEditingController();
  String _statusMessage = '';
  bool _isLoading = false;

  Future<void> _checkPhoneNumber() async {
    if (_isLoading) return;

    final phoneNumber = _phoneController.text.trim();
    debugPrint('Raw phone input: "$phoneNumber"');
    if (phoneNumber.isEmpty || phoneNumber.length != 10) {
      setState(() {
        _statusMessage = 'Please enter a valid 10-digit phone number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking phone number...';
    });

    try {
      final formattedPhone = '+91$phoneNumber'; // Match Firestore format: +917652067023
      debugPrint('Executing query: drivers.where(phone == $formattedPhone).limit(1)');
      final driverRef = FirebaseFirestore.instance
          .collection('drivers')
          .where('phone', isEqualTo: formattedPhone)
          .limit(1);
      final querySnapshot = await driverRef.get();

      if (querySnapshot.docs.isNotEmpty) {
        debugPrint('Phone number $formattedPhone found in Firestore, triggering OTP');
        context.read<PhoneAuthCubit>().submitForm(phoneNumber: formattedPhone);
        await Future.delayed(Duration.zero); // Ensure state emission
      } else {
        debugPrint('Phone number $formattedPhone not found in Firestore, navigating to phone auth');
        context.push('/phone-auth', extra: {'phoneNumber': phoneNumber});
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    } catch (e) {
      debugPrint('Error checking phone number: $e');
      setState(() {
        _statusMessage = 'Error: $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PhoneAuthCubit, PhoneAuthState>(
      listener: (context, state) {
        debugPrint('BlocListener triggered: isCodeSent=${state.isCodeSent}, '
            'phoneNumber=${state.phoneNumber}, statusMessage=${state.statusMessage}');
        setState(() {
          _statusMessage = state.statusMessage;
          _isLoading = state.statusMessage == 'Sending verification code...';
        });
        if (state.isCodeSent && state.phoneNumber != null && state.verificationId != null) {
          debugPrint('Navigating to /otp with phoneNumber: ${state.phoneNumber}');
          context.push('/otp', extra: {
            'phoneNumber': state.phoneNumber,
            'verificationId': state.verificationId,
          });
          setState(() {
            _isLoading = false;
          });
        } else if (state.statusMessage.contains('Error')) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.statusMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Enter Mobile Number',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 20.sp,
            ),
          ),
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          toolbarHeight: 60.h,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blueAccent, Colors.white],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Card(
                  elevation: 8.0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: Image.network(
                            'https://img.freepik.com/free-vector/mobile-login-concept-illustration_114360-135.jpg',
                            height: 150.h,
                            width: 150.w,
                            fit: BoxFit.cover,
                          ),
                        ),
                        SizedBox(height: 24.h),
                        CustomTextField(
                          controller: _phoneController,
                          labelText: 'Enter phone number',
                          prefixIcon: Icons.phone,
                          prefixText: '+91 ',
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelStyle: TextStyle(fontSize: 14.sp, color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 8.h,
                              horizontal: 16.w,
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                        ),
                        SizedBox(height: 24.h),
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blueAccent, Colors.cyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8.r,
                                offset: Offset(0, 4.h),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _checkPhoneNumber,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 32.w,
                                vertical: 16.h,
                              ),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                            child: _isLoading
                                ? CircularProgressIndicator(color: Colors.white)
                                : Text(
                                    'Confirm and Proceed',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: _statusMessage.contains('Error')
                                ? Colors.red
                                : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}