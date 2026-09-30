import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state_provider.dart';
import '../providers/pune_providers.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';


class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  double _thresholdAqi = 150.0;
  bool _morningBrief = true;
  bool _eveningCommute = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final reportsAsync = ref.watch(citizenReportsProvider);
    final pulseAsync = ref.watch(punePulseProvider);

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Pune Alerts & AirWatch'),
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.indigo,
          onRefresh: () async {
            ref.invalidate(citizenReportsProvider);
            ref.invalidate(punePulseProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
            children: [
              // 1. ACTIVE CITY-WIDE ADVISORY BANNER (Public)
              pulseAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (pulse) {
                  final cat = pulse['city_category'] ?? 'Satisfactory';
                  final color = AppColors.colorForAqiCategory(cat);
                  return GlassCard(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color.withValues(alpha: 0.2), AppColors.surface],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: Icon(Icons.notifications_active_rounded, color: color, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Active City Advisory: $cat Air', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                pulse['health_guidance'] ?? 'Normal outdoor activities permitted across Pune.',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // 2. PERSONAL AQI TRIGGER ALERT (Auth Guarded vs Interactive)
              if (user == null) ...[
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: AppColors.indigo.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.lock_outline_rounded, color: AppColors.violet, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Personal AQI Trigger Alerts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                SizedBox(height: 2),
                                Text('Sign in to configure personal spike notifications', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Receive instant notifications when your nearest Pune station crosses your customized AQI threshold (e.g. >120 for sensitive groups), plus daily 8:00 AM commute advisories.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.push('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.indigo,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Sign In to Enable Alerts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Personal AQI Trigger Alert', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      const Text('Receive instant notification when your nearest Pune station crosses this threshold.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Notify me above:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.colorForAqiCategory(_thresholdAqi > 200 ? 'Poor' : 'Moderate').withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${_thresholdAqi.round()} AQI', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                          ),
                        ],
                      ),
                      Slider(
                        value: _thresholdAqi,
                        min: 50,
                        max: 300,
                        divisions: 5,
                        activeColor: AppColors.indigo,
                        inactiveColor: AppColors.surfaceElevated,
                        onChanged: (val) => setState(() => _thresholdAqi = val),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Morning Commute Briefing (8:00 AM)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        value: _morningBrief,
                        activeColor: AppColors.indigo,
                        onChanged: (v) => setState(() => _morningBrief = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Evening Transit Advisory (5:30 PM)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        value: _eveningCommute,
                        activeColor: AppColors.indigo,
                        onChanged: (v) => setState(() => _eveningCommute = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await ref.read(userAlertsProvider.notifier).saveAlert(
                                  thresholdValue: _thresholdAqi,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Threshold saved: Alert when AQI > ${_thresholdAqi.round()}'),
                                      backgroundColor: AppColors.indigo,
                                    ),
                                  );
                                }

                                // Check current station against saved threshold immediately
                                final nearestData = ref.read(userNearestStationProvider).valueOrNull;
                                final st = nearestData?['nearest_station'] as Map<String, dynamic>?;
                                if (st != null && st['aqi_value'] != null) {
                                  final aqi = (st['aqi_value'] as num).toInt();
                                  final name = st['name']?.toString() ?? 'Pune';
                                  if (aqi >= _thresholdAqi) {
                                    await NotificationService.instance.showAqiAlert(
                                      title: '⚠️ Alert: $name AQI is $aqi',
                                      body: 'Ambient AQI at $name ($aqi) already exceeds your safety threshold of ${_thresholdAqi.round()} AQI.',
                                      aqi: aqi,
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
                              label: const Text('Save Trigger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.indigo,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await NotificationService.instance.showAqiAlert(
                                title: '🔔 AirAware Pune: Test Alert',
                                body: 'Live local notification verified! You will receive push alerts when Pune AQI exceeds ${_thresholdAqi.round()}.',
                                aqi: _thresholdAqi.round(),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Test notification dispatched to Android notification tray.'),
                                    backgroundColor: AppColors.surfaceElevated,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.notifications_active_outlined, size: 16, color: AppColors.violet),
                            label: const Text('Test Alert', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.borderSubtle),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 3. CITIZEN AIRWATCH (COMMUNITY INCIDENTS)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Citizen AirWatch Feed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ElevatedButton.icon(
                    onPressed: () => _showReportDialog(context, user != null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 14, color: Colors.white),
                    label: const Text('Report Incident', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              reportsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: AppColors.indigo),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Error loading reports: $e', style: const TextStyle(color: AppColors.textMuted)),
                  ),
                ),
                data: (reports) {
                  if (reports.isEmpty) {
                    return GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.aqiGood.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded, color: AppColors.aqiGood, size: 26),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Active Pollution Incidents',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'The citizen watch feed is clean in your area right now. If you observe garbage burning, construction dust, or industrial emissions, report it below to alert Pune citizens and authorities.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showReportDialog(context, user != null),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.indigo,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.report_gmailerrorred_rounded, size: 16, color: Colors.white),
                            label: const Text('Report Incident Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: reports.map((r) {
                      final reportId = r['id']?.toString() ?? '';
                      final ward = r['ward'] ?? 'Pune';
                      final cat = r['category'] ?? 'Smoke/Dust';
                      final desc = r['description'] ?? '';
                      final status = r['status'] ?? 'Under Review';
                      final votes = r['votes'] ?? 1;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(Icons.report_problem_rounded, color: AppColors.aqiPoor, size: 16),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '$cat • $ward',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(6)),
                                    child: Text(status, style: const TextStyle(fontSize: 10, color: AppColors.violet, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      if (reportId.isNotEmpty) {
                                        await ref.read(citizenReportsProvider.notifier).voteReport(reportId);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Thank you! Incident confirmed with your upvote.'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceElevated,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.thumb_up_alt_outlined, size: 13, color: AppColors.violet),
                                          const SizedBox(width: 4),
                                          Text('$votes confirms', style: const TextStyle(fontSize: 11, color: AppColors.violet, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context, bool isLoggedIn) {
    final wardCtrl = TextEditingController(text: 'Kothrud');
    final descCtrl = TextEditingController();
    String category = 'Garbage Burning';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Report Air Quality Incident', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: category,
                isExpanded: true,
                dropdownColor: AppColors.surfaceElevated,
                decoration: const InputDecoration(labelText: 'Incident Type', border: OutlineInputBorder()),
                items: ['Garbage Burning', 'Construction Dust', 'Industrial Emissions', 'Vehicular Smoke'].map((c) {
                  return DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDlgState(() => category = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: wardCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Ward / Area (e.g. Wakad, Bhosari)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final ward = wardCtrl.text.trim();
                      final desc = descCtrl.text.trim();
                      if (ward.isEmpty || desc.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please provide area and description.')),
                        );
                        return;
                      }

                      setDlgState(() => isSubmitting = true);
                      try {
                        final pos = ref.read(deviceLocationProvider).valueOrNull;
                        await ref.read(citizenReportsProvider.notifier).submitReport(
                          ward,
                          category,
                          desc,
                          latitude: pos?.latitude,
                          longitude: pos?.longitude,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Incident reported and submitted to Pune database.'),
                              backgroundColor: AppColors.indigo,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Submission error: $e')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

}
