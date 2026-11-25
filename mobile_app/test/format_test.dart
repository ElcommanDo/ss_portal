import 'package:flutter_test/flutter_test.dart';
import 'package:smart_system_timesheet/core/format.dart';
import 'package:smart_system_timesheet/core/models.dart';

void main() {
  test('hours are shown like the portal stores them', () {
    expect(Fmt.hm(2.3333), '2h 20m');
    expect(Fmt.hm(8), '8h');
    expect(Fmt.hm(0.5), '30m');
    expect(Fmt.dec(7.5), '7.5');
    expect(Fmt.dec(8), '8');
    expect(Fmt.dec(2.3333), '2.33');
  });

  test('12h time labels', () {
    expect(Fmt.time12('09:05'), '9:05 AM');
    expect(Fmt.time12('17:30'), '5:30 PM');
    expect(Fmt.time12('00:15'), '12:15 AM');
  });

  test('page parsing is defensive', () {
    final page = PageResult.parse<UserBrief>({
      'count': 1,
      'page': 1,
      'pages': 1,
      'results': [
        {'id': 3, 'username': 'aibrahim', 'full_name': 'Ahmed Ibrahim', 'role': 'leader'}
      ],
    }, UserBrief.fromJson);
    expect(page.results.single.initials, 'AI');
    expect(page.hasMore, isFalse);
  });
}
