import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/forgot_password_screen.dart';
import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';
import '../maps/pune_map_screen.dart';
import '../screens/home_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/exposure_screen.dart';
import '../screens/station_detail_screen.dart';
import 'app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    // Allow seamless access to Pune air quality data without forced login
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loggingInRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/signup' ||
        state.matchedLocation == '/forgot-password';
    if (loggedIn && loggingInRoute) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
    GoRoute(path: '/exposure', builder: (context, state) => const ExposureScreen()),
    GoRoute(
      path: '/station/:id',
      builder: (context, state) => StationDetailScreen(stationId: state.pathParameters['id']!),
    ),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/explore', builder: (context, state) => const PuneMapScreen()),
        GoRoute(path: '/insights', builder: (context, state) => const InsightsScreen()),
        GoRoute(path: '/alerts', builder: (context, state) => const AlertsScreen()),
        GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      ],
    ),
  ],
);
