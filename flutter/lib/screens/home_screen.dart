import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_state_provider.dart';
import '../providers/pune_providers.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';
import '../widgets/ai_assistant_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stationsAsync = ref.watch(stationsProvider);
    final pulseAsync = ref.watch(punePulseProvider);
    final liveStationAsync = ref.watch(userNearestStationProvider);
    final savedLocationsAsync = ref.watch(savedLocationsProvider);
    final advisorAsync = ref.watch(activityAdvisorProvider);
    final reportsAsync = ref.watch(citizenReportsProvider);

    return GradientScaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.indigo,
          backgroundColor: AppColors.surfaceElevated,
          onRefresh: () async {
            ref.invalidate(punePulseProvider);
            ref.invalidate(userNearestStationProvider);
            ref.invalidate(savedLocationsProvider);
            ref.invalidate(activityAdvisorProvider);
            ref.invalidate(citizenReportsProvider);
            await ref.read(stationsProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // 1. TOP HEADER (Adaptive for Guest vs Authenticated)
              SliverToBoxAdapter(child: _HomeHeader(user: user)),

              // 2. LIVE USER LOCATION AIR QUALITY HERO CARD
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: liveStationAsync.when(
                    loading: () => const _LiveCardSkeleton(),
                    error: (err, _) => _LiveCardFallback(error: err.toString()),
                    data: (data) => _LiveLocationCard(data: data, isLoggedIn: user != null),
                  ),
                ),
              ),

              // 3. ASK AI ASSISTANT PROMPT CARD
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: _AiAssistantBanner(),
                ),
              ),

              // 4. CLEANER ROUTE COMMUTE CARD
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: _CleanRouteBanner(),
                ),
              ),

              // 5. PUNE CITY AIR PULSE BANNER
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: pulseAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (pulse) => _PuneAirPulseBanner(pulse: pulse),
                  ),
                ),
              ),

              // 6. DIURNAL ACTIVITY ADVISOR WINDOW
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: advisorAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (advisor) => _ActivityAdvisorCard(advisor: advisor),
                  ),
                ),
              ),

              // 7. COMMUNITY POLLUTION WATCH SUMMARY
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: reportsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (reports) => _CommunityWatchCard(reportsCount: reports.length),
                  ),
                ),
              ),

              // 8. SAVED PLACES SECTION
              SliverToBoxAdapter(
                child: _SavedPlacesSection(
                  isLoggedIn: user != null,
                  savedPlacesAsync: savedLocationsAsync,
                ),
              ),

              // 9. PUNE STATIONS LEADERBOARD
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Pune Stations Leaderboard',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => context.go('/explore'),
                        icon: const Icon(Icons.map_outlined, size: 16, color: AppColors.indigo),
                        label: const Text('View Map', style: TextStyle(fontSize: 13, color: AppColors.indigo)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: stationsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(color: AppColors.indigo),
                      ),
                    ),
                  ),
                  error: (err, _) => SliverToBoxAdapter(
                    child: GlassCard(
                      child: Text('Error loading stations: $err', style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  ),
                  data: (stations) {
                    final valid = stations.where((s) => s.hasCurrentAqi).toList()
                      ..sort((a, b) => (a.aqiValue ?? 0).compareTo(b.aqiValue ?? 0));
                    if (valid.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final st = valid[index];
                          final rank = index + 1;
                          final color = AppColors.colorForAqiCategory(st.aqiCategory);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () => context.push('/station/${st.id}'),
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: rank <= 3 ? AppColors.indigo.withValues(alpha: 0.25) : AppColors.surfaceElevated,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '#$rank',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: rank <= 3 ? AppColors.violet : AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            st.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            st.area ?? 'Pune Region',
                                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: color.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            '${st.aqiValue} AQI',
                                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          st.aqiCategory ?? '',
                                          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: valid.length,
                      ),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  final dynamic user;
  const _HomeHeader({required this.user});

  void _sharePulse(BuildContext context, WidgetRef ref) {
    final live = ref.read(userNearestStationProvider).valueOrNull;
    final st = live?['nearest_station'] as Map<String, dynamic>? ?? {};
    final aqi = st['aqi_value'] ?? 85;
    final category = st['aqi_category'] ?? 'Satisfactory';
    final dominant = (st['dominant_pollutant'] ?? 'PM2.5').toString().toUpperCase();
    final name = st['name'] ?? 'Pune Urban Network';
    final area = st['area'] ?? 'Pune';

    Share.share(
      '🌿 AirSense Pune — Live City Air Advisory\n\n'
      '📍 Reference Locality: $name ($area)\n'
      '📊 Current AQI: $aqi ($category)\n'
      '🔬 Dominant Pollutant: $dominant\n'
      '💡 Standard: CPCB National Air Quality Index (NAQI) 🇮🇳\n'
      '🕒 Verified Real-Time Telemetry\n\n'
      'Stay informed and protect your respiratory health with AirSense Pune 🌍',
      subject: 'Pune Air Quality Advisory ($aqi AQI)',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient(),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: AppColors.indigo.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.air_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AIRAWare',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5, color: AppColors.textPrimary),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: AppColors.aqiGood, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Pune Urban Network • LIVE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.aqiGood),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.share_outlined, color: AppColors.textMuted, size: 20),
                tooltip: 'Share Pune air advisory',
                onPressed: () => _sharePulse(context, ref),
              ),
              if (user == null)
                ElevatedButton(
                  onPressed: () => context.push('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.violet,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderSubtle)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Sign In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                )
              else
                IconButton(
                  icon: const Icon(Icons.tune_rounded, color: AppColors.textMuted),
                  onPressed: () => context.go('/profile'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveLocationCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  final bool isLoggedIn;
  const _LiveLocationCard({required this.data, required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = data['nearest_station'] as Map<String, dynamic>? ?? {};
    final aqi = st['aqi_value'] as int? ?? 85;
    final category = st['aqi_category'] as String? ?? 'Satisfactory';
    final dominant = st['dominant_pollutant'] as String? ?? 'PM2.5';
    final distance = st['distance_km'] != null ? '${st['distance_km']} km away' : 'Nearby';
    final stationName = st['name'] as String? ?? 'Pune Central';
    final stationArea = st['area'] as String? ?? 'Pune';
    final stationId = st['id'] as String?;
    final transparencyNote = data['transparency_note'] as String? ?? 'Direct measurement';
    final isGps = data['is_gps'] == true;
    final isMeasured = data['data_classification'] == 'measured_station';

    final color = AppColors.colorForAqiCategory(category);

    return GlassCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.22), AppColors.surface],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isGps ? AppColors.indigo.withValues(alpha: 0.25) : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isGps ? AppColors.violet.withValues(alpha: 0.5) : AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGps ? Icons.my_location_rounded : Icons.location_city_rounded,
                        size: 11,
                        color: isGps ? AppColors.violet : AppColors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          isGps ? 'GPS LOCATION' : 'PUNE REFERENCE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: isGps ? Colors.white : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      Share.share(
                        '🌿 AirSense Pune — Live Local Air Quality\n\n'
                        '📍 Location: $stationName ($stationArea) • $distance\n'
                        '📊 Current AQI: $aqi ($category)\n'
                        '🔬 Dominant Pollutant: $dominant\n'
                        '💡 Status: $transparencyNote\n'
                        '🕒 Verified Pune Urban Network Telemetry\n\n'
                        'Stay protected with AirSense Pune 🌍',
                        subject: 'AirSense Pune: $stationName ($aqi AQI)',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const Icon(Icons.share_outlined, size: 14, color: AppColors.textMuted),
                    ),
                  ),
                  if (stationId != null) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => context.push('/station/$stationId'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Details', style: TextStyle(fontSize: 11, color: AppColors.violet, fontWeight: FontWeight.w700)),
                            SizedBox(width: 3),
                            Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.violet),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: aqi.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  value.round().toString(),
                  style: TextStyle(fontSize: 62, fontWeight: FontWeight.w800, color: color, height: 1),
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        category,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Dominant: $dominant', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Nearest Station Row (tappable to station detail)
          GestureDetector(
            onTap: () {
              if (stationId != null) context.push('/station/$stationId');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sensors_rounded, size: 15, color: AppColors.violet),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nearest: $stationName ($stationArea) • $distance',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isMeasured ? AppColors.aqiGood : AppColors.aqiModerate,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  transparencyNote,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiAssistantBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AiAssistantDialog.show(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.indigo.withValues(alpha: 0.25), AppColors.surfaceElevated],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient(),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pune Air AI Assistant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('Ask about running, N95 masks, or any Pune area...',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.violet),
          ],
        ),
      ),
    );
  }
}

class _CleanRouteBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/exposure'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.aqiGood.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.alt_route_rounded, color: AppColors.aqiGood, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cleaner Route Commute', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('Reduce inhaled PM2.5 by up to 26% across Pune corridors',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CommunityWatchCard extends StatelessWidget {
  final int reportsCount;
  const _CommunityWatchCard({required this.reportsCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.aqiModerate.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign_rounded, color: AppColors.aqiModerate, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    const Text('Community Watch', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.aqiModerate.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$reportsCount Active', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.aqiModerate)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Garbage burning & dust reports across PMC/PCMC',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => context.go('/alerts'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(40, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('View', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _PuneAirPulseBanner extends StatelessWidget {
  final Map<String, dynamic> pulse;
  const _PuneAirPulseBanner({required this.pulse});

  @override
  Widget build(BuildContext context) {
    final avgAqi = pulse['average_aqi'] ?? 85;
    final category = pulse['city_category'] ?? 'Satisfactory';
    final cleanest = pulse['cleanest_area'] as Map<String, dynamic>? ?? {};
    final worst = pulse['most_polluted_area'] as Map<String, dynamic>? ?? {};
    final color = AppColors.colorForAqiCategory(category);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: AppColors.indigo, size: 18),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text('Pune City Air Pulse', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text('City Avg: $avgAqi', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.eco_rounded, size: 13, color: AppColors.aqiGood),
                          SizedBox(width: 4),
                          Text('Cleanest Zone', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(cleanest['name'] ?? 'Pashan', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('${cleanest['aqi'] ?? 45} AQI', style: const TextStyle(color: AppColors.aqiGood, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.aqiPoor),
                          SizedBox(width: 4),
                          Text('Pollution Peak', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(worst['name'] ?? 'Bhosari MIDC', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('${worst['aqi'] ?? 142} AQI', style: const TextStyle(color: AppColors.aqiPoor, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityAdvisorCard extends ConsumerWidget {
  final Map<String, dynamic> advisor;
  const _ActivityAdvisorCard({required this.advisor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePersona = ref.watch(activeHealthPersonaProvider);
    final baseGuidance = advisor['activity_guidance'] as String? ?? 'Conditions are suitable for outdoor exercise.';
    final maskRec = advisor['mask_recommended'] == true;
    final windows = (advisor['optimal_windows'] as List?) ?? [];
    final morning = windows.isNotEmpty ? windows.first as Map<String, dynamic> : null;

    String customizedGuidance = baseGuidance;
    if (activePersona.contains('Asthma')) {
      customizedGuidance = 'Asthmatic Guidance: Particulate dispersion is moderate. Keep quick-relief inhaler handy; avoid active cardio along heavy traffic corridors.';
    } else if (activePersona.contains('Senior')) {
      customizedGuidance = 'Senior Advisory: Air is favorable for gentle morning walks in garden parks; stay hydrated and avoid congested junction roads.';
    } else if (activePersona.contains('Athlete')) {
      customizedGuidance = 'Athlete Advisory: Optimal outdoor workout window is before morning rush hour (06:00 - 07:30 AM). High ventilation rates recommend green tracks.';
    } else if (activePersona.contains('Child')) {
      customizedGuidance = 'Child Safety: Outdoor school playground activities are safe today. Ensure clean indoor ventilation during afternoon peak temperature.';
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.directions_run_rounded, color: AppColors.violet, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Outdoor Health Advisor • $activePersona', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (maskRec || activePersona.contains('Asthma'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.aqiPoor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.aqiPoor),
                  ),
                  child: const Text('Mask Recommended', style: TextStyle(color: AppColors.aqiPoor, fontSize: 10, fontWeight: FontWeight.w700)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.aqiGood.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.aqiGood),
                  ),
                  child: const Text('Mask Optional', style: TextStyle(color: AppColors.aqiGood, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            customizedGuidance,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          if (morning != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wb_sunny_rounded, size: 14, color: AppColors.aqiGood),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Best Window: ${morning['recommended_time']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.aqiGood)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedPlacesSection extends StatelessWidget {
  final bool isLoggedIn;
  final AsyncValue<List<Map<String, dynamic>>> savedPlacesAsync;

  const _SavedPlacesSection({required this.isLoggedIn, required this.savedPlacesAsync});

  @override
  Widget build(BuildContext context) {
    if (!isLoggedIn) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bookmark_border_rounded, color: AppColors.violet, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Save Your Pune Places', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    const Text(
                      'Sign in to bookmark Home, Office, or College for one-tap air monitoring.',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => context.push('/login'),
                      child: const Text(
                        'Sign In to Add Places →',
                        style: TextStyle(fontSize: 12, color: AppColors.violet, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Saved Places',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              TextButton.icon(
                onPressed: () => context.go('/profile'),
                icon: const Icon(Icons.tune_rounded, size: 16, color: AppColors.violet),
                label: const Text('Manage', style: TextStyle(fontSize: 13, color: AppColors.violet)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 124,
          child: savedPlacesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.indigo)),
            error: (_, __) => const SizedBox.shrink(),
            data: (places) {
              if (places.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassCard(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_location_alt_outlined, color: AppColors.violet, size: 20),
                          const SizedBox(width: 8),
                          const Text('No saved places yet.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => context.go('/profile'),
                            child: const Text('Add Place', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _SavedPlaceCard(place: places[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SavedPlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  const _SavedPlaceCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final label = place['label'] ?? 'Place';
    final aqi = place['aqi_value'] as int? ?? 80;
    final cat = place['aqi_category'] as String? ?? 'Satisfactory';
    final color = AppColors.colorForAqiCategory(cat);

    IconData icon;
    if (label.toLowerCase().contains('home')) {
      icon = Icons.home_rounded;
    } else if (label.toLowerCase().contains('college') || label.toLowerCase().contains('university')) {
      icon = Icons.school_rounded;
    } else if (label.toLowerCase().contains('office') || label.toLowerCase().contains('work')) {
      icon = Icons.business_rounded;
    } else {
      icon = Icons.pin_drop_rounded;
    }

    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: AppColors.violet),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                child: Text('$aqi AQI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(cat, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveCardSkeleton extends StatelessWidget {
  const _LiveCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator(color: AppColors.indigo)),
      ),
    );
  }
}

class _LiveCardFallback extends StatelessWidget {
  final String error;
  const _LiveCardFallback({required this.error});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pune City Baseline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('GPS location unavailable. Showing Pune metropolitan average.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          Text(error, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }
}
