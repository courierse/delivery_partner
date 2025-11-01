import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class AppCheckService {
  static final AppCheckService _instance = AppCheckService._internal();
  factory AppCheckService() => _instance;
  AppCheckService._internal();

  bool _isInitialized = false;

  /// Initialize Firebase App Check
  /// 
  /// For debug builds, uses DebugAppCheckProvider
  /// For production builds, uses platform-specific providers:
  /// - Android: PlayIntegrityProvider
  /// - iOS: DeviceCheckProvider
  /// - Web: ReCaptchaEnterpriseProvider (configure in Firebase Console)
  /// 
  /// IMPORTANT SETUP STEPS:
  /// 1. Run the app in debug mode and check console for debug token
  /// 2. Register the debug token in Firebase Console > App Check > Apps
  /// 3. For production: Configure Play Integrity (Android) and DeviceCheck (iOS) in Firebase Console
  /// 4. For web: Configure ReCAPTCHA Enterprise in Firebase Console and update the site key below
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        // Debug provider for development
        // Register the debug token in Firebase Console > App Check
        await FirebaseAppCheck.instance.activate(
          providerAndroid: AndroidDebugProvider(),
          providerApple: AppleDebugProvider(),
          // Web debug provider - you can add ReCaptchaEnterpriseProvider if needed
        );
        
        if (kDebugMode) {
          print('═══════════════════════════════════════════════════════');
          print('🔐 App Check initialized with DEBUG provider');
          print('═══════════════════════════════════════════════════════');
          
          // Try to get token multiple times with increasing delays
          String? debugToken;
          for (int attempt = 0; attempt < 8; attempt++) {
            await Future.delayed(Duration(milliseconds: 500 + (attempt * 500)));
            try {
              debugToken = await getToken();
              if (debugToken != null && debugToken.isNotEmpty) {
                break;
              }
            } catch (e) {
              if (kDebugMode) {
                print('Attempt ${attempt + 1} failed: $e');
              }
            }
          }
          
          if (debugToken != null && debugToken.isNotEmpty) {
            print('📋 YOUR DEBUG TOKEN: $debugToken');
            print('');
            print('⚠️  IMPORTANT: Copy this token and register it in:');
            print('   Firebase Console > App Check > Apps > [Your App] > Manage debug tokens');
            print('');
            print('   Steps:');
            print('   1. Go to https://console.firebase.google.com/');
            print('   2. Select your project');
            print('   3. Go to Build > App Check');
            print('   4. Click on your Android app');
            print('   5. Click "Manage debug tokens"');
            print('   6. Click "Add debug token"');
            print('   7. Paste the token above');
          } else {
            print('⚠️  Debug token not available via API.');
            print('');
            print('📱 The debug token should appear in Android logcat.');
            print('');
            print('   METHOD 1 - Check logcat:');
            print('   Run: adb logcat | Select-String -Pattern "AppCheck|debug.*token"');
            print('');
            print('   METHOD 2 - Android Studio:');
            print('   1. Open Android Studio');
            print('   2. Go to View > Tool Windows > Logcat');
            print('   3. Filter by: "FirebaseAppCheck" or "AppCheck"');
            print('   4. Look for a line containing "debug token"');
            print('   5. The token will be a long UUID-like string');
            print('');
            print('   METHOD 3 - Restart app:');
            print('   Sometimes the token appears after a few seconds.');
            print('   Try closing and reopening the app.');
          }
          print('═══════════════════════════════════════════════════════');
        }
      } else {
        // Production providers
        // Make sure Play Integrity (Android) and DeviceCheck (iOS) are configured in Firebase Console
        await FirebaseAppCheck.instance.activate(
          providerAndroid: AndroidPlayIntegrityProvider(),
          providerApple: AppleDeviceCheckProvider(),
          // For web production, uncomment and configure:
          // providerWeb: ReCaptchaEnterpriseProvider('your-recaptcha-enterprise-site-key'),
        );
        if (kDebugMode) {
          print('App Check initialized with PRODUCTION providers');
        }
      }

      // Set token refresh listener (optional, for monitoring)
      FirebaseAppCheck.instance.onTokenChange.listen((token) {
        if (kDebugMode && token != null) {
          print('App Check token refreshed: $token');
        }
      });

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing App Check: $e');
      }
      // Don't throw - App Check initialization failure shouldn't break the app
    }
  }

  /// Get the current App Check token (optional, for verification)
  Future<String?> getToken() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      return token;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting App Check token: $e');
      }
      return null;
    }
  }

  bool get isInitialized => _isInitialized;
}

