import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/screens/phone_auth_page.dart';
import 'package:phone_authentication/screens/otp_screen.dart';
import 'package:phone_authentication/screens/home_screen.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';

final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) {
        final authState = context.read<PhoneAuthCubit>().state;
        if (authState.user != null) {
          debugPrint('Redirecting to /home for authenticated user');
          return '/home';
        }
        debugPrint('Redirecting to /login for unauthenticated user');
        return '/login';
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const PhoneAuthPage(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final phoneNumber = extra?['phoneNumber'] as String? ?? '';
        final verificationId = extra?['verificationId'] as String? ?? '';
        debugPrint('Navigation: Extracted phoneNumber from extra: $phoneNumber');
        return OtpScreen(
          phoneNumber: phoneNumber,
          verificationId: verificationId,
        );
      },
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);