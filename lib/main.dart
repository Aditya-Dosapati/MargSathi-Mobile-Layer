import 'package:flutter/material.dart';
import 'features/auth/screens/login_page.dart';
import 'features/home/screens/home_page.dart';
import 'features/home/screens/profile_page.dart';
import 'features/parking/screens/parking_prediction_page.dart';
import 'features/routing/screens/smart_routing_page.dart';
import 'features/shared/theme/app_theme.dart';
import 'features/sign_translation/screens/sign_translation_page.dart';

void main() {
  runApp(const MargSathiApp());
}

class MargSathiApp extends StatelessWidget {
  const MargSathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MargSathi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/profile': (context) => const ProfilePage(),
        '/smart-routing': (context) => const SmartRoutingPage(),
        '/parking': (context) => const ParkingPredictionPage(),
        '/sign-translation': (context) => const SignTranslationPage(),
      },
    );
  }
}
