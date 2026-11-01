class StudyMaterial {
  final String id;
  final String teacherId;
  final String teacherName;
  final String title;
  final String? description;
  final String materialType; // 'youtube', 'drive', 'link'
  final String url;
  final String subject; // 'Physics', 'Chemistry', 'Biology', 'Mathematics'
  final String standard; // '11', '12'
  final String division; // 'A', 'B', 'C', 'ACC'
  final String medium; // 'English', 'Gujarati'
  final String studentGroup; // 'Biology', 'Math', 'all'
  final String institution; // 'Sharda Mandir', 'Tuition ACC'
  final String academicYear;
  final List<String>? assignedStudentIds; // null = entire class section; list = specific students
  final DateTime createdAt;
  final DateTime? updatedAt;

  StudyMaterial({
    this.id = '',
    required this.teacherId,
    this.teacherName = 'Teacher',
    required this.title,
    this.description,
    required this.materialType,
    required this.url,
    required this.subject,
    required this.standard,
    required this.division,
    required this.medium,
    this.studentGroup = 'all',
    this.institution = 'Sharda Mandir',
    this.academicYear = '2026-2027',
    this.assignedStudentIds,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isYouTube {
    final lower = url.trim().toLowerCase();
    return materialType == 'youtube' ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be');
  }

  bool get isDrive {
    final lower = url.trim().toLowerCase();
    return materialType == 'drive' ||
        lower.contains('drive.google.com') ||
        lower.contains('docs.google.com');
  }

  String get typeDisplay {
    if (isYouTube) return 'YouTube Video';
    if (isDrive) return 'Google Drive';
    return 'Web Resource';
  }

  bool get isTargetedToSpecificStudents =>
      assignedStudentIds != null && assignedStudentIds!.isNotEmpty;

  String get scopeDisplay {
    final stdText = 'Std $standard';
    final divText = 'Div $division';
    final medText = ' • $medium';
    final grpText = (studentGroup == 'all' || studentGroup.isEmpty) ? '' : ' • $studentGroup';
    final targetedText = isTargetedToSpecificStudents
        ? ' (${assignedStudentIds!.length} students)'
        : '';
    return '$stdText ($divText)$medText$grpText$targetedText';
  }

  factory StudyMaterial.fromMap(Map<String, dynamic> map) {
    List<String>? parsedStudentIds;
    if (map['assigned_student_ids'] != null) {
      final raw = map['assigned_student_ids'];
      if (raw is List) {
        parsedStudentIds = raw.map((e) => e.toString()).toList();
      }
    }

    return StudyMaterial(
      id: map['id']?.toString() ?? '',
      teacherId: map['teacher_id']?.toString() ?? '',
      teacherName: map['teacher_name']?.toString() ?? 'Teacher',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      materialType: map['material_type']?.toString() ?? 'link',
      url: map['url']?.toString() ?? '',
      subject: map['subject']?.toString() ?? 'General',
      standard: map['standard']?.toString() ?? '11',
      division: map['division']?.toString() ?? 'A',
      medium: map['medium']?.toString() ?? 'English',
      studentGroup: map['student_group']?.toString() ?? 'all',
      institution: map['institution']?.toString() ?? 'Sharda Mandir',
      academicYear: map['academic_year']?.toString() ?? '2026-2027',
      assignedStudentIds: parsedStudentIds,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id.isNotEmpty) 'id': id,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'title': title,
      'description': description,
      'material_type': materialType,
      'url': url,
      'subject': subject,
      'standard': standard,
      'division': division,
      'medium': medium,
      'student_group': studentGroup,
      'institution': institution,
      'academic_year': academicYear,
      'assigned_student_ids': assignedStudentIds,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  StudyMaterial copyWith({
    String? id,
    String? teacherId,
    String? teacherName,
    String? title,
    String? description,
    String? materialType,
    String? url,
    String? subject,
    String? standard,
    String? division,
    String? medium,
    String? studentGroup,
    String? institution,
    String? academicYear,
    List<String>? assignedStudentIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudyMaterial(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      teacherName: teacherName ?? this.teacherName,
      title: title ?? this.title,
      description: description ?? this.description,
      materialType: materialType ?? this.materialType,
      url: url ?? this.url,
      subject: subject ?? this.subject,
      standard: standard ?? this.standard,
      division: division ?? this.division,
      medium: medium ?? this.medium,
      studentGroup: studentGroup ?? this.studentGroup,
      institution: institution ?? this.institution,
      academicYear: academicYear ?? this.academicYear,
      assignedStudentIds: assignedStudentIds ?? this.assignedStudentIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
