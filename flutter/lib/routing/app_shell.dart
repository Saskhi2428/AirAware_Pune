import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/', '/explore', '/insights', '/alerts', '/profile'];
  static const _icons = [Icons.home_rounded, Icons.map_rounded, Icons.insights_rounded, Icons.notifications_rounded, Icons.person_rounded];
  static const _outlineIcons = [Icons.home_outlined, Icons.map_outlined, Icons.insights_outlined, Icons.notifications_outlined, Icons.person_outline_rounded];
  static const _labels = ['Home', 'Explore', 'Insights', 'Alerts', 'Profile'];

  int _indexForLocation(String location) {
    if (location.startsWith('/explore')) return 1;
    if (location.startsWith('/insights')) return 2;
    if (location.startsWith('/alerts')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);

    return GradientScaffold(
      body: child,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_tabs.length, (i) {
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => context.go(_tabs[i]),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.brandGradient(opacity: 0.85) : null,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(selected ? _icons[i] : _outlineIcons[i],
                            size: 21, color: selected ? Colors.white : AppColors.textMuted),
                        const SizedBox(height: 2),
                        Text(_labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppColors.textMuted,
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
