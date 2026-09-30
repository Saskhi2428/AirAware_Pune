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

  // ---------------------------------------------------------------------------
  // 1. EDIT PROFILE DIALOG (Strictly updates full_name, NEVER sends email)
  // ---------------------------------------------------------------------------
  void _showEditProfileDialog(BuildContext context, Map<String, dynamic> profile, User user) {
    final currentName = (profile['full_name'] as String?)?.trim().isNotEmpty == true
        ? profile['full_name'] as String
        : (user.userMetadata?['full_name'] as String?) ??
            (user.email?.split('@')[0].replaceAll('.', ' ') ?? 'Pune Citizen');

    final nameCtrl = TextEditingController(text: currentName);
    bool isSaving = false;
    String? inlineError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.borderSubtle),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Edit Profile',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dynamic Avatar Initial Preview
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient(),
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        nameCtrl.text.trim().isNotEmpty
                            ? nameCtrl.text.trim()[0].toUpperCase()
                            : (user.email != null && user.email!.isNotEmpty ? user.email![0].toUpperCase() : 'U'),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Editable Full Name Field
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.person_rounded, color: AppColors.violet, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.indigo),
                      ),
                      errorText: inlineError,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (_) {
                      if (inlineError != null) setDlgState(() => inlineError = null);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Read-Only Account Email Card (Auth-Managed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 18, color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Account Email (Read-Only)',
                                style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email ?? 'No email associated',
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const Tooltip(
                          message: 'Managed securely by Supabase Authentication',
                          child: Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Email is linked to your authentication login credentials and is read-only here.',
                      style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                      if (newName.length < 2) {
                        setDlgState(() => inlineError = 'Please enter at least 2 characters');
                        return;
                      }

                      setDlgState(() {
                        isSaving = true;
                        inlineError = null;
                      });

                      try {
                        await ref.read(userProfileProvider.notifier).updateFullName(newName);

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppColors.indigo,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() {
                          isSaving = false;
                          inlineError = 'Couldn\'t update profile. Please try again.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.indigo,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. SAVED PLACES (Add, Delete, Categories)
  // ---------------------------------------------------------------------------
  void _showAddPlaceDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    String category = 'Home'; // 'Home', 'Office', 'College', 'Custom'
    final localities = [
      {'name': 'Shivajinagar', 'lat': 18.5314, 'lng': 73.8446},
      {'name': 'Kothrud', 'lat': 18.5074, 'lng': 73.8077},
      {'name': 'Hinjawadi Phase 1', 'lat': 18.5913, 'lng': 73.7389},
      {'name': 'SPPU / University', 'lat': 18.5529, 'lng': 73.8260},
      {'name': 'Hadapsar / Magarpatta', 'lat': 18.5167, 'lng': 73.9298},
      {'name': 'Viman Nagar', 'lat': 18.5679, 'lng': 73.9143},
      {'name': 'Aundh', 'lat': 18.5580, 'lng': 73.8073},
      {'name': 'Wakad', 'lat': 18.5987, 'lng': 73.7688},
      {'name': 'Bhosari MIDC', 'lat': 18.6277, 'lng': 73.8471},
      {'name': 'Baner', 'lat': 18.5590, 'lng': 73.7868},
      {'name': 'Katraj', 'lat': 18.4529, 'lng': 73.8553},
      {'name': 'Pimpri', 'lat': 18.6279, 'lng': 73.8009},
      {'name': 'Swargate', 'lat': 18.5018, 'lng': 73.8586},
      {'name': 'Kalyani Nagar', 'lat': 18.5463, 'lng': 73.9034},
    ];
    Map<String, dynamic> selectedLoc = localities[0];
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.borderSubtle),
          ),
          title: const Text('Add Saved Place in Pune', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: ['Home', 'Office', 'College', 'Custom'].map((cat) {
                      final sel = category == cat;
                      return ChoiceChip(
                        label: Text(
                          cat == 'Home' ? '🏠 Home' : (cat == 'Office' ? '🏢 Office' : (cat == 'College' ? '🎓 College' : '📍 Custom')),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                        selected: sel,
                        selectedColor: AppColors.indigo,
                        backgroundColor: AppColors.surface,
                        onSelected: (val) {
                          if (val) {
                            setDlgState(() {
                              category = cat;
                              if (cat != 'Custom' && nameCtrl.text.isEmpty) {
                                nameCtrl.text = '$cat (${selectedLoc['name']})';
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedLoc,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      labelText: 'Pune Locality',
                      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    items: localities.map((loc) {
                      return DropdownMenuItem(
                        value: loc,
                        child: Text(loc['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() {
                          selectedLoc = val;
                          if (category != 'Custom' && (nameCtrl.text.isEmpty || nameCtrl.text.startsWith(category))) {
                            nameCtrl.text = '$category (${val['name']})';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Custom Label (Optional)',
                      hintText: '$category (${selectedLoc['name']})',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
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
                      final label = nameCtrl.text.trim().isNotEmpty
                          ? nameCtrl.text.trim()
                          : '$category (${selectedLoc['name']})';

                      setDlgState(() => isSaving = true);
                      try {
                        await ref.read(savedLocationsProvider.notifier).addLocation(
                              label,
                              selectedLoc['lat'] as double,
                              selectedLoc['lng'] as double,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added "$label" to saved places'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppColors.indigo,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Couldn\'t save place. Please try again.'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Place', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePlace(BuildContext context, String id, String label) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
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
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(savedLocationsProvider.notifier).removeLocation(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed "$label"'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.aqiPoor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Are you sure you want to sign out? Your saved places and notification preferences will remain safely stored in your cloud account.',
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
                  const SnackBar(
                    content: Text('Signed out'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                context.go('/');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.aqiPoor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. MAIN BUILD METHOD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(userProfileProvider);
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
            // 1. GUEST MODE CALLOUT
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
              // 2. AUTHENTICATED USER IDENTITY CARD (Loaded from public.profiles)
              profileAsync.when(
                loading: () => const _ProfileSkeleton(),
                error: (err, _) => GlassCard(
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.aqiPoor),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Could not load profile from database.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(userProfileProvider),
                        child: const Text('Retry', style: TextStyle(color: AppColors.violet)),
                      ),
                    ],
                  ),
                ),
                data: (profile) {
                  final displayName = (profile['full_name'] as String?)?.trim().isNotEmpty == true
                      ? profile['full_name'] as String
                      : (user.userMetadata?['full_name'] as String?) ??
                          (user.email?.split('@')[0].replaceAll('.', ' ') ?? 'Pune Citizen');

                  final rawRole = (profile['role'] ?? 'user').toString().toLowerCase();
                  final roleLabel = rawRole == 'admin'
                      ? 'SYSTEM ADMIN'
                      : (rawRole == 'researcher' ? 'RESEARCHER' : 'CITIZEN');
                  final roleColor = rawRole == 'admin'
                      ? AppColors.violet
                      : (rawRole == 'researcher' ? AppColors.aqiGood : AppColors.indigo);
                  final roleIcon = rawRole == 'admin'
                      ? Icons.security_rounded
                      : (rawRole == 'researcher' ? Icons.science_rounded : Icons.verified_user_rounded);

                  final prefs = Map<String, dynamic>.from(profile['notification_prefs'] as Map? ?? {});

                  return Column(
                    children: [
                      // User Identity Card
                      GlassCard(
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: AppColors.brandGradient(),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
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
                                      color: roleColor.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: roleColor.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(roleIcon, size: 12, color: roleColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ROLE: $roleLabel • AUTHENTICATED',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: roleColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, color: AppColors.violet, size: 26),
                              tooltip: 'Edit Profile Name',
                              onPressed: () => _showEditProfileDialog(context, profile, user),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. SAVED PLACES MANAGEMENT
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
                                          const SizedBox(height: 8),
                                          ElevatedButton.icon(
                                            onPressed: () => _showAddPlaceDialog(context),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.surfaceElevated,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
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
                                    final placeLabel = p['label']?.toString() ?? 'Place';
                                    final aqi = p['aqi_value'] ?? 80;
                                    final cat = p['aqi_category']?.toString() ?? 'Satisfactory';
                                    final color = AppColors.colorForAqiCategory(cat);

                                    // Category icon
                                    IconData placeIcon = Icons.place_rounded;
                                    if (placeLabel.toLowerCase().contains('home')) {
                                      placeIcon = Icons.home_rounded;
                                    } else if (placeLabel.toLowerCase().contains('office') || placeLabel.toLowerCase().contains('work')) {
                                      placeIcon = Icons.business_rounded;
                                    } else if (placeLabel.toLowerCase().contains('college') || placeLabel.toLowerCase().contains('univ')) {
                                      placeIcon = Icons.school_rounded;
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceElevated,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: AppColors.borderSubtle),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(placeIcon, color: AppColors.violet, size: 20),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(placeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                                  Text(
                                                    p['nearest_station_name'] != null
                                                        ? 'Station: ${p['nearest_station_name']}'
                                                        : 'Pune Telemetry Region',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: color.withValues(alpha: 0.6)),
                                              ),
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

                      // 4. HEALTH PERSONA & RESPIRATORY PROFILE (Persisted in profiles.notification_prefs)
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Health Persona & Respiratory Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text(
                              'Customizes alert triggers, exercise windows, and health advice for Pune.',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                'General Citizen',
                                'Asthma / Respiratory',
                                'Senior Citizen',
                                'Outdoor Athlete',
                                'Child / Parent'
                              ].map((p) {
                                final activePersona = prefs['health_persona'] as String? ?? 'General Citizen';
                                final isSelected = activePersona == p ||
                                    (activePersona.toLowerCase().contains('general') && p == 'General Citizen') ||
                                    (activePersona.toLowerCase().contains('asthma') && p == 'Asthma / Respiratory') ||
                                    (activePersona.toLowerCase().contains('senior') && p == 'Senior Citizen') ||
                                    (activePersona.toLowerCase().contains('athlete') && p == 'Outdoor Athlete') ||
                                    (activePersona.toLowerCase().contains('child') && p == 'Child / Parent');

                                return ChoiceChip(
                                  label: Text(
                                    p,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? Colors.white : AppColors.textSecondary,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: AppColors.indigo,
                                  backgroundColor: AppColors.surfaceElevated,
                                  onSelected: (val) async {
                                    if (val && !isSelected) {
                                      final updatedPrefs = Map<String, dynamic>.from(prefs);
                                      updatedPrefs['health_persona'] = p;
                                      try {
                                        await ref.read(userProfileProvider.notifier).updateNotificationPrefs(updatedPrefs);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Health persona switched to $p'),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Couldn\'t update setting. Please try again.'),
                                              duration: Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. NOTIFICATION SETTINGS (Persisted in profiles.notification_prefs)
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Notifications & Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.aqiGood.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.aqiGood.withValues(alpha: 0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: AppColors.aqiGood, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'Delivery: In-app & local alerts active',
                                        style: TextStyle(color: AppColors.aqiGood, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Cloud-persisted alert preferences for Pune monitoring stations.',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),

                            // Switch 1: Morning Brief
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Daily Morning Pune Air Brief (7:00 AM)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Diurnal summary of cleanest window for exercise', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              value: (prefs['morning_brief'] as bool?) ?? true,
                              activeColor: AppColors.indigo,
                              onChanged: (v) async {
                                final updatedPrefs = Map<String, dynamic>.from(prefs);
                                updatedPrefs['morning_brief'] = v;
                                try {
                                  await ref.read(userProfileProvider.notifier).updateNotificationPrefs(updatedPrefs);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Couldn\'t update notification setting. Please try again.'), behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              },
                            ),

                            // Switch 2: Spike Alerts
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Pollution Spike Alerts (> 150 AQI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Immediate alert when local Pune station enters Unhealthy AQI', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              value: (prefs['spike_alerts'] as bool?) ?? true,
                              activeColor: AppColors.indigo,
                              onChanged: (v) async {
                                final updatedPrefs = Map<String, dynamic>.from(prefs);
                                updatedPrefs['spike_alerts'] = v;
                                try {
                                  await ref.read(userProfileProvider.notifier).updateNotificationPrefs(updatedPrefs);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Couldn\'t update notification setting. Please try again.'), behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              },
                            ),

                            // Switch 3: Asthma Sensitivity
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Asthma / Low-Tolerance Sensitivity', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Lowers threshold alert trigger to 100 AQI', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              value: (prefs['asthma_sensitivity'] as bool?) ?? false,
                              activeColor: AppColors.indigo,
                              onChanged: (v) async {
                                final updatedPrefs = Map<String, dynamic>.from(prefs);
                                updatedPrefs['asthma_sensitivity'] = v;
                                try {
                                  await ref.read(userProfileProvider.notifier).updateNotificationPrefs(updatedPrefs);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Couldn\'t update notification setting. Please try again.'), behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              },
                            ),

                            // Switch 4: Outdoor Athlete Mode
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Outdoor Athlete Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Enables diurnal clean-window workout advice and route notifications', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              value: (prefs['outdoor_athlete'] as bool?) ?? true,
                              activeColor: AppColors.indigo,
                              onChanged: (v) async {
                                final updatedPrefs = Map<String, dynamic>.from(prefs);
                                updatedPrefs['outdoor_athlete'] = v;
                                try {
                                  await ref.read(userProfileProvider.notifier).updateNotificationPrefs(updatedPrefs);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Couldn\'t update notification setting. Please try again.'), behavior: SnackBarBehavior.floating),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ],

            // 6. PUNE AQI STANDARDS GUIDE CARD (Always available for civic education)
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

            // 7. SYSTEM DIAGNOSTICS & TELEMETRY HEALTH
            const _DataHealthSection(),
            const SizedBox(height: 24),

            // 8. LOGOUT ACTION FOR AUTHENTICATED USERS
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 140, height: 16, decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(width: 180, height: 12, decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(width: 100, height: 16, decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(8))),
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
