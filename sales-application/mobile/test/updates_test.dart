import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracker_app/updates.dart';

AppRelease release(int build, {int minBuild = 0}) => AppRelease(
    version: '1.$build.0', build: build, url: '/media/app/x.apk',
    minBuild: minBuild);

void main() {
  test('nothing on the server, or not newer: no update (#94)', () {
    expect(updateNeed(3, null), UpdateNeed.none);
    expect(updateNeed(3, release(3)), UpdateNeed.none);
    expect(updateNeed(4, release(3)), UpdateNeed.none);
  });

  test('a newer build is offered, and can be put off', () {
    expect(updateNeed(3, release(4)), UpdateNeed.optional);
    expect(updateNeed(3, release(4, minBuild: 3)), UpdateNeed.optional);
  });

  test('below the minimum build, the update is required', () {
    expect(updateNeed(2, release(4, minBuild: 3)), UpdateNeed.required);
  });

  test('reads the server answer', () {
    final r = AppRelease.fromJson(<String, dynamic>{
      'version': '1.2.0', 'build': 3, 'url': '/media/app/a.apk',
      'notes': 'Faster pages', 'min_build': 0, 'size_mb': 56.5,
    });
    expect((r.version, r.build, r.notes, r.sizeMb),
        ('1.2.0', 3, 'Faster pages', 56.5));
  });
}
