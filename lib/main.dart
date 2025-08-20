import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/core/navigation.dart';
import 'package:phone_authentication/firebase_options.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_authentication/bloc/phone_auth_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690), // Reference design size for scaling
      minTextAdapt: true, // Adapt text for small/large screens
      splitScreenMode: true, // Support split-screen or foldable devices
      builder: (context, child) {
        return BlocProvider(
          create: (context) => PhoneAuthCubit(),
          child: MaterialApp.router(
            title: 'Phone Auth UI Demo',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primarySwatch: Colors.blue,
            ),
            routerConfig: router,
          ),
        );
      },
    );
  }
}