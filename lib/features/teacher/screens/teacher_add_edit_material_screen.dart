import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/core/services/supabase_service.dart';
import 'package:mcq_test_app/core/widgets/animated_page.dart';
import 'package:mcq_test_app/core/widgets/app_card.dart';
import 'package:mcq_test_app/core/widgets/app_gradient_background.dart';
import 'package:mcq_test_app/models/app_user.dart';
import 'package:mcq_test_app/models/study_material.dart';
import 'package:mcq_test_app/models/teacher_assignment.dart';
import 'package:url_launcher/url_launcher.dart';

class TeacherAddEditMaterialScreen extends StatefulWidget {
  final StudyMaterial? material;

  const TeacherAddEditMaterialScreen({super.key, this.material});

  @override
  State<TeacherAddEditMaterialScreen> createState() => _TeacherAddEditMaterialScreenState();
}

class _TeacherAddEditMaterialScreenState extends State<TeacherAddEditMaterialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = SupabaseService();

  late TextEditingController _titleController;
  late TextEditingController _urlController;
  late TextEditingController _descriptionController;

  bool _isLoadingAssignments = true;
  bool _isSaving = false;
  List<TeacherAssignment> _assignments = [];

  // Strictly assigned selections
  String? _selectedSubject;
  String? _selectedStandard;
  String? _selectedDivision;
  String? _selectedMedium;
  String? _selectedInstitution;
  String _selectedGroup = 'all'; // 'all', 'Biology', 'Math'

  // Student specific targeting
  bool _targetSpecificStudents = false;
  List<AppUser> _eligibleStudents = [];
  bool _isLoadingStudents = false;
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    final m = widget.material;
    _titleController = TextEditingController(text: m?.title ?? '');
    _urlController = TextEditingController(text: m?.url ?? '');
    _descriptionController = TextEditingController(text: m?.description ?? '');

    if (m != null) {
      _selectedSubject = m.subject;
      _selectedStandard = m.standard;
      _selectedDivision = m.division;
      _selectedMedium = m.medium;
      _selectedInstitution = m.institution;
      _selectedGroup = m.studentGroup;
      if (m.assignedStudentIds != null && m.assignedStudentIds!.isNotEmpty) {
        _targetSpecificStudents = true;
        _selectedStudentIds.addAll(m.assignedStudentIds!);
      }
    }

    _urlController.addListener(() {
      setState(() {});
    });

    _loadTeacherAssignments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.material != null;

  Future<void> _loadTeacherAssignments() async {
    setState(() => _isLoadingAssignments = true);
    final user = _supabase.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingAssignments = false);
      return;
    }

    try {
      final list = await _supabase.getTeacherAssignments(user.id);
      if (mounted) {
        setState(() {
          _assignments = list;
          _isLoadingAssignments = false;

          // If adding new, auto-select first valid assigned combination
          if (!_isEditing && _assignments.isNotEmpty) {
            final first = _assignments.first;
            _selectedInstitution = first.institution;
            _selectedSubject = first.subject;
            _selectedStandard = first.standard;
            _selectedDivision = first.division;
            _selectedMedium = first.medium;
            _autoAdjustGroupForSubject(_selectedSubject);
          }
        });

        if (_targetSpecificStudents || (_selectedStandard != null && _selectedDivision != null)) {
          _loadEligibleStudents();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAssignments = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load teaching assignments: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _autoAdjustGroupForSubject(String? subject) {
    if (subject == null) return;
    final sub = subject.toLowerCase();
    if (sub.contains('bio')) {
      _selectedGroup = 'Biology';
    } else if (sub.contains('math')) {
      _selectedGroup = 'Math';
    } else {
      _selectedGroup = 'all';
    }
  }

  // Filtered assigned options
  List<String> get _assignedSubjects {
    return _assignments.map((a) => a.subject).toSet().toList();
  }

  List<String> get _assignedStandards {
    if (_selectedSubject == null) return [];
    return _assignments
        .where((a) => a.subject == _selectedSubject)
        .map((a) => a.standard)
        .toSet()
        .toList();
  }

  List<String> get _assignedDivisions {
    if (_selectedSubject == null || _selectedStandard == null) return [];
    return _assignments
        .where((a) => a.subject == _selectedSubject && a.standard == _selectedStandard)
        .map((a) => a.division)
        .toSet()
        .toList();
  }

  List<String> get _assignedMediums {
    if (_selectedSubject == null || _selectedStandard == null || _selectedDivision == null) return [];
    return _assignments
        .where((a) =>
            a.subject == _selectedSubject &&
            a.standard == _selectedStandard &&
            a.division == _selectedDivision)
        .map((a) => a.medium)
        .toSet()
        .toList();
  }

  void _onSectionChanged() {
    // Find matching assignment to auto-sync institution
    final matching = _assignments.firstWhere(
      (a) =>
          a.subject == _selectedSubject &&
          a.standard == _selectedStandard &&
          a.division == _selectedDivision &&
          a.medium == _selectedMedium,
      orElse: () => _assignments.isNotEmpty ? _assignments.first : TeacherAssignment(
        teacherId: '',
        standard: '',
        division: '',
        medium: '',
        subject: '',
      ),
    );
    if (matching.institution.isNotEmpty) {
      _selectedInstitution = matching.institution;
    }
    _autoAdjustGroupForSubject(_selectedSubject);

    if (_targetSpecificStudents) {
      _loadEligibleStudents();
    }
  }

  Future<void> _loadEligibleStudents() async {
    if (_selectedStandard == null || _selectedDivision == null || _selectedMedium == null) return;

    setState(() => _isLoadingStudents = true);
    try {
      final list = await _supabase.getStudentsForSection(
        institution: _selectedInstitution ?? 'Sharda Mandir',
        standard: _selectedStandard!,
        division: _selectedDivision!,
        medium: _selectedMedium!,
        studentGroup: _selectedGroup,
      );

      if (mounted) {
        setState(() {
          _eligibleStudents = list;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
      }
    }
  }

  void _showStudentSelectionDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final filtered = _eligibleStudents.where((s) {
              final q = searchQuery.toLowerCase();
              if (q.isEmpty) return true;
              final name = (s.name ?? '').toLowerCase();
              final roll = (s.rollNo ?? '').toLowerCase();
              return name.contains(q) || roll.contains(q);
            }).toList();

            final allSelected = filtered.isNotEmpty &&
                filtered.every((s) => _selectedStudentIds.contains(s.id));

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.people_alt_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Eligible Students',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${_selectedStudentIds.length} chosen',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by student name or roll...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) {
                        setDialogState(() => searchQuery = val.trim());
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                            size: 16,
                          ),
                          label: Text(allSelected ? 'Deselect All' : 'Select All Filtered'),
                          onPressed: () {
                            setDialogState(() {
                              setState(() {
                                if (allSelected) {
                                  for (var s in filtered) {
                                    _selectedStudentIds.remove(s.id);
                                  }
                                } else {
                                  for (var s in filtered) {
                                    _selectedStudentIds.add(s.id);
                                  }
                                }
                              });
                            });
                          },
                        ),
                        Text(
                          'Total: ${_eligibleStudents.length}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No enrolled students found matching this section.',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (c, i) {
                                final student = filtered[i];
                                final isChecked = _selectedStudentIds.contains(student.id);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(student.name ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    'Roll: ${student.rollNo ?? "N/A"} • Group: ${student.studentGroup ?? "Both"}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  value: isChecked,
                                  onChanged: (val) {
                                    setDialogState(() {
                                      setState(() {
                                        if (val == true) {
                                          _selectedStudentIds.add(student.id);
                                        } else {
                                          _selectedStudentIds.remove(student.id);
                                        }
                                      });
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _detectUrlType(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return 'youtube';
    }
    if (lower.contains('drive.google.com') || lower.contains('docs.google.com')) {
      return 'drive';
    }
    return 'link';
  }

  Future<void> _testLaunchUrl() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a link first')),
      );
      return;
    }

    var normalized = rawUrl;
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL format'), backgroundColor: AppColors.error),
      );
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link in browser'), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch link: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSubject == null ||
        _selectedStandard == null ||
        _selectedDivision == null ||
        _selectedMedium == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an assigned Subject, Standard, Division, and Medium'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_targetSpecificStudents && _selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You selected "Specific Students" but haven\'t chosen any students yet.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    var rawUrl = _urlController.text.trim();
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    final user = _supabase.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication error: teacher not logged in')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final teacherName = user.userMetadata?['name'] as String? ??
          user.userMetadata?['full_name'] as String? ??
          'Teacher';

      final detectedType = _detectUrlType(rawUrl);
      final assignedList = _targetSpecificStudents ? _selectedStudentIds.toList() : null;

      if (_isEditing) {
        final updated = widget.material!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          url: rawUrl,
          materialType: detectedType,
          subject: _selectedSubject!,
          standard: _selectedStandard!,
          medium: _selectedMedium!,
          division: _selectedDivision!,
          studentGroup: _selectedGroup,
          institution: _selectedInstitution ?? 'Sharda Mandir',
          assignedStudentIds: assignedList,
          updatedAt: DateTime.now(),
        );
        await _supabase.updateStudyMaterial(updated);
      } else {
        final newMaterial = StudyMaterial(
          id: '',
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          url: rawUrl,
          materialType: detectedType,
          subject: _selectedSubject!,
          teacherId: user.id,
          teacherName: teacherName,
          standard: _selectedStandard!,
          medium: _selectedMedium!,
          division: _selectedDivision!,
          studentGroup: _selectedGroup,
          institution: _selectedInstitution ?? 'Sharda Mandir',
          assignedStudentIds: assignedList,
          createdAt: DateTime.now(),
        );
        await _supabase.createStudyMaterial(newMaterial);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Material updated successfully' : 'Study material shared successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detectedType = _detectUrlType(_urlController.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Study Material' : 'Upload Study Material'),
        actions: [
          if (!_isSaving && !_isLoadingAssignments && _assignments.isNotEmpty)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              label: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: AppGradientBackground(
        child: AnimatedPage(
          child: _isLoadingAssignments
              ? const Center(child: SpinKitFadingCircle(color: AppColors.primary, size: 44))
              : _assignments.isEmpty
                  ? _buildNoAssignmentsView()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Material URL Card
                            _buildUrlCard(detectedType),

                            const SizedBox(height: 16),

                            // Material Details Card
                            _buildDetailsCard(),

                            const SizedBox(height: 16),

                            // Assigned Teaching Scope Card (Strictly assigned by admin)
                            _buildAssignedScopeCard(),

                            const SizedBox(height: 16),

                            // Student Targeting Card (All in section vs Specific students)
                            _buildStudentTargetCard(),

                            const SizedBox(height: 24),

                            // Save Button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isSaving ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isSaving
                                    ? const SpinKitThreeBounce(color: Colors.white, size: 24)
                                    : Text(
                                        _isEditing ? 'Update Study Material' : 'Share with Assigned Students',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildNoAssignmentsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_late_rounded, size: 48, color: AppColors.warning),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Teaching Assignments Found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can only upload and share study materials for subjects, standards, and divisions assigned to you by the Admin.\n\nPlease contact the administrator to configure your teaching assignments.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlCard(String detectedType) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.link_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resource URL / Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Paste Google Drive document or YouTube video link', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (detectedType == 'youtube')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_fill_rounded, color: Colors.red, size: 14),
                      SizedBox(width: 4),
                      Text('YouTube', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else if (detectedType == 'drive')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_done_rounded, color: Colors.blue, size: 14),
                      SizedBox(width: 4),
                      Text('Google Drive', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Link URL *',
              hintText: 'https://youtube.com/watch?v=... or https://drive.google.com/...',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: _urlController.text.trim().isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      tooltip: 'Test Link',
                      onPressed: _testLaunchUrl,
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.url,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Please enter a URL';
              if (!val.trim().contains('.')) return 'Please enter a valid URL';
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            detectedType == 'drive'
                ? 'Note: Ensure Google Drive file sharing is set to "Anyone with the link can view".'
                : 'Tip: You can share PDFs, revision notes, homework sheets, or video lectures.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Material Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Title *',
              hintText: 'e.g. Chapter 4 Motion in a Plane - PYQ Notes',
              prefixIcon: const Icon(Icons.title_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Please provide a title';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Instructions / Description (Optional)',
              hintText: 'Add instructions, topics covered, homework questions...',
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedScopeCard() {
    final subjects = _assignedSubjects;
    final standards = _assignedStandards;
    final divisions = _assignedDivisions;
    final mediums = _assignedMediums;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Assigned Class & Subject Scope',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (_selectedInstitution != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _selectedInstitution!,
                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Options are restricted strictly to your assigned teaching classes.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // 1. Assigned Subject Dropdown
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _selectedSubject != null && subjects.contains(_selectedSubject) ? _selectedSubject : null,
            decoration: InputDecoration(
              labelText: 'Assigned Subject *',
              prefixIcon: const Icon(Icons.menu_book_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: subjects
                .map((sub) => DropdownMenuItem(
                      value: sub,
                      child: Text(sub, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedSubject = val;
                  // reset standard/division/medium if no longer valid
                  final validStds = _assignedStandards;
                  if (!validStds.contains(_selectedStandard)) {
                    _selectedStandard = validStds.isNotEmpty ? validStds.first : null;
                  }
                  final validDivs = _assignedDivisions;
                  if (!validDivs.contains(_selectedDivision)) {
                    _selectedDivision = validDivs.isNotEmpty ? validDivs.first : null;
                  }
                  final validMeds = _assignedMediums;
                  if (!validMeds.contains(_selectedMedium)) {
                    _selectedMedium = validMeds.isNotEmpty ? validMeds.first : null;
                  }
                  _onSectionChanged();
                });
              }
            },
            validator: (v) => v == null ? 'Please choose your assigned subject' : null,
          ),
          const SizedBox(height: 14),

          // 2. Standard & Medium in a row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedStandard != null && standards.contains(_selectedStandard) ? _selectedStandard : null,
                  decoration: InputDecoration(
                    labelText: 'Standard *',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: standards
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text('Std $s', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedStandard = val;
                        final validDivs = _assignedDivisions;
                        if (!validDivs.contains(_selectedDivision)) {
                          _selectedDivision = validDivs.isNotEmpty ? validDivs.first : null;
                        }
                        final validMeds = _assignedMediums;
                        if (!validMeds.contains(_selectedMedium)) {
                          _selectedMedium = validMeds.isNotEmpty ? validMeds.first : null;
                        }
                        _onSectionChanged();
                      });
                    }
                  },
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedMedium != null && mediums.contains(_selectedMedium) ? _selectedMedium : null,
                  decoration: InputDecoration(
                    labelText: 'Medium *',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: mediums
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedMedium = val;
                        _onSectionChanged();
                      });
                    }
                  },
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. Division & Group in a row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedDivision != null && divisions.contains(_selectedDivision) ? _selectedDivision : null,
                  decoration: InputDecoration(
                    labelText: 'Division *',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: divisions
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('Div $d', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedDivision = val;
                        _onSectionChanged();
                      });
                    }
                  },
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedGroup,
                  decoration: InputDecoration(
                    labelText: 'Stream Group *',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Both (Bio & Math)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Biology',
                      child: Text('Biology Group', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Math',
                      child: Text('Math Group', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedGroup = val;
                        _onSectionChanged();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentTargetCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Student Assignment Scope', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Choose whether all enrolled students in this section receive this material, or only selected individuals.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('All Section Students'),
                icon: Icon(Icons.groups_rounded),
              ),
              ButtonSegment(
                value: true,
                label: Text('Selected Students'),
                icon: Icon(Icons.person_pin_rounded),
              ),
            ],
            selected: {_targetSpecificStudents},
            onSelectionChanged: (val) {
              setState(() {
                _targetSpecificStudents = val.first;
                if (_targetSpecificStudents && _eligibleStudents.isEmpty) {
                  _loadEligibleStudents();
                }
              });
            },
          ),
          if (_targetSpecificStudents) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedStudentIds.isEmpty
                              ? 'No students selected yet'
                              : '${_selectedStudentIds.length} student(s) selected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoadingStudents
                              ? 'Loading student list...'
                              : 'Total ${_eligibleStudents.length} students enrolled in this section',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoadingStudents ? null : _showStudentSelectionDialog,
                    icon: const Icon(Icons.checklist_rounded, size: 16),
                    label: const Text('Pick Students'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
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
