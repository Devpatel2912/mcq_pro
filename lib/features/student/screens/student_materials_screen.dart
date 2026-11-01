import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/core/services/supabase_service.dart';
import 'package:mcq_test_app/core/widgets/animated_page.dart';
import 'package:mcq_test_app/core/widgets/app_card.dart';
import 'package:mcq_test_app/core/widgets/app_gradient_background.dart';
import 'package:mcq_test_app/models/study_material.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentMaterialsScreen extends StatefulWidget {
  final String standard;
  final String medium;
  final String division;
  final String studentGroup;
  final String? studentId;
  final String? institution;
  final String? academicYear;

  const StudentMaterialsScreen({
    super.key,
    required this.standard,
    required this.medium,
    required this.division,
    required this.studentGroup,
    this.studentId,
    this.institution,
    this.academicYear,
  });

  @override
  State<StudentMaterialsScreen> createState() => _StudentMaterialsScreenState();
}

class _StudentMaterialsScreenState extends State<StudentMaterialsScreen> {
  final _supabase = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<StudyMaterial> _materials = [];
  bool _isLoading = true;
  String _selectedSubject = 'all';
  String _selectedType = 'all'; // 'all', 'youtube', 'drive'

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.currentUser;
      final currentStudentId = widget.studentId ?? user?.id;

      final list = await _supabase.getStudentStudyMaterials(
        studentId: currentStudentId,
        standard: widget.standard,
        medium: widget.medium,
        division: widget.division,
        studentGroup: widget.studentGroup,
        institution: widget.institution,
        academicYear: widget.academicYear,
      );
      if (mounted) {
        setState(() {
          _materials = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load materials: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<StudyMaterial> get _filteredMaterials {
    final query = _searchController.text.trim().toLowerCase();
    return _materials.where((m) {
      if (_selectedSubject != 'all' && m.subject.toLowerCase() != _selectedSubject.toLowerCase()) {
        return false;
      }
      if (_selectedType == 'youtube' && !m.isYouTube) {
        return false;
      }
      if (_selectedType == 'drive' && !m.isDrive) {
        return false;
      }
      if (query.isNotEmpty) {
        final title = m.title.toLowerCase();
        final desc = (m.description ?? '').toLowerCase();
        final teacher = m.teacherName.toLowerCase();
        final sub = m.subject.toLowerCase();
        if (!title.contains(query) && !desc.contains(query) && !teacher.contains(query) && !sub.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _openLink(StudyMaterial material) async {
    var rawUrl = material.url.trim();
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link URL'), backgroundColor: AppColors.error),
      );
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: rawUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open automatically. Link copied to clipboard!'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: rawUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied to clipboard: $rawUrl'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    IconData? icon,
    Color? iconColor,
    Color? activeColor,
  }) {
    final effectiveActiveColor = activeColor ?? AppColors.primary;
    return ChoiceChip(
      avatar: icon != null
          ? Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : (iconColor ?? effectiveActiveColor),
            )
          : null,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: effectiveActiveColor,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(
        color: selected ? effectiveActiveColor : AppColors.border,
        width: 1,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMaterials;
    final grp = widget.studentGroup.toLowerCase();
    final List<String> subjects = ['all', 'Physics', 'Chemistry'];
    if (grp.contains('bio')) {
      subjects.add('Biology');
    } else if (grp.contains('math')) {
      subjects.add('Mathematics');
    } else {
      subjects.addAll(['Biology', 'Mathematics']);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Materials & Links'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadMaterials,
          ),
        ],
      ),
      body: AppGradientBackground(
        child: AnimatedPage(
          child: Column(
            children: [
              // Search & Filter header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search notes, topics, or teacher...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Type selector pills (All, YouTube, Google Drive)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'All Links',
                            selected: _selectedType == 'all',
                            onSelected: () => setState(() => _selectedType = 'all'),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'YouTube Videos',
                            icon: Icons.play_circle_fill_rounded,
                            iconColor: Colors.red,
                            activeColor: const Color(0xFFDC2626),
                            selected: _selectedType == 'youtube',
                            onSelected: () => setState(() => _selectedType = 'youtube'),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Drive Files / Notes',
                            icon: Icons.cloud_done_rounded,
                            iconColor: const Color(0xFF2563EB),
                            activeColor: const Color(0xFF2563EB),
                            selected: _selectedType == 'drive',
                            onSelected: () => setState(() => _selectedType = 'drive'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subject filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: subjects.map((sub) {
                          final isSelected = _selectedSubject.toLowerCase() == sub.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFilterChip(
                              label: sub == 'all' ? 'All Subjects' : sub,
                              selected: isSelected,
                              onSelected: () {
                                setState(() {
                                  _selectedSubject = isSelected ? 'all' : sub;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Content List
              Expanded(
                child: _isLoading
                    ? const Center(child: SpinKitFadingCircle(color: AppColors.primary, size: 44))
                    : filtered.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadMaterials,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (ctx, index) {
                                return _buildMaterialCard(filtered[index]);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialCard(StudyMaterial material) {
    Color typeColor = AppColors.primary;
    IconData typeIcon = Icons.link_rounded;
    String typeLabel = 'Resource Link';

    if (material.isYouTube) {
      typeColor = const Color(0xFFDC2626);
      typeIcon = Icons.play_circle_fill_rounded;
      typeLabel = 'YouTube Video';
    } else if (material.isDrive) {
      typeColor = const Color(0xFF2563EB);
      typeIcon = Icons.cloud_done_rounded;
      typeLabel = 'Google Drive File';
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeIcon, color: typeColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            material.subject,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (material.description != null && material.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              material.description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_rounded, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    material.teacherName,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openLink(material),
                icon: Icon(
                  material.isYouTube ? Icons.play_arrow_rounded : Icons.open_in_new_rounded,
                  size: 16,
                ),
                label: Text(material.isYouTube ? 'Watch Video' : 'Open Link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: typeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 54,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Study Materials Assigned Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'When your assigned teachers share Google Drive notes, revision PDFs, or YouTube lecture links for your class, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
