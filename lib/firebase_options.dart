import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FirebaseOptionsManual {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static FirebaseOptions web = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY']!,
    appId: "1:911608784405:web:209c055c9515c2a735101c",
    messagingSenderId: "911608784405",
    projectId: 'floovia',
    authDomain: 'floovia.firebaseapp.com', // Add this
  );

  static FirebaseOptions android = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY']!,
    appId: "1:911608784405:android:1:911608784405:android:72e2ed6a671ee04c35101c",
    messagingSenderId: "911608784405",
    projectId: 'floovia',
  );

  static FirebaseOptions ios = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY']!,
    appId: "1:911608784405:ios:1:911608784405:ios:6656c4e30501763135101c", // Get from Firebase Console
    messagingSenderId: "911608784405",
    projectId: 'floovia',
    iosBundleId: 'com.yourcompany.floovia',
  );
}