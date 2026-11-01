import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/core/services/supabase_service.dart';
import 'package:mcq_test_app/core/utils/academic_year_utils.dart';
import 'package:mcq_test_app/core/widgets/animated_page.dart';
import 'package:mcq_test_app/core/widgets/app_card.dart';
import 'package:mcq_test_app/core/widgets/app_gradient_background.dart';
import 'package:mcq_test_app/models/app_user.dart';

class AdminEditStudentScreen extends StatefulWidget {
  final AppUser student;

  const AdminEditStudentScreen({
    super.key,
    required this.student,
  });

  @override
  State<AdminEditStudentScreen> createState() => _AdminEditStudentScreenState();
}

class _AdminEditStudentScreenState extends State<AdminEditStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = SupabaseService();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _rollNoController;

  late String _selectedClass;
  late String _selectedDivision;
  late String _selectedMedium;
  late String _selectedGroup;
  late String _selectedInstitution;
  late String _selectedAcademicYear;
  late bool _isActive;
  late List<String> _availableAcademicYears;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final student = widget.student;

    _nameController = TextEditingController(text: student.name ?? '');
    _emailController = TextEditingController(text: student.email);
    _rollNoController = TextEditingController(text: student.rollNo ?? '');

    _selectedClass = (student.studentClass == '12') ? '12' : '11';

    // Institution resolution
    final inst = (student.institution ?? '').trim();
    if (inst.toLowerCase().contains('acc')) {
      _selectedInstitution = 'Tuition ACC';
    } else {
      _selectedInstitution = 'Sharda Mandir';
    }

    // Division resolution
    final rawDiv = (student.division ?? 'A').trim().toUpperCase();
    if (_selectedInstitution == 'Tuition ACC') {
      _selectedDivision = 'ACC';
    } else {
      _selectedDivision = ['A', 'B', 'C'].contains(rawDiv) ? rawDiv : 'A';
    }

    // Medium resolution
    final rawMedium = (student.medium ?? 'English').trim();
    _selectedMedium = rawMedium.toLowerCase().contains('guj') ? 'Gujarati' : 'English';

    // Group resolution
    final rawGroup = (student.studentGroup ?? 'Biology').trim().toLowerCase();
    _selectedGroup = (rawGroup.contains('math') || rawGroup == 'a') ? 'Math' : 'Biology';

    // Academic Year
    _availableAcademicYears = AcademicYearUtils.getDynamicAcademicYears(
      extraYear: student.academicYear,
    );
    final currentYear = student.academicYear?.trim();
    if (currentYear != null && currentYear.isNotEmpty) {
      _selectedAcademicYear = currentYear;
      if (!_availableAcademicYears.contains(_selectedAcademicYear)) {
        _availableAcademicYears.add(_selectedAcademicYear);
        _availableAcademicYears.sort();
      }
    } else {
      _selectedAcademicYear = _availableAcademicYears.contains('2026-2027')
          ? '2026-2027'
          : AcademicYearUtils.getCurrentAcademicYear();
    }

    _isActive = student.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _rollNoController.dispose();
    super.dispose();
  }

  void _onInstitutionChanged(String? newInst) {
    if (newInst == null) return;
    setState(() {
      _selectedInstitution = newInst;
      if (newInst == 'Tuition ACC') {
        _selectedDivision = 'ACC';
      } else {
        if (!['A', 'B', 'C'].contains(_selectedDivision)) {
          _selectedDivision = 'A';
        }
      }
    });
  }

  Future<void> _pickAcademicYearFromCalendar() async {
    final now = DateTime.now();
    int initialYear = now.year;
    final match = RegExp(r'^(\d{4})').firstMatch(_selectedAcademicYear);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null && parsed >= 2020 && parsed <= 2045) {
        initialYear = parsed;
      }
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initialYear, 6),
      firstDate: DateTime(2020),
      lastDate: DateTime(2045),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select Academic Session Start Year',
    );

    if (pickedDate != null) {
      final formattedYear = AcademicYearUtils.formatFromStartYear(pickedDate.year);
      setState(() {
        if (!_availableAcademicYears.contains(formattedYear)) {
          _availableAcademicYears.add(formattedYear);
          _availableAcademicYears.sort();
        }
        _selectedAcademicYear = formattedYear;
      });
    }
  }

  void _showResetPasswordDialog() {
    final passController = TextEditingController(text: 'Pass@1234');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Reset Password: ${widget.student.name ?? widget.student.email}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set a temporary password. The student will be prompted to change it upon their next login:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: passController,
                    decoration: InputDecoration(
                      labelText: 'Temporary Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: passController.text.trim()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final newPass = passController.text.trim();
              try {
                await _supabase.adminSetUserPassword(
                  userId: widget.student.id,
                  email: widget.student.email,
                  newPassword: newPass,
                  mustChangePassword: true,
                );
                Clipboard.setData(
                  ClipboardData(text: 'Email: ${widget.student.email}\nTemporary Password: $newPass'),
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Password reset for ${widget.student.email}. Credentials copied!'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error resetting password: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Reset & Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final name = _nameController.text.trim();
    final rollNo = _rollNoController.text.trim();

    setState(() => _isSaving = true);

    try {
      await _supabase.updateStudent(
        studentId: widget.student.id,
        name: name,
        studentClass: _selectedClass,
        division: _selectedDivision,
        medium: _selectedMedium,
        studentGroup: _selectedGroup,
        rollNo: rollNo,
        institution: _selectedInstitution,
        academicYear: _selectedAcademicYear,
        isActive: _isActive,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Student data updated successfully!'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update student: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.student.name?.trim().isNotEmpty == true
        ? widget.student.name!.trim()
        : 'Student';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Student Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset_rounded),
            tooltip: 'Reset Password',
            onPressed: _showResetPasswordDialog,
          ),
        ],
      ),
      body: AppGradientBackground(
        child: AnimatedPage(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header card with student preview
                      _buildHeaderCard(displayName, initial),
                      const SizedBox(height: 18),

                      // Personal / Identity Section
                      _buildIdentityCard(),
                      const SizedBox(height: 18),

                      // Academic Enrollment Section
                      _buildAcademicCard(),
                      const SizedBox(height: 18),

                      // Account Status Section
                      _buildStatusCard(),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSaving ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveChanges,
                              icon: _isSaving
                                  ? const SizedBox.shrink()
                                  : const Icon(Icons.check_circle_rounded),
                              label: _isSaving
                                  ? const SpinKitThreeBounce(color: Colors.white, size: 20)
                                  : const Text(
                                      'Save Student Data',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String displayName, String initial) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.primaryGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  widget.student.email,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Student ID: ${widget.student.id.substring(0, 8)}...',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Personal & Identity Info',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Student Full Name
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Student Full Name *',
              hintText: 'e.g. John Doe',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.person_rounded),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter the student\'s name';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Roll Number
          TextFormField(
            controller: _rollNoController,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Roll Number *',
              hintText: 'e.g. 1, 14, 25',
              helperText: 'Assigned sequential roll number for this student',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter a roll number';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Email (Read-Only)
          TextFormField(
            controller: _emailController,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Login Email Address',
              helperText: 'Registered authentication email (managed by auth)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              filled: true,
              fillColor: AppColors.surface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicCard() {
    final isAcc = _selectedInstitution == 'Tuition ACC';

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.school_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Academic & Class Enrollment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Institution / School Selector
          const Text(
            'Institution / School',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildChoiceChip(
                  label: 'Sharda Mandir',
                  selected: _selectedInstitution == 'Sharda Mandir',
                  onSelected: () => _onInstitutionChanged('Sharda Mandir'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildChoiceChip(
                  label: 'Tuition ACC',
                  selected: _selectedInstitution == 'Tuition ACC',
                  onSelected: () => _onInstitutionChanged('Tuition ACC'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Standard / Class
          const Text(
            'Standard / Class',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildChoiceChip(
                  label: 'Std 11 (11th)',
                  selected: _selectedClass == '11',
                  onSelected: () => setState(() => _selectedClass = '11'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildChoiceChip(
                  label: 'Std 12 (12th)',
                  selected: _selectedClass == '12',
                  onSelected: () => setState(() => _selectedClass = '12'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Division
          const Text(
            'Division / Section',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (isAcc) ...[
            _buildChoiceChip(
              label: 'ACC Division',
              selected: true,
              onSelected: () {},
            ),
          ] else ...[
            Row(
              children: ['A', 'B', 'C'].map((div) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildChoiceChip(
                      label: 'Div $div',
                      selected: _selectedDivision == div,
                      onSelected: () => setState(() => _selectedDivision = div),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),

          // Medium of Instruction
          const Text(
            'Medium of Instruction',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildChoiceChip(
                  label: 'English Medium',
                  selected: _selectedMedium == 'English',
                  onSelected: () => setState(() => _selectedMedium = 'English'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildChoiceChip(
                  label: 'Gujarati Medium',
                  selected: _selectedMedium == 'Gujarati',
                  onSelected: () => setState(() => _selectedMedium = 'Gujarati'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Subject Stream / Group
          const Text(
            'Subject Stream / Elective Group',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildChoiceChip(
                  label: 'Biology (Group B / Medical)',
                  selected: _selectedGroup == 'Biology',
                  onSelected: () => setState(() => _selectedGroup = 'Biology'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildChoiceChip(
                  label: 'Math (Group A / Engineering)',
                  selected: _selectedGroup == 'Math',
                  onSelected: () => setState(() => _selectedGroup = 'Math'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Academic Year
          const Text(
            'Academic Session / Year',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _availableAcademicYears.contains(_selectedAcademicYear)
                      ? _selectedAcademicYear
                      : null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  items: _availableAcademicYears.map((yr) {
                    return DropdownMenuItem<String>(
                      value: yr,
                      child: Text(yr, style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedAcademicYear = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.date_range_rounded),
                tooltip: 'Pick Academic Year from Calendar',
                onPressed: _pickAcademicYearFromCalendar,
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Account Controls & Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _isActive ? 'Student Account is Active' : 'Student Account is Disabled',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _isActive ? AppColors.success : AppColors.error,
              ),
            ),
            subtitle: Text(
              _isActive
                  ? 'The student can log in, take tests, view performance, and send messages.'
                  : 'The student is blocked from logging in until re-enabled by an admin.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            value: _isActive,
            activeColor: AppColors.success,
            onChanged: (val) => setState(() => _isActive = val),
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Temporary Password',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      'Issue a new temporary password if student forgot credentials',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showResetPasswordDialog,
                icon: const Icon(Icons.lock_reset_rounded, size: 16),
                label: const Text('Reset Pass'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

