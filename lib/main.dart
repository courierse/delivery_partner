import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phone_authentication/bloc/location_cubit/location_cubit.dart';
import 'package:phone_authentication/core/navigation.dart';
import 'package:phone_authentication/firebase_options.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';
import 'package:phone_authentication/services/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  setupLocator(); // Initialize service locator
     await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,   // ✅ Allow only portrait up
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => PhoneAuthCubit(),
            ),
            BlocProvider(
              create: (context) => locator<LocationCubit>()..getCurrentLocation(),
            ),
          ],
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