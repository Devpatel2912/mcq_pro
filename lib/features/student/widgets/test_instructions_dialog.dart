import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/models/test.dart';

class TestInstructionsDialog extends StatefulWidget {
  final Test test;

  const TestInstructionsDialog({
    super.key,
    required this.test,
  });

  /// Shows the modal dialog and returns `true` only if the student agrees and clicks Start Test.
  static Future<bool> show(BuildContext context, Test test) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TestInstructionsDialog(test: test),
    );
    return result == true;
  }

  @override
  State<TestInstructionsDialog> createState() => _TestInstructionsDialogState();
}

class _TestInstructionsDialogState extends State<TestInstructionsDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final test = widget.test;
    final displayTitle = (test.title != null && test.title!.trim().isNotEmpty)
        ? test.title!.trim()
        : test.topic;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: AppColors.primaryGradient,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Exam Instructions',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Please read all rules carefully before starting',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textSecondary,
                        splashRadius: 20,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── Test Info Card ───────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildInfoChip(Icons.book_rounded, test.subject),
                            const SizedBox(width: 8),
                            _buildInfoChip(Icons.school_rounded, 'Std ${test.studentClass}'),
                            const SizedBox(width: 8),
                            _buildInfoChip(Icons.timer_rounded, '${test.duration} mins'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── Rules Section ────────────────────────────────────────
                  const Text(
                    'STRICT EXAM RULES & ANTI-CHEAT POLICY:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Rule 1: No screenshots
                  _buildRuleTile(
                    icon: Icons.no_photography_rounded,
                    iconColor: AppColors.error,
                    title: 'No Screenshots or Screen Recording',
                    description:
                        'Taking screenshots or screen recordings is strictly prohibited and blocked by the system.',
                  ),

                  const SizedBox(height: 10),

                  // Rule 2: Do not switch apps or leave screen
                  _buildRuleTile(
                    icon: Icons.app_blocking_rounded,
                    iconColor: AppColors.error,
                    title: 'Do Not Switch Apps or Leave Screen',
                    description:
                        'If you minimize the app, switch to another app, or navigate back, your test will be AUTOMATICALLY SUBMITTED immediately.',
                  ),

                  const SizedBox(height: 10),

                  // Rule 3: No back navigation
                  _buildRuleTile(
                    icon: Icons.lock_clock_rounded,
                    iconColor: AppColors.secondary,
                    title: 'No Back Navigation Once Started',
                    description:
                        'You cannot exit or go back after starting. You must complete and submit your answers.',
                  ),

                  const SizedBox(height: 10),

                  // Rule 4: Timer & Auto-submission
                  _buildRuleTile(
                    icon: Icons.timer_outlined,
                    iconColor: AppColors.primary,
                    title: 'Timer Auto-Submission',
                    description:
                        'The test has a ${test.duration}-minute timer. When the countdown reaches zero, all answers will be automatically submitted.',
                  ),

                  const SizedBox(height: 18),

                  // ── Mandatory Checkbox ───────────────────────────────────
                  GestureDetector(
                    onTap: () => setState(() => _agreed = !_agreed),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _agreed
                            ? AppColors.primary.withOpacity(0.08)
                            : Colors.grey.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _agreed
                              ? AppColors.primary
                              : Colors.grey.withOpacity(0.3),
                          width: _agreed ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _agreed,
                            onChanged: (val) => setState(() => _agreed = val ?? false),
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              'I have read, understood, and agree to strictly follow all the exam instructions and anti-cheating rules.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Actions ──────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: BorderSide(color: Colors.grey.withOpacity(0.35)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _agreed
                              ? () => Navigator.pop(context, true)
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text(
                            'Start Test',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.withOpacity(0.25),
                            disabledForegroundColor: Colors.grey.withOpacity(0.6),
                            elevation: _agreed ? 3 : 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: iconColor == AppColors.error ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary.withOpacity(0.9),
                    height: 1.3,
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
