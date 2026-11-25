import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/core/services/supabase_service.dart';
import 'package:mcq_test_app/models/app_user.dart';
import 'package:mcq_test_app/models/teacher_assignment.dart';

class BroadcastMessageModal extends StatefulWidget {
  const BroadcastMessageModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const BroadcastMessageModal(),
    );
  }

  @override
  State<BroadcastMessageModal> createState() => _BroadcastMessageModalState();
}

class _BroadcastMessageModalState extends State<BroadcastMessageModal> {
  final SupabaseService _supabase = SupabaseService();
  final TextEditingController _messageController = TextEditingController();

  List<TeacherAssignment> _assignments = [];
  List<AppUser> _allStudents = [];
  bool _isLoading = true;
  bool _isSending = false;

  String? _selectedStandard;
  final Set<String> _selectedDivisions = {}; // empty means 'All'

  final List<String> _quickTemplates = [
    '📢 Test Announcement: MCQ test scheduled for tomorrow. Please revise thoroughly!',
    '⏰ Reminder: Please complete your assigned practice tests and review your answers.',
    '📝 Exam Instructions: Bring your calculators and formula sheets for the test.',
    '💡 Important Notice: Extra doubt-clearing session will be conducted after class.',
  ];

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadTeacherData() async {
    final user = _supabase.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final assignments = await _supabase.getTeacherAssignments(user.id);
      final students = await _supabase.getAuthorizedStudentsForCurrentTeacher();

      if (mounted) {
        setState(() {
          _assignments = assignments;
          _allStudents = students;
          _isLoading = false;

          final standards = _availableStandards;
          if (standards.isNotEmpty) {
            _selectedStandard = standards.first;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _availableStandards {
    final set = _assignments.map((a) => a.standard.trim()).where((s) => s.isNotEmpty).toSet().toList();
    set.sort();
    return set.isNotEmpty ? set : ['11', '12'];
  }

  List<String> get _availableDivisions {
    if (_selectedStandard == null) return ['A', 'B', 'C'];
    final set = _assignments
        .where((a) => a.standard.trim() == _selectedStandard)
        .map((a) {
          var d = a.division.trim().toUpperCase();
          if (d.startsWith('DIV ')) d = d.substring(4).trim();
          return d;
        })
        .where((d) => d.isNotEmpty && d != 'ALL')
        .toSet()
        .toList();
    set.sort();
    return set.isNotEmpty ? set : ['A', 'B', 'C'];
  }

  List<AppUser> get _matchingStudents {
    if (_selectedStandard == null) return [];
    final targetStd = _selectedStandard!.trim();
    final allowedDivs = _selectedDivisions
        .map((d) => d.trim().toUpperCase())
        .where((d) => d.isNotEmpty && d != 'ALL')
        .toSet();

    return _allStudents.where((student) {
      final sStd = (student.studentClass ?? '').trim();
      var sDiv = (student.division ?? '').trim().toUpperCase();
      if (sDiv.startsWith('DIV ')) sDiv = sDiv.substring(4).trim();

      final testDigit = RegExp(r'\d+').firstMatch(targetStd)?.group(0);
      final studentDigit = RegExp(r'\d+').firstMatch(sStd)?.group(0);
      final isClassMatch = (testDigit != null && studentDigit != null)
          ? (testDigit == studentDigit)
          : (targetStd.toLowerCase() == sStd.toLowerCase());

      if (!isClassMatch) return false;

      if (allowedDivs.isNotEmpty) {
        if (sDiv.isNotEmpty && !allowedDivs.contains(sDiv)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _sendBroadcast() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an announcement message to broadcast.')),
      );
      return;
    }

    if (_selectedStandard == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target standard.')),
      );
      return;
    }

    final recipients = _matchingStudents;
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No enrolled students match the selected standard & division(s).')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final count = await _supabase.broadcastMessageToClass(
        standard: _selectedStandard!,
        divisions: _selectedDivisions.toList(),
        messageText: text,
      );

      if (mounted) {
        Navigator.pop(context);
        final divLabel = _selectedDivisions.isEmpty || _selectedDivisions.length == _availableDivisions.length
            ? 'All Divisions'
            : 'Div ${(_selectedDivisions.toList()..sort()).join(', ')}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎉 Broadcasted to $count students in Std $_selectedStandard ($divLabel)!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Broadcast failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isAllDivisionsSelected = _selectedDivisions.isEmpty ||
        _selectedDivisions.length == _availableDivisions.length;
    final matchingCount = _matchingStudents.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottomInset),
            child: _isLoading
                ? const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Title Bar
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: AppColors.primaryGradient),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Broadcast Announcement',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Text(
                                    'Send a direct message to division(s) or entire class',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                              splashRadius: 20,
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // ── Standard (Class) Selection ──
                        const Text(
                          'Target Standard',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          children: _availableStandards.map((std) {
                            final isSelected = std == _selectedStandard;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedStandard = std;
                                  _selectedDivisions.removeWhere((d) => !_availableDivisions.contains(d));
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? const LinearGradient(colors: AppColors.primaryGradient)
                                      : null,
                                  color: isSelected ? null : Colors.grey.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.2),
                                  ),
                                ),
                                child: Text(
                                  'Std $std',
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? Colors.white : AppColors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        // ── Division Selection (Multi-select) ──
                        Row(
                          children: [
                            const Text(
                              'Target Division(s)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isAllDivisionsSelected
                                    ? 'All Divisions'
                                    : 'Div ${(_selectedDivisions.toList()..sort()).join(', ')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            // "All" pill
                            _buildPill(
                              label: 'All',
                              isSelected: isAllDivisionsSelected,
                              showCheck: false,
                              onTap: () {
                                setState(() => _selectedDivisions.clear());
                              },
                            ),
                            // Individual division pills
                            ..._availableDivisions.map((div) {
                              final isSelected = !isAllDivisionsSelected && _selectedDivisions.contains(div);
                              return _buildPill(
                                label: div,
                                isSelected: isSelected,
                                showCheck: isSelected,
                                onTap: () {
                                  setState(() {
                                    if (isAllDivisionsSelected) {
                                      _selectedDivisions.clear();
                                      _selectedDivisions.add(div);
                                    } else {
                                      if (_selectedDivisions.contains(div)) {
                                        _selectedDivisions.remove(div);
                                      } else {
                                        _selectedDivisions.add(div);
                                        if (_selectedDivisions.length == _availableDivisions.length) {
                                          _selectedDivisions.clear();
                                        }
                                      }
                                    }
                                  });
                                },
                              );
                            }),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Audience Summary Chip ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: matchingCount > 0
                                ? AppColors.success.withOpacity(0.08)
                                : AppColors.secondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: matchingCount > 0
                                  ? AppColors.success.withOpacity(0.25)
                                  : AppColors.secondary.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                matchingCount > 0 ? Icons.people_alt_rounded : Icons.info_outline_rounded,
                                size: 16,
                                color: matchingCount > 0 ? AppColors.success : AppColors.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  matchingCount > 0
                                      ? 'Ready to broadcast to $matchingCount student${matchingCount > 1 ? "s" : ""} in Std $_selectedStandard'
                                      : 'No authorized students found for Std $_selectedStandard in selected division(s)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: matchingCount > 0 ? AppColors.success : AppColors.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // ── Announcement Message Input ──
                        const Text(
                          'Announcement Message',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _messageController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Type your announcement message here...',
                            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                            filled: true,
                            fillColor: Colors.grey.withOpacity(0.05),
                            contentPadding: const EdgeInsets.all(14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey.withOpacity(0.25)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.grey.withOpacity(0.25)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Quick Templates
                        const Text(
                          'Quick Templates',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _quickTemplates.map((template) {
                              final shortLabel = template.split(':').first;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(shortLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  backgroundColor: AppColors.primary.withOpacity(0.06),
                                  side: BorderSide(color: AppColors.primary.withOpacity(0.2)),
                                  onPressed: () {
                                    setState(() {
                                      _messageController.text = template;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Broadcast Action Button ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _isSending ? null : _sendBroadcast,
                            icon: _isSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                              _isSending
                                  ? 'Broadcasting Message...'
                                  : 'Send Broadcast to $matchingCount Student${matchingCount == 1 ? "" : "s"}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required bool showCheck,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: AppColors.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.22),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCheck) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
