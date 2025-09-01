import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/constants/images.dart';
import 'package:phone_authentication/screens/custom_text_field.dart';
import '../bloc/profile_cubit.dart';

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key});

  @override
  _PhoneAuthPageState createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final _controllers = {
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'address': TextEditingController(),
    'age': TextEditingController(),
    'vehicle': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _controllers['phone']!.selection = TextSelection.fromPosition(
      const TextPosition(offset: 0),
    );
  }

  Widget _buildTextField({
    required String key,
    required String label,
    required TextInputType keyboardType,
    IconData? prefixIcon,
    String? prefixText,
    String? errorText,
    required BuildContext context,
  }) {
    _controllers[key]!.text = context.read<PhoneAuthCubit>().state.fields[key] ?? '';
    _controllers[key]!.addListener(() {
      context.read<PhoneAuthCubit>().updateField(key, _controllers[key]!.text);
    });

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: CustomTextField(
        controller: _controllers[key]!,
        labelText: label,
        prefixIcon: prefixIcon,
        keyboardType: keyboardType,
        prefixText: prefixText,
        errorText: errorText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PhoneAuthCubit, PhoneAuthState>(
      listener: (context, state) {
        if (state.user != null) {
          context.go('/home'); // Redirect to HomeScreen if authenticated
        } else if (state.isCodeSent && state.phoneNumber != null && state.verificationId != null) {
          debugPrint('Navigating with phone number: ${state.phoneNumber}, verificationId: ${state.verificationId}');
          try {
            context.push('/otp', extra: {
              'phoneNumber': state.phoneNumber,
              'verificationId': state.verificationId,
            });
          } catch (e) {
            debugPrint('Navigation error: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Navigation failed: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
          }
        } else if (state.statusMessage.contains('Error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.statusMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Phone Authentication',
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: BlocBuilder<PhoneAuthCubit, PhoneAuthState>(
                      builder: (context, state) {
                        return Column(
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
                            _buildTextField(
                              key: 'name',
                              label: 'Enter name',
                              keyboardType: TextInputType.name,
                              prefixIcon: Icons.person,
                              errorText: state.errors['name'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'phone',
                              label: 'Enter phone number',
                              keyboardType: TextInputType.phone,
                              prefixIcon: Icons.phone,
                              prefixText: '+91 ',
                              errorText: state.errors['phone'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'address',
                              label: 'Enter address',
                              keyboardType: TextInputType.streetAddress,
                              prefixIcon: Icons.location_on,
                              errorText: state.errors['address'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'age',
                              label: 'Enter age',
                              keyboardType: TextInputType.number,
                              prefixIcon: Icons.cake,
                              errorText: state.errors['age'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'vehicle',
                              label: 'Enter vehicle number',
                              keyboardType: TextInputType.text,
                              prefixIcon: Icons.directions_car,
                              errorText: state.errors['vehicle'],
                              context: context,
                            ),
                            SizedBox(height: 8.h),
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
                                onPressed: state.isCodeSent
                                    ? null
                                    : () => context.read<PhoneAuthCubit>().submitForm(),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: Text(
                                  'Send Verification Code',
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
                              state.statusMessage,
                              style: TextStyle(
                                fontSize: 16.sp,
                                color: state.statusMessage.contains('Error') ? Colors.red : Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
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
    _controllers.forEach((_, controller) {
      controller.removeListener(() {});
      controller.dispose();
    });
    super.dispose();
  }
}