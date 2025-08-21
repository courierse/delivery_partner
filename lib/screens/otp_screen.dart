import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/bloc/phone_auth_cubit.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  _OtpScreenState createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  String _statusMessage = '';

  void _verifyOTP() {
    final smsCode = _otpController.text.trim();
    if (smsCode.isEmpty) {
      setState(() => _statusMessage = 'Please enter OTP');
      return;
    }
    // Pass context to verifyOtp
    context.read<PhoneAuthCubit>().verifyOtp(smsCode, widget.verificationId, context);
  }

  @override
  void initState() {
    super.initState();
    debugPrint('Received phone number in OtpScreen: ${widget.phoneNumber}, verificationId: ${widget.verificationId}');
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PhoneAuthCubit, PhoneAuthState>(
      listener: (context, state) {
        setState(() => _statusMessage = state.statusMessage);
        // Navigation is handled in PhoneAuthCubit, so no need for context.pushReplacement here
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Verify OTP',
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
                        Text(
                          'Enter the OTP sent to ${widget.phoneNumber.isEmpty ? "Not provided" : widget.phoneNumber}',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16.h),
                        TextField(
                          controller: _otpController,
                          decoration: InputDecoration(
                            labelText: 'Enter OTP',
                            labelStyle: TextStyle(color: Colors.blueAccent, fontSize: 14.sp),
                            prefixIcon: Icon(Icons.lock, color: Colors.blueAccent, size: 24.r),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.r)),
                              borderSide: BorderSide(color: Colors.black, width: 2.w),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.r)),
                              borderSide: BorderSide(color: Colors.black, width: 2.w),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.r)),
                              borderSide: BorderSide(color: Colors.black, width: 2.5.w),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                          ),
                          keyboardType: TextInputType.number,
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
                            onPressed: _verifyOTP,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                            child: Text(
                              'Verify OTP',
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
                            color: _statusMessage.contains('Error') ? Colors.red : Colors.green,
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

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }
}