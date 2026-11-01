import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';
import 'package:mcq_test_app/core/services/supabase_service.dart';
import 'package:mcq_test_app/core/widgets/animated_page.dart';
import 'package:mcq_test_app/core/widgets/app_card.dart';
import 'package:mcq_test_app/core/widgets/app_gradient_background.dart';
import 'package:mcq_test_app/features/teacher/screens/teacher_add_edit_material_screen.dart';
import 'package:mcq_test_app/models/study_material.dart';
import 'package:url_launcher/url_launcher.dart';

class TeacherMaterialsScreen extends StatefulWidget {
  const TeacherMaterialsScreen({super.key});

  @override
  State<TeacherMaterialsScreen> createState() => _TeacherMaterialsScreenState();
}

class _TeacherMaterialsScreenState extends State<TeacherMaterialsScreen> {
  final _supabase = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<StudyMaterial> _materials = [];
  bool _isLoading = true;
  String _selectedSubject = 'all'; // 'all', 'Physics', 'Chemistry', 'Biology', 'Math'
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
    final user = _supabase.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _supabase.getTeacherMaterials(user.id);
    if (mounted) {
      setState(() {
        _materials = list;
        _isLoading = false;
      });
    }
  }

  List<StudyMaterial> get _filteredMaterials {
    final query = _searchController.text.trim().toLowerCase();
    return _materials.where((m) {
      // Subject filter
      if (_selectedSubject != 'all' && m.subject.toLowerCase() != _selectedSubject.toLowerCase()) {
        return false;
      }

      // Type filter
      if (_selectedType == 'youtube' && !m.isYouTube) return false;
      if (_selectedType == 'drive' && !m.isDrive) return false;

      // Search query
      if (query.isNotEmpty) {
        final title = m.title.toLowerCase();
        final desc = (m.description ?? '').toLowerCase();
        final sub = m.subject.toLowerCase();
        final scope = m.scopeDisplay.toLowerCase();
        return title.contains(query) || desc.contains(query) || sub.contains(query) || scope.contains(query);
      }
      return true;
    }).toList();
  }

  Future<void> _openLink(String urlString) async {
    final cleanUrl = urlString.trim();
    if (cleanUrl.isEmpty) return;
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid link URL'), backgroundColor: AppColors.error),
      );
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        // Fallback to platform default
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _deleteMaterial(StudyMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Study Material?'),
        content: Text('Are you sure you want to remove "${material.title}"? Students will no longer have access to this link.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.deleteStudyMaterial(material.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Material removed successfully'), backgroundColor: AppColors.success),
          );
        }
        _loadMaterials();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _navigateAddEdit([StudyMaterial? material]) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherAddEditMaterialScreen(material: material),
      ),
    );
    if (updated == true) {
      _loadMaterials();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMaterials;

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateAddEdit(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Material', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: AppGradientBackground(
        child: AnimatedPage(
          child: RefreshIndicator(
            onRefresh: _loadMaterials,
            child: Column(
              children: [
                // Search and Filters Bar
                _buildSearchAndFilters(),

                // List of Materials
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                return _buildMaterialCard(filtered[index]);
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Search input
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search material title, subject, standard...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Type filters
                _filterChip(label: 'All Types', selected: _selectedType == 'all', onSelected: () => setState(() => _selectedType = 'all')),
                const SizedBox(width: 6),
                _filterChip(label: 'YouTube', icon: Icons.play_circle_fill_rounded, color: const Color(0xFFFF0000), selected: _selectedType == 'youtube', onSelected: () => setState(() => _selectedType = 'youtube')),
                const SizedBox(width: 6),
                _filterChip(label: 'Google Drive', icon: Icons.add_to_drive_rounded, color: const Color(0xFF0F9D58), selected: _selectedType == 'drive', onSelected: () => setState(() => _selectedType = 'drive')),
                const SizedBox(width: 12),
                Container(width: 1, height: 24, color: AppColors.border),
                const SizedBox(width: 12),

                // Subject filters
                _filterChip(label: 'All Subjects', selected: _selectedSubject == 'all', onSelected: () => setState(() => _selectedSubject = 'all')),
                const SizedBox(width: 6),
                _filterChip(label: 'Physics', selected: _selectedSubject == 'Physics', onSelected: () => setState(() => _selectedSubject = 'Physics')),
                const SizedBox(width: 6),
                _filterChip(label: 'Chemistry', selected: _selectedSubject == 'Chemistry', onSelected: () => setState(() => _selectedSubject = 'Chemistry')),
                const SizedBox(width: 6),
                _filterChip(label: 'Biology', selected: _selectedSubject == 'Biology', onSelected: () => setState(() => _selectedSubject = 'Biology')),
                const SizedBox(width: 6),
                _filterChip(label: 'Math', selected: _selectedSubject == 'Math', onSelected: () => setState(() => _selectedSubject = 'Math')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    IconData? icon,
    Color? color,
  }) {
    return ChoiceChip(
      avatar: icon != null ? Icon(icon, size: 16, color: selected ? Colors.white : (color ?? AppColors.primary)) : null,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
        color: selected ? Colors.white : AppColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
    );
  }

  Widget _buildMaterialCard(StudyMaterial material) {
    Color typeColor = AppColors.primary;
    IconData typeIcon = Icons.link_rounded;

    if (material.isYouTube) {
      typeColor = const Color(0xFFFF0000);
      typeIcon = Icons.play_circle_fill_rounded;
    } else if (material.isDrive) {
      typeColor = const Color(0xFF0F9D58);
      typeIcon = Icons.add_to_drive_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Type Badge + Scope Badge + Popup Menu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 5),
                      Text(
                        material.typeDisplay,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    material.subject,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _navigateAddEdit(material);
                    } else if (val == 'delete') {
                      _deleteMaterial(material);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Details'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Delete Material', style: TextStyle(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Material Title
            Text(
              material.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),

            // Description / Notes
            if (material.description != null && material.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                material.description!.trim(),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Target Scope Badge
            Row(
              children: [
                const Icon(Icons.school_outlined, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    material.scopeDisplay,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),

            // Bottom Actions: Copy Link & Open Link Button
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: material.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied to clipboard!'), duration: Duration(seconds: 2)),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              material.url,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _openLink(material.url),
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('Open'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: typeColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.video_library_outlined, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Study Materials Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share Google Drive documents, question banks, or YouTube lecture videos with your assigned students.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _navigateAddEdit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Study Material'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
