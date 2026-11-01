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

class AdminMaterialsScreen extends StatefulWidget {
  const AdminMaterialsScreen({super.key});

  @override
  State<AdminMaterialsScreen> createState() => _AdminMaterialsScreenState();
}

class _AdminMaterialsScreenState extends State<AdminMaterialsScreen> {
  final _supabase = SupabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<StudyMaterial> _materials = [];
  bool _isLoading = true;

  String _selectedSubject = 'all';
  String _selectedType = 'all'; // 'all', 'youtube', 'drive'
  String _selectedStandard = 'all'; // 'all', '11', '12'
  String _selectedInstitution = 'all'; // 'all', 'Sharda Mandir', 'Tuition ACC'

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
      final list = await _supabase.getAllStudyMaterials();
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
          SnackBar(content: Text('Failed to load study materials: $e'), backgroundColor: AppColors.error),
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
      if (_selectedStandard != 'all' && m.standard != _selectedStandard) {
        return false;
      }
      if (_selectedInstitution != 'all') {
        final isAcc = _selectedInstitution.toLowerCase().contains('acc');
        final mAcc = m.institution.toLowerCase().contains('acc');
        if (isAcc != mAcc) return false;
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
            const SnackBar(content: Text('Could not open automatically. Link copied!'), backgroundColor: AppColors.primary),
          );
        }
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: rawUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link copied to clipboard: $rawUrl'), backgroundColor: AppColors.primary),
        );
      }
    }
  }

  Future<void> _deleteMaterial(StudyMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Study Material?'),
        content: Text('Are you sure you want to permanently remove "${material.title}" uploaded by ${material.teacherName}? Students will lose access immediately.'),
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
            const SnackBar(content: Text('Material deleted successfully'), backgroundColor: AppColors.success),
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

  void _showEditDialog(StudyMaterial material) {
    final titleController = TextEditingController(text: material.title);
    final descController = TextEditingController(text: material.description ?? '');
    final urlController = TextEditingController(text: material.url);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Study Material'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'URL Link *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newTitle = titleController.text.trim();
              final newUrl = urlController.text.trim();
              if (newTitle.isEmpty || newUrl.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Title and URL cannot be empty')),
                );
                return;
              }

              final updated = material.copyWith(
                title: newTitle,
                url: newUrl,
                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                updatedAt: DateTime.now(),
              );

              try {
                await _supabase.updateStudyMaterial(updated);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Material updated'), backgroundColor: AppColors.success),
                  );
                  _loadMaterials();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMaterials;
    final subjects = ['all', 'Physics', 'Chemistry', 'Biology', 'Mathematics'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Study Materials'),
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
              // Filters Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search title, teacher, or notes...',
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Type & Standard filter row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All Types'),
                            selected: _selectedType == 'all',
                            onSelected: (val) {
                              if (val) setState(() => _selectedType = 'all');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.play_circle_fill_rounded, color: Colors.red, size: 18),
                            label: const Text('YouTube'),
                            selected: _selectedType == 'youtube',
                            selectedColor: Colors.red.withOpacity(0.18),
                            onSelected: (val) {
                              if (val) setState(() => _selectedType = 'youtube');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.cloud_done_rounded, color: Colors.blue, size: 18),
                            label: const Text('Google Drive'),
                            selected: _selectedType == 'drive',
                            selectedColor: Colors.blue.withOpacity(0.18),
                            onSelected: (val) {
                              if (val) setState(() => _selectedType = 'drive');
                            },
                          ),
                          const SizedBox(width: 14),
                          ChoiceChip(
                            label: const Text('All Standards'),
                            selected: _selectedStandard == 'all',
                            onSelected: (val) {
                              if (val) setState(() => _selectedStandard = 'all');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Std 11'),
                            selected: _selectedStandard == '11',
                            onSelected: (val) {
                              if (val) setState(() => _selectedStandard = '11');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Std 12'),
                            selected: _selectedStandard == '12',
                            onSelected: (val) {
                              if (val) setState(() => _selectedStandard = '12');
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subject filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: subjects.map((sub) {
                          final isSelected = _selectedSubject.toLowerCase() == sub.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(sub == 'all' ? 'All Subjects' : sub),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  _selectedSubject = val ? sub : 'all';
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

              // Materials List
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
      typeColor = Colors.red;
      typeIcon = Icons.play_circle_fill_rounded;
      typeLabel = 'YouTube Video';
    } else if (material.isDrive) {
      typeColor = Colors.blue;
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _tag(material.subject, AppColors.primary),
                        _tag(material.scopeDisplay, const Color(0xFF6366F1)),
                        _tag(material.institution, Colors.teal),
                        Text(
                          typeLabel,
                          style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) {
                  if (val == 'open') _openLink(material);
                  if (val == 'edit') _showEditDialog(material);
                  if (val == 'delete') _deleteMaterial(material);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'open', child: Row(children: [Icon(Icons.open_in_new_rounded, size: 18), SizedBox(width: 8), Text('Open / Test Link')])),
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 8), Text('Edit Material')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error), SizedBox(width: 8), Text('Delete Material', style: TextStyle(color: AppColors.error))])),
                ],
              ),
            ],
          ),
          if (material.description != null && material.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              material.description!,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
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
                    'Teacher: ${material.teacherName}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _openLink(material),
                icon: Icon(material.isYouTube ? Icons.play_arrow_rounded : Icons.open_in_new_rounded, size: 16),
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

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
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
              child: const Icon(Icons.menu_book_rounded, size: 54, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Study Materials Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'No study materials have been uploaded yet or no records match your current search filters.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

