import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../auth/auth_state_provider.dart';
import '../providers/pune_providers.dart';
import '../theme/app_theme.dart';
import '../theme/gradient_scaffold.dart';


class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _authService = AuthService();
  final String _selectedRole = 'user'; // 'user', 'researcher', 'admin'
  bool _morningBrief = true;
  bool _spikeAlerts = true;
  bool _asthmaSensitivity = false;
  bool _outdoorAthlete = true;
  void _showEditProfileDialog(BuildContext context, User user) {

    final currentName = user.userMetadata?['full_name'] as String? ??
        (user.email?.split('@')[0].replaceAll('.', ' ') ?? 'Pune Citizen');
    final nameCtrl = TextEditingController(text: currentName);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Account Email: ${user.email ?? ""}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final newName = nameCtrl.text.trim();
                      if (newName.isEmpty) return;

                      setDlgState(() => isSaving = true);
                      try {
                        final sb = Supabase.instance.client;
                        await sb.from('profiles').upsert({
                          'id': user.id,
                          'full_name': newName,
                          'email': user.email ?? '',
                          'updated_at': DateTime.now().toUtc().toIso8601String(),
                        });

                        await sb.auth.updateUser(
                          UserAttributes(data: {'full_name': newName}),
                        );

                        ref.invalidate(currentUserProvider);

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully!'),
                              backgroundColor: AppColors.indigo,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update error: $e')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Are you sure you want to sign out? You will return to guest mode and your personalized saved places will be protected.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.signOut();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out successfully. Switched to Guest Mode.')),
                );
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.aqiPoor),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePlace(BuildContext context, String id, String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Remove Saved Place', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to remove "$label" from your saved places?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(savedLocationsProvider.notifier).removeLocation(id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed "$label"')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.aqiPoor),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddPlaceDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final localities = [
      {'name': 'Kothrud', 'lat': 18.5074, 'lng': 73.8077},
      {'name': 'SPPU / University', 'lat': 18.5529, 'lng': 73.8260},
      {'name': 'Hinjawadi Phase 1', 'lat': 18.5913, 'lng': 73.7389},
      {'name': 'Hadapsar / Magarpatta', 'lat': 18.5167, 'lng': 73.9298},
      {'name': 'Viman Nagar', 'lat': 18.5679, 'lng': 73.9143},
      {'name': 'Aundh', 'lat': 18.5580, 'lng': 73.8073},
      {'name': 'Wakad', 'lat': 18.5987, 'lng': 73.7688},
      {'name': 'Bhosari MIDC', 'lat': 18.6277, 'lng': 73.8471},
      {'name': 'Shivajinagar', 'lat': 18.5314, 'lng': 73.8446},
    ];
    Map<String, dynamic> selectedLoc = localities[0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Add Saved Place in Pune', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Custom Label (e.g. My Flat, Office, Study)',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selectedLoc,
                dropdownColor: AppColors.surfaceElevated,
                decoration: const InputDecoration(labelText: 'Pune Locality', border: OutlineInputBorder()),
                items: localities.map((loc) {
                  return DropdownMenuItem(
                    value: loc,
                    child: Text(loc['name'] as String, style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDlgState(() => selectedLoc = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final label = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : (selectedLoc['name'] as String);
                ref.read(savedLocationsProvider.notifier).addLocation(
                  label,
                  selectedLoc['lat'] as double,
                  selectedLoc['lng'] as double,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added "$label" to your saved places!')),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.indigo),
              child: const Text('Save Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final savedPlacesAsync = ref.watch(savedLocationsProvider);

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('My Profile & Settings'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            // GUEST MODE CALLOUT OR AUTHENTICATED USER IDENTITY CARD
            if (user == null) ...[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient(),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pune Citizen Guest', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              SizedBox(height: 2),
                              Text('Exploring public air telemetry', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Unlock Personalized Features:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.violet)),
                          SizedBox(height: 6),
                          _BulletPoint(text: 'Save Home, Office & College for instant monitoring'),
                          _BulletPoint(text: 'Custom AQI spike push notifications for your ward'),
                          _BulletPoint(text: 'Personal commute particulate inhalation tracking'),
                          _BulletPoint(text: 'Report local burning & industrial smoke incidents'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => context.push('/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.indigo,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.push('/signup'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.violet),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Create Account', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // AUTHENTICATED USER IDENTITY CARD
              GlassCard(
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient(),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        user.email != null && user.email!.isNotEmpty ? user.email![0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.userMetadata?['full_name'] as String? ??
                                (user.email?.split('@')[0].replaceAll('.', ' ') ?? 'Pune Citizen'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.email ?? '',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.indigo.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.indigo.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'ROLE: ${_selectedRole.toUpperCase()} • AUTHENTICATED',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.violet),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note_rounded, color: AppColors.violet, size: 24),
                      tooltip: 'Edit Profile Name',
                      onPressed: () => _showEditProfileDialog(context, user),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),


              // SAVED PLACES MANAGEMENT (Strictly authenticated user data)
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('My Saved Places', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        IconButton(
                          onPressed: () => _showAddPlaceDialog(context),
                          icon: const Icon(Icons.add_location_alt_rounded, color: AppColors.indigo),
                          tooltip: 'Add Place',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    savedPlacesAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(color: AppColors.indigo),
                        ),
                      ),
                      error: (e, _) => Text('Error loading places: $e', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      data: (places) {
                        if (places.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Column(
                                children: [
                                  const Text('No saved places yet.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddPlaceDialog(context),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceElevated),
                                    icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.violet),
                                    label: const Text('Add Home, Work, or College', style: TextStyle(fontSize: 12, color: AppColors.violet)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: places.map((p) {
                            final placeId = p['id']?.toString() ?? '';
                            final placeLabel = p['label'] ?? 'Place';
                            final aqi = p['aqi_value'] ?? 80;
                            final cat = p['aqi_category'] ?? 'Satisfactory';
                            final color = AppColors.colorForAqiCategory(cat);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.place_rounded, color: AppColors.violet, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(placeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                          Text(p['nearest_station_name'] ?? 'Nearest Station', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                      child: Text('$aqi AQI', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
                                      onPressed: () => _confirmDeletePlace(context, placeId, placeLabel),
                                      tooltip: 'Delete Place',
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
              const SizedBox(height: 16),
            ],

            // HEALTH SENSITIVITY PROFILE
            Consumer(
              builder: (context, ref, _) {
                final activePersona = ref.watch(activeHealthPersonaProvider);
                final personas = [
                  'General Citizen',
                  'Asthma / Respiratory',
                  'Senior Citizen',
                  'Outdoor Athlete',
                  'Child / Parent'
                ];

                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Health Persona & Respiratory Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text('Customizes alert triggers, exercise windows, and health advice for Pune.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: personas.map((p) {
                          final isSelected = activePersona == p || (activePersona == 'General' && p == 'General Citizen');
                          return ChoiceChip(
                            label: Text(p, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? Colors.white : AppColors.textSecondary)),
                            selected: isSelected,
                            selectedColor: AppColors.indigo,
                            backgroundColor: AppColors.surfaceElevated,
                            onSelected: (val) async {
                              if (val) {
                                ref.read(activeHealthPersonaProvider.notifier).state = p;
                                if (user != null) {
                                  try {
                                    final sb = Supabase.instance.client;
                                    await sb.from('user_preferences').upsert({
                                      'user_id': user.id,
                                      'health_persona': p.toLowerCase().replaceAll(' ', '_'),
                                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                                    });
                                  } catch (e) {
                                    debugPrint('[Profile] user_preferences upsert error: $e');
                                  }
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Health persona switched to $p')),
                                  );
                                }
                              }
                            },

                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Asthma / Low-Tolerance Sensitivity', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Lowers threshold alert trigger to 100 AQI', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        value: _asthmaSensitivity,
                        activeColor: AppColors.indigo,
                        onChanged: (v) => setState(() => _asthmaSensitivity = v),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Outdoor Athlete Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Enables diurnal clean-window workout advice', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        value: _outdoorAthlete,
                        activeColor: AppColors.indigo,
                        onChanged: (v) => setState(() => _outdoorAthlete = v),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // NOTIFICATION SETTINGS
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notifications & Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Daily Morning Pune Air Brief (7:00 AM)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: _morningBrief,
                    activeColor: AppColors.indigo,
                    onChanged: (v) => setState(() => _morningBrief = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pollution Spike Alerts (> 150 AQI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: _spikeAlerts,
                    activeColor: AppColors.indigo,
                    onChanged: (v) => setState(() => _spikeAlerts = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // PUNE AQI STANDARDS GUIDE CARD
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Indian National AQI (CPCB) Scale', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _aqiScaleRow('0 - 50', 'Good', AppColors.aqiGood, 'Minimal health impact'),
                  _aqiScaleRow('51 - 100', 'Satisfactory', AppColors.aqiSatisfactory, 'Minor breathing discomfort to sensitive people'),
                  _aqiScaleRow('101 - 200', 'Moderate', AppColors.aqiModerate, 'Breathing discomfort to people with asthma and heart diseases'),
                  _aqiScaleRow('201 - 300', 'Poor', AppColors.aqiPoor, 'Breathing discomfort to most people on prolonged exposure'),
                  _aqiScaleRow('301 - 400', 'Very Poor', AppColors.aqiVeryPoor, 'Respiratory illness on prolonged exposure'),
                  _aqiScaleRow('401 - 500', 'Severe', AppColors.aqiSevere, 'Affects healthy people and seriously impacts sensitive groups'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // SYSTEM DIAGNOSTICS & TELEMETRY HEALTH
            const _DataHealthSection(),
            const SizedBox(height: 24),

            // LOGOUT ACTION FOR AUTHENTICATED USERS
            if (user != null)
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.aqiPoor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.logout_rounded, color: AppColors.aqiPoor),
                label: const Text('Sign Out', style: TextStyle(color: AppColors.aqiPoor, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _aqiScaleRow(String range, String category, Color color, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
            alignment: Alignment.center,
            child: Text(range, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color)),
                Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.violet, fontSize: 14, fontWeight: FontWeight.w800)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}

class _DataHealthSection extends ConsumerWidget {
  const _DataHealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(dataHealthProvider);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety_rounded, color: AppColors.aqiGood, size: 18),
                  SizedBox(width: 8),
                  Text('System Diagnostics', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.aqiGood.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Operational', style: TextStyle(color: AppColors.aqiGood, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          healthAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.indigo))),
            error: (_, __) => const Text('Telemetry diagnostic active', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            data: (data) {
              final tel = data['telemetry_health'] as Map<String, dynamic>? ?? {};
              return Column(
                children: [
                  _diagRow('Active Stations', '${tel['active_stations'] ?? 49} Pune Stations'),
                  _diagRow('Sync Interval', tel['pipeline_status'] ?? '15-min background sync'),
                  _diagRow('Standard Engine', 'CPCB NAQI 2014 Standard'),
                  _diagRow('ML Forecast Model', 'XGBoost Diurnal Dispersal'),
                  _diagRow('Cloud Database', 'Supabase PostgreSQL (Connected)'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
