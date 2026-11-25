enum TestStatus { draft, published }

class Test {
  final String id;
  final String? testCode;
  final String? title;
  final String teacherId;
  final String studentClass;
  final String? division;
  final String medium;
  final String subject;
  final String topic;
  final String level;
  final int duration;
  final TestStatus status;
  final DateTime? createdAt;

  Test({
    this.id = '',
    this.testCode,
    this.title,
    required this.teacherId,
    required this.studentClass,
    this.division,
    required this.medium,
    required this.subject,
    required this.topic,
    required this.level,
    required this.duration,
    required this.status,
    this.createdAt,
  });

  factory Test.fromMap(Map<String, dynamic> map) {
    TestStatus parseStatus(dynamic val) {
      if (val == null) return TestStatus.published;
      final str = val.toString().toLowerCase();
      if (str == 'draft') return TestStatus.draft;
      return TestStatus.published;
    }

    int parseDuration(dynamic val) {
      if (val is int) return val;
      return int.tryParse(val?.toString() ?? '') ?? 30;
    }

    String? title = map['title']?.toString();
    String topic = map['topic']?.toString() ?? 'Untitled';
    if ((title == null || title.isEmpty) && topic.contains(':::title:')) {
      final parts = topic.split(':::title:');
      topic = parts[0];
      title = parts[1];
    }

    return Test(
      id: map['id']?.toString() ?? '',
      testCode: map['test_code']?.toString(),
      title: title,
      teacherId: map['teacher_id']?.toString() ?? '',
      studentClass: (map['class'] ?? '11').toString(),
      division: map['division']?.toString(),
      medium: map['medium']?.toString() ?? 'English',
      subject: map['subject']?.toString() ?? 'General',
      topic: topic,
      level: map['level']?.toString() ?? 'Medium',
      duration: parseDuration(map['duration']),
      status: parseStatus(map['status']),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'test_code': testCode,
      'teacher_id': teacherId,
      'class': studentClass,
      'division': division,
      'medium': medium,
      'subject': subject,
      'topic': topic,
      'level': level,
      'duration': duration,
      'status': status.name,
    };
    if (title != null && title!.trim().isNotEmpty) {
      map['title'] = title!.trim();
    }
    return map;
  }

  Test copyWith({
    String? id,
    String? testCode,
    String? title,
    String? teacherId,
    String? studentClass,
    String? division,
    String? medium,
    String? subject,
    String? topic,
    String? level,
    int? duration,
    TestStatus? status,
    DateTime? createdAt,
  }) {
    return Test(
      id: id ?? this.id,
      testCode: testCode ?? this.testCode,
      title: title ?? this.title,
      teacherId: teacherId ?? this.teacherId,
      studentClass: studentClass ?? this.studentClass,
      division: division ?? this.division,
      medium: medium ?? this.medium,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      level: level ?? this.level,
      duration: duration ?? this.duration,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
