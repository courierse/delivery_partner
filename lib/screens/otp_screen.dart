import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    context.read<PhoneAuthCubit>().verifyOtp(smsCode, widget.verificationId);
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
        if (state.statusMessage.contains('Authentication successful')) {
          context.pushReplacement('/home'); // Navigate to HomeScreen after successful auth
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Verify OTP',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.blueAccent,
          elevation: 0,
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
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Card(
                  elevation: 8.0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: Image.network(
                            'https://img.freepik.com/free-vector/mobile-login-concept-illustration_114360-135.jpg',
                            height: 150,
                            width: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 24.0),
                        Text(
                          'Enter the OTP sent to ${widget.phoneNumber.isEmpty ? "Not provided" : widget.phoneNumber}',
                          style: const TextStyle(
                            fontSize: 16.0,
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16.0),
                        TextField(
                          controller: _otpController,
                          decoration: const InputDecoration(
                            labelText: 'Enter OTP',
                            labelStyle: TextStyle(color: Colors.blueAccent),
                            prefixIcon: Icon(Icons.lock, color: Colors.blueAccent),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.0)),
                              borderSide: BorderSide(color: Colors.black, width: 2.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.0)),
                              borderSide: BorderSide(color: Colors.black, width: 2.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12.0)),
                              borderSide: BorderSide(color: Colors.black, width: 2.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 24.0),
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blueAccent, Colors.cyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12.0),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8.0,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _verifyOTP,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            child: const Text(
                              'Verify OTP',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24.0),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 16.0,
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