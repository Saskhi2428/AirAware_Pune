import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

/// Used ONLY for nav destinations whose backend + data pipeline haven't been
/// built yet in the phased rollout. This never shows a fake number or fake
/// chart — it's honest about build stage, styled to match the rest of the
/// premium UI instead of looking like a bare "under construction" page.
class PendingPhaseScreen extends StatelessWidget {
  final String title;
  final String phaseNote;
  const PendingPhaseScreen({super.key, required this.title, required this.phaseNote});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(gradient: AppColors.brandGradient(opacity: 0.25), shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome_rounded, size: 30, color: AppColors.violet),
                ),
                const SizedBox(height: 20),
                Text('$title is coming soon', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(phaseNote, textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, height: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
