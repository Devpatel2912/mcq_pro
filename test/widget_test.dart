import 'package:mcq_test_app/core/theme/app_theme.dart';
import 'package:mcq_test_app/features/admin/screens/admin_edit_student_screen.dart';
import 'package:mcq_test_app/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcq_test_app/core/widgets/app_card.dart';
import 'package:mcq_test_app/core/constants/app_colors.dart';

void main() {
  testWidgets('AppCard renders child and responds to tap', (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(
            onTap: () => tapped = true,
            child: const Text('MCQ Pro Card Content'),
          ),
        ),
      ),
    );

    expect(find.text('MCQ Pro Card Content'), findsOneWidget);
    await tester.tap(find.text('MCQ Pro Card Content'));
    expect(tapped, isTrue);
  });

  test('AppColors brand constants check', () {
    expect(AppColors.primary, isNotNull);
    expect(AppColors.secondary, isNotNull);
    expect(AppColors.cardBackground, equals(const Color(0xFFFFFFFF)));
  });

  testWidgets('AdminEditStudentScreen renders properly with AppTheme', (WidgetTester tester) async {
    final mockStudent = AppUser(
      id: 'test-student-id-12345',
      role: 'student',
      email: 'student@example.com',
      name: 'Test Student',
      studentClass: '11',
      division: 'A',
      rollNo: '1',
      studentGroup: 'Biology',
      medium: 'English',
      institution: 'Sharda Mandir',
      academicYear: '2026-2027',
      isActive: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdminEditStudentScreen(student: mockStudent),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Student Data'), findsOneWidget);
    expect(find.text('Personal & Identity Info'), findsOneWidget);
    expect(find.text('Academic & Class Enrollment'), findsOneWidget);
    expect(find.text('Account Controls & Status'), findsOneWidget);
  });
}
