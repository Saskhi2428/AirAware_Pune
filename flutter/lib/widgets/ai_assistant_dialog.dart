import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pune_providers.dart';
import '../theme/app_theme.dart';

class AiAssistantDialog extends ConsumerStatefulWidget {
  final String? initialLocality;
  const AiAssistantDialog({super.key, this.initialLocality});

  static Future<void> show(BuildContext context, {String? locality}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAssistantDialog(initialLocality: locality),
    );
  }

  @override
  ConsumerState<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends ConsumerState<AiAssistantDialog> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  final List<String> _suggestions = [
    'Can I go for a morning run?',
    'Do I need an N95 mask today?',
    'Should I open windows to ventilate?',
    'Is air safe for kids and seniors?',
  ];

  @override
  void initState() {
    super.initState();
    // Initial welcome message
    _messages.add({
      'isUser': false,
      'text':
          'Hello! I am your Pune Air Quality Assistant. Ask me anything about current pollution levels, outdoor activities, masks, ventilation, or specific Pune localities (e.g. Pashan, Kothrud, Hinjawadi).',
      'recommendations': <String>[],
    });
  }

  Future<void> _sendQuery(String query) async {
    final text = query.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    setState(() {
      _messages.add({'isUser': true, 'text': text});
      _isLoading = true;
    });

    try {
      final repo = ref.read(puneApiRepositoryProvider);
      final resp = await repo.askAiAssistant(text, locality: widget.initialLocality);

      if (mounted) {
        setState(() {
          _messages.add({
            'isUser': false,
            'text': resp['answer'] ?? 'Air quality in Pune is monitored in real-time.',
            'locality': resp['locality'],
            'aqi': resp['current_aqi'],
            'category': resp['category'],
            'pollutant': resp['dominant_pollutant'],
            'recommendations': List<String>.from(resp['key_recommendations'] ?? []),
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'isUser': false,
            'text': 'Sorry, I could not fetch live Pune air telemetry right now. Please check your network connection.',
            'recommendations': <String>[],
          });
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.borderSubtle, width: 1.5)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient(),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pune Air AI Assistant',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                      ),
                      Text(
                        'Real-time atmospheric telemetry & health guidance',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),

          // Messages list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                final isUser = m['isUser'] as bool;
                final recs = m['recommendations'] as List<String>? ?? [];
                final aqi = m['aqi'] as int?;
                final cat = m['category'] as String?;
                final locality = m['locality'] as String?;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isUser) ...[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome, size: 14, color: AppColors.violet),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isUser ? AppColors.indigo : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isUser ? AppColors.indigo : AppColors.borderSubtle,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser && aqi != null) ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.colorForAqiCategory(cat).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.colorForAqiCategory(cat)),
                                      ),
                                      child: Text(
                                        '${locality ?? "Pune"}: AQI $aqi • ${cat ?? ""}',
                                        style: TextStyle(
                                          color: AppColors.colorForAqiCategory(cat),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                m['text'] as String,
                                style: TextStyle(
                                  color: isUser ? Colors.white : AppColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                              if (recs.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                ...recs.map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('• ', style: TextStyle(color: AppColors.violet, fontWeight: FontWeight.bold)),
                                        Expanded(
                                          child: Text(
                                            r,
                                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet),
                  ),
                  SizedBox(width: 8),
                  Text('Analyzing Pune air telemetry...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),

          // Suggested quick question chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: _suggestions.map((s) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    backgroundColor: AppColors.surfaceElevated,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: () => _sendQuery(s),
                  ),
                );
              }).toList(),
            ),
          ),

          // Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ask about air, mask, running, or a Pune area...',
                      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.indigo, width: 1.5),
                      ),
                    ),
                    onSubmitted: _sendQuery,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.indigo,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: () => _sendQuery(_controller.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
