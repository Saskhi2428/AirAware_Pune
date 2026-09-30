import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/auth_state_provider.dart';
import '../models/station.dart';
import '../providers/pune_providers.dart';
import '../services/exposure_tracker_service.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';

class PuneMapScreen extends ConsumerStatefulWidget {
  const PuneMapScreen({super.key});

  @override
  ConsumerState<PuneMapScreen> createState() => _PuneMapScreenState();
}

class _PuneMapScreenState extends ConsumerState<PuneMapScreen> {
  static const _puneCenter = LatLng(18.53, 73.85);
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showHotspots = true;
  String _selectedFilter = 'all'; // 'all', 'clean', 'elevated'
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _selectStation(Station station, bool isLoggedIn) {
    _searchFocusNode.unfocus();
    _searchController.text = station.name;
    setState(() => _searchQuery = '');
    _mapController.move(LatLng(station.latitude, station.longitude), 14.5);
    _showStationPreview(context, station, isLoggedIn);
  }

  void _handleSearchSubmit(String query, List<Station> stations, bool isLoggedIn) {
    _searchFocusNode.unfocus();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return;

    Station? match;
    for (final s in stations) {
      if (s.name.toLowerCase().contains(q) || (s.area ?? '').toLowerCase().contains(q)) {
        match = s;
        break;
      }
    }

    if (match != null) {
      _selectStation(match, isLoggedIn);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No Pune monitoring station found for "$query"'),
          backgroundColor: AppColors.surfaceElevated,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final snapshotAsync = ref.watch(mapSnapshotProvider);
    final hotspotsAsync = ref.watch(hotspotsProvider);
    final userPos = ref.watch(deviceLocationProvider).valueOrNull;
    final tracker = ref.watch(exposureTrackerProvider);

    return GradientScaffold(
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.indigo)),
        error: (err, _) => _MapError(
          message: err.toString(),
          onRetry: () => ref.invalidate(mapSnapshotProvider),
        ),
        data: (stations) {
          if (stations.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: GlassCard(
                  child: Text(
                    'No stations registered for Pune region.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            );
          }

          final cleanCount = stations.where((s) => (s.aqiValue ?? 100) <= 80).length;
          final elevatedCount = stations.where((s) => (s.aqiValue ?? 0) > 80).length;

          final q = _searchQuery.toLowerCase().trim();
          final suggestions = q.isEmpty
              ? <Station>[]
              : stations.where((s) {
                  return s.name.toLowerCase().contains(q) || (s.area ?? '').toLowerCase().contains(q);
                }).take(6).toList();

          final filteredStations = stations.where((s) {
            if (q.isNotEmpty) {
              final matchesName = s.name.toLowerCase().contains(q);
              final matchesArea = (s.area ?? '').toLowerCase().contains(q);
              if (!matchesName && !matchesArea) return false;
            }

            if (_selectedFilter == 'clean') {
              return (s.aqiValue ?? 100) <= 80;
            } else if (_selectedFilter == 'elevated') {
              return (s.aqiValue ?? 0) > 80;
            }
            return true;
          }).toList();

          // Build hotspot circles if available
          final circles = <CircleMarker>[];
          if (_showHotspots) {
            final hotspots = (hotspotsAsync.value?['hotspots'] as List?) ?? [];
            for (final h in hotspots) {
              final center = h['center'] as Map<String, dynamic>?;
              if (center != null) {
                final lat = (center['latitude'] as num).toDouble();
                final lng = (center['longitude'] as num).toDouble();
                final radiusKm = (h['radius_km'] as num?)?.toDouble() ?? 2.0;
                final peakAqi = (h['peak_aqi'] as num?)?.toInt() ?? 100;
                final c = peakAqi > 150 ? AppColors.aqiPoor : AppColors.aqiModerate;

                circles.add(
                  CircleMarker(
                    point: LatLng(lat, lng),
                    radius: radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: c.withValues(alpha: 0.18),
                    borderColor: c.withValues(alpha: 0.6),
                    borderStrokeWidth: 2,
                  ),
                );
              }
            }
          }

          // Build markers: User GPS position + official stations
          final markers = <Marker>[];
          if (userPos != null) {
            markers.add(
              Marker(
                point: LatLng(userPos.latitude, userPos.longitude),
                width: 50,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.indigo,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ),
            );
          }

          for (final s in filteredStations) {
            markers.add(_buildMarker(context, ref, s, user != null));
          }

          final reports = ref.watch(citizenReportsProvider).valueOrNull ?? [];
          for (final rep in reports) {
            final lat = (rep['latitude'] as num?)?.toDouble();
            final lng = (rep['longitude'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              final cat = rep['category']?.toString() ?? 'Pollution Incident';
              final ward = rep['ward']?.toString() ?? 'Pune';
              final desc = rep['description']?.toString() ?? '';
              markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () {
                      _searchFocusNode.unfocus();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('AirWatch Incident: $cat • $ward\n$desc'),
                          backgroundColor: AppColors.surfaceElevated,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.aqiPoor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.report_problem_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              );
            }
          }

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _puneCenter,
                  initialZoom: 11.5,
                  minZoom: 9.0,
                  maxZoom: 17.0,
                  onTap: (_, __) {
                    if (_searchFocusNode.hasFocus) {
                      _searchFocusNode.unfocus();
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'in.airaware.app',
                  ),
                  if (circles.isNotEmpty) CircleLayer(circles: circles),
                  MarkerLayer(markers: markers),
                  const RichAttributionWidget(
                    attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                  ),
                ],
              ),

              // Search bar, suggestions, and filter chips floating at top
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Modern Floating Search Bar with Hotspot toggle & actions
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: AppColors.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 8, right: 6),
                            child: Icon(Icons.search_rounded, color: AppColors.violet, size: 22),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(
                                hintText: 'Search Pune locality (e.g. Pashan, Hinjawadi)...',
                                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                              onSubmitted: (query) => _handleSearchSubmit(query, stations, user != null),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                          Container(
                            height: 22,
                            width: 1,
                            color: AppColors.borderSubtle,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          IconButton(
                            icon: Icon(
                              _showHotspots ? Icons.bubble_chart_rounded : Icons.bubble_chart_outlined,
                              color: _showHotspots ? AppColors.violet : AppColors.textMuted,
                              size: 22,
                            ),
                            tooltip: _showHotspots ? 'Hide Pollution Hotspots' : 'Show Pollution Hotspots',
                            onPressed: () => setState(() => _showHotspots = !_showHotspots),
                          ),
                        ],
                      ),
                    ),

                    // Interactive Suggestions Dropdown
                    if (_searchQuery.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 240),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.borderSubtle),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: suggestions.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.search_off_rounded, color: AppColors.textMuted, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'No Pune stations found matching "$_searchQuery"',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: suggestions.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderSubtle),
                                  itemBuilder: (ctx, idx) {
                                    final s = suggestions[idx];
                                    final col = s.hasCurrentAqi
                                        ? AppColors.colorForAqiCategory(s.aqiCategory)
                                        : AppColors.aqiUnavailable;
                                    return ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      leading: CircleAvatar(
                                        radius: 13,
                                        backgroundColor: col.withValues(alpha: 0.2),
                                        child: Icon(Icons.location_on_rounded, color: col, size: 15),
                                      ),
                                      title: Text(
                                        s.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                                      ),
                                      subtitle: Text(
                                        '${s.area ?? "Pune Region"} • ${s.locationTypeLabel}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: col.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: col.withValues(alpha: 0.6)),
                                        ),
                                        child: Text(
                                          s.hasCurrentAqi ? '${s.aqiValue} AQI' : '–',
                                          style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 11),
                                        ),
                                      ),
                                      onTap: () => _selectStation(s, user != null),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Filter chips row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('All (${stations.length})', 'all'),
                          const SizedBox(width: 8),
                          _filterChip('Clean ($cleanCount)', 'clean'),
                          const SizedBox(width: 8),
                          _filterChip('Elevated ($elevatedCount)', 'elevated'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Floating Exposure Tracker Button (Bottom Left)
              Positioned(
                bottom: 96,
                left: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'map_exposure_fab',
                  backgroundColor: AppColors.surfaceElevated,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: tracker.isTracking ? AppColors.aqiGood : AppColors.borderSubtle,
                      width: tracker.isTracking ? 1.8 : 1.0,
                    ),
                  ),
                  icon: Icon(
                    tracker.isTracking ? Icons.directions_walk_rounded : Icons.directions_walk_outlined,
                    color: tracker.isTracking ? AppColors.aqiGood : AppColors.violet,
                    size: 20,
                  ),
                  label: Text(
                    tracker.isTracking
                        ? 'Tracking (${tracker.elapsedTimeString})'
                        : 'Exposure Tracker',
                    style: TextStyle(
                      color: tracker.isTracking ? AppColors.aqiGood : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () => context.push('/exposure'),
                ),
              ),

              // Recenter map button (Bottom Right)
              Positioned(
                bottom: 96,
                right: 16,
                child: FloatingActionButton.small(
                  backgroundColor: AppColors.surfaceElevated,
                  onPressed: () {
                    if (userPos != null) {
                      _mapController.move(LatLng(userPos.latitude, userPos.longitude), 13.0);
                    } else {
                      _mapController.move(_puneCenter, 11.5);
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, color: AppColors.violet),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    final sel = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppColors.indigo : AppColors.surfaceElevated.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? AppColors.violet : AppColors.borderSubtle),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Marker _buildMarker(BuildContext context, WidgetRef ref, Station station, bool isLoggedIn) {
    final color = station.hasCurrentAqi
        ? AppColors.colorForAqiCategory(station.aqiCategory)
        : AppColors.aqiUnavailable;

    return Marker(
      point: LatLng(station.latitude, station.longitude),
      width: 46,
      height: 46,
      child: GestureDetector(
        onTap: () {
          _searchFocusNode.unfocus();
          _showStationPreview(context, station, isLoggedIn);
        },
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))],
          ),
          alignment: Alignment.center,
          child: Text(
            station.hasCurrentAqi ? '${station.aqiValue}' : '–',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
    );
  }

  void _showStationPreview(BuildContext context, Station station, bool isLoggedIn) {
    final color = station.hasCurrentAqi
        ? AppColors.colorForAqiCategory(station.aqiCategory)
        : AppColors.aqiUnavailable;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                station.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                station.area ?? 'Pune Region',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color),
                          ),
                          child: Text(
                            station.hasCurrentAqi ? '${station.aqiValue} AQI' : '– AQI',
                            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _previewPill('Category', station.aqiCategory ?? 'Unknown', color),
                        const SizedBox(width: 8),
                        _previewPill('Dominant', (station.dominantPollutant ?? 'PM2.5').toUpperCase(), AppColors.violet),
                        const SizedBox(width: 8),
                        _previewPill('Source', station.locationTypeLabel, AppColors.aqiGood),
                      ],
                    ),
                    if (station.lastObservationAt != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Observed: ${station.lastObservationAt!.toLocal().hour.toString().padLeft(2, '0')}:${station.lastObservationAt!.toLocal().minute.toString().padLeft(2, '0')} • Freshness: ${station.freshness.toUpperCase()}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Embedded 24h Sparkline preview
                    _StationSparkline(stationId: station.id, aqiColor: color),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              context.push('/station/${station.id}');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.indigo,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.analytics_outlined, color: Colors.white, size: 16),
                            label: const Text('Full Analytics', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Cleaner route here',
                          icon: const Icon(Icons.directions_rounded, color: AppColors.violet),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderSubtle)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/exposure', extra: station.name);
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Share station report',
                          icon: const Icon(Icons.share_outlined, color: AppColors.violet),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderSubtle)),
                          ),
                          onPressed: () {
                            Share.share(
                              '🌿 AirAware Pune — Map Intelligence\n\n'
                              '📍 Station: ${station.name} (${station.area ?? "Pune"})\n'
                              '📊 Current AQI: ${station.aqiValue ?? "—"} (${station.aqiCategory ?? "Standard"})\n'
                              '🔬 Primary Pollutant: ${(station.dominantPollutant ?? "PM2.5").toUpperCase()}\n'
                              '🕒 Real-time Pune Urban Sensor Telemetry\n\n'
                              'Track Pune air quality live on AirAware 🌍',
                              subject: 'AirAware Pune: ${station.name} Air Quality',
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Bookmark station',
                          icon: const Icon(Icons.bookmark_add_outlined, color: AppColors.violet),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderSubtle)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (!isLoggedIn) {
                              showDialog(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  backgroundColor: AppColors.surfaceElevated,
                                  title: const Text('Sign In Required', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  content: const Text(
                                    'Sign in to save this Pune monitoring station to your personal dashboard.',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(dCtx);
                                        context.push('/login');
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
                                      child: const Text('Sign In', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              final label = station.area ?? station.name.split(',')[0];
                              ref.read(savedLocationsProvider.notifier).addLocation(label, station.latitude, station.longitude);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Added "$label" to your saved places!')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPill(String label, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            const SizedBox(height: 2),
            Text(val, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _StationSparkline extends ConsumerWidget {
  final String stationId;
  final Color aqiColor;
  const _StationSparkline({required this.stationId, required this.aqiColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(stationHistoryProvider((stationId: stationId, range: '24h')));

    return historyAsync.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.indigo))),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (histData) {
        if (histData.isEmpty) return const SizedBox.shrink();

        final spots = <FlSpot>[];
        for (int i = 0; i < histData.length; i++) {
          final val = (histData[i]['aqi_value'] as num).toDouble();
          spots.add(FlSpot(i.toDouble(), val));
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('24-Hour Trend Sparkline', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('CPCB NAQI', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 50,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    minX: 0,
                    maxX: (spots.length - 1).toDouble(),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: aqiColor,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: aqiColor.withValues(alpha: 0.15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MapError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_rounded, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 14),
              const Text('Could not load Pune map stations',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
