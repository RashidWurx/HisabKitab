import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/features/notifications/data/notification_coordinator.dart';

void main() {
  test('notification taps open the right screen', () {
    expect(routeForPayload('due:abc', null), '/dues/abc');
    expect(routeForPayload('due:abc', 'receive'), '/dues/abc?action=receive');
    expect(routeForPayload('due:abc', 'extend'), '/dues/abc?action=extend');
    expect(routeForPayload('sub:s1', null), '/subscriptions/s1');
    expect(routeForPayload('reminder:r1', null), '/reminders/r1/edit');
    expect(routeForPayload('backup', null), '/more');
    expect(routeForPayload('test', null), '/settings/notifications');
    expect(routeForPayload('weird', null), '/home');
  });
}