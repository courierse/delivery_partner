import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';
import 'package:phone_authentication/constants/images.dart';
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
      final formattedPhone = '+91$phoneNumber';
      debugPrint('Executing query: drivers.where(phone == $formattedPhone).limit(1)');
      final driverRef = FirebaseFirestore.instance
          .collection('drivers')
          .where('phone', isEqualTo: formattedPhone)
          .limit(1);
      final querySnapshot = await driverRef.get();

      if (querySnapshot.docs.isNotEmpty) {
        debugPrint('Phone number $formattedPhone found in Firestore, triggering OTP');
        context.read<PhoneAuthCubit>().submitForm(phoneNumber: formattedPhone);
        await Future.delayed(Duration.zero);
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
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue.shade800, Colors.blue.shade200],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Card(
                    elevation: 12.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(32.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Sign in with your phone number',
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(height: 24.h),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16.r),
                            child: Image.asset(
                              Images.phoneauthimg,
                              height: 180.h,
                              width: 180.w,
                              fit: BoxFit.cover,
                            ),
                          ),
                          SizedBox(height: 32.h),
                          CustomTextField(
                            controller: _phoneController,
                            labelText: 'Phone Number',
                            prefixIcon: Icons.phone_iphone,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelStyle: TextStyle(
                                fontSize: 16.sp,
                                color: Colors.grey.shade700,
                              ),
                              prefixIcon: Icon(
                                Icons.phone_iphone,
                                color: Colors.blue.shade700,
                                size: 24.sp,
                              ),
                              prefixText: '+91 ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r),
                                borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12.h,
                                horizontal: 16.w,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          SizedBox(height: 32.h),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.blue.shade700, Colors.blue.shade400],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10.r,
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
                                  ? SizedBox(
                                      height: 24.h,
                                      width: 24.h,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      'Continue',
                                      style: TextStyle(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.w600,
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
                                  ? Colors.red.shade600
                                  : Colors.green.shade600,
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
      ),
    );
  }
}