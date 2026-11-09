import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_city_renewable_ai/data/services/cloud_run_api.dart';

void main() {
  test(
    'shared requests, force refresh, site parameters, expiry and errors',
    () async {
      var calls = 0;
      var fail = false;
      var now = DateTime(2026, 10, 29, 12, 0);
      final gate = Completer<void>();
      final api = CloudRunApi(
        baseUrl: 'https://example.test',
        clock: () => now,
        client: MockClient((_) async {
          calls++;
          await gate.future;
          return http.Response('{"value":$calls}', fail ? 500 : 200);
        }),
      );
      Future<Map<String, dynamic>> get({
        bool force = false,
        double capacity = 25,
      }) => api.fetchForecast(
        lat: 50.968,
        lon: 71.344,
        days: 7,
        capacityKw: capacity,
        forceRefresh: force,
        retries: 0,
      );
      final a = get();
      final b = get();
      gate.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
      await get();
      expect(calls, 1);
      await get(force: true);
      expect(calls, 2);
      await get(capacity: 30);
      expect(calls, 3);
      now = now.add(const Duration(minutes: 4));
      await get();
      expect(calls, 4);
      now = DateTime(2026, 10, 29, 12, 14);
      await get();
      expect(calls, 5);
      now = DateTime(2026, 10, 29, 12, 15);
      await get();
      expect(calls, 6);
      api.clearCache();
      fail = true;
      await expectLater(get(), throwsA(isA<CloudRunApiException>()));
      fail = false;
      await get();
      expect(calls, 8);
      api.close();
    },
  );

  test('only two active requests and queued calls resume in order', () async {
    final gates = <Completer<void>>[];
    var active = 0;
    var peak = 0;
    final api = CloudRunApi(
      baseUrl: 'https://example.test',
      client: MockClient((r) async {
        active++;
        if (active > peak) peak = active;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        active--;
        return http.Response('{}', 200);
      }),
    );
    final requests = [
      for (var days = 1; days <= 5; days++)
        api.fetchForecast(lat: 1, lon: 2, days: days, retries: 0),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(gates.length, 2);
    for (var i = 0; i < 5; i++) {
      gates[i].complete();
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(requests);
    expect(peak, 2);
    api.close();
  });

  test(
    'optimization cache distinguishes battery settings and explicit rerun',
    () async {
      var calls = 0;
      final api = CloudRunApi(
        baseUrl: 'https://example.test',
        client: MockClient((r) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      Future<Map<String, dynamic>> run(double capacity, {bool force = false}) =>
          api.optimize(
            lat: 1,
            lon: 2,
            days: 7,
            battery: {'battery_capacity_kwh': capacity},
            forceRefresh: force,
          );
      await run(20);
      await run(20);
      expect(calls, 1);
      await run(40);
      expect(calls, 2);
      await run(40, force: true);
      expect(calls, 3);
      api.close();
    },
  );
}
