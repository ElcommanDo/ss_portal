import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final session = Session();
  runApp(
    ChangeNotifierProvider<Session>.value(
      value: session,
      child: const SmartSystemApp(),
    ),
  );
  // restore the saved session after the first frame so the splash shows immediately
  await session.init();
}

class SmartSystemApp extends StatelessWidget {
  const SmartSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.select<Session, AuthState>((s) => s.state);
    final userId = context.select<Session, int?>((s) => s.user?.id);
    Widget child;
    switch (state) {
      case AuthState.loading:
        child = const SplashScreen();
        break;
      case AuthState.signedOut:
        child = const LoginScreen();
        break;
      case AuthState.signedIn:
        // a new key per user rebuilds the whole shell after switching accounts
        child = HomeShell(key: ValueKey('shell-$userId'));
        break;
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: child);
  }
}
