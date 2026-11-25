// Kept on purpose: `flutter create .` does not overwrite this file, so it will not
// generate the default counter test that references a non-existent MyApp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_system_timesheet/core/format.dart';
import 'package:smart_system_timesheet/widgets/common.dart';

void main() {
  testWidgets('status chip shows its label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: StatusChip.status('in_progress')))));
    expect(find.text('In Progress'), findsOneWidget);
  });

  testWidgets('stat tile renders value and label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 180,
          child: StatTile(label: 'Logged today', value: '7h 30m', icon: Icons.today_rounded, tone: Tone.info),
        ),
      ),
    ));
    expect(find.text('7h 30m'), findsOneWidget);
    expect(find.text('Logged today'), findsOneWidget);
  });
}
