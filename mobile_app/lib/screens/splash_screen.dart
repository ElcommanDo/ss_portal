import 'package:flutter/material.dart';

import '../core/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Image.asset('assets/images/logo_white.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Timesheet',
                style: TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.w600),
              ),
              const Spacer(flex: 2),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
