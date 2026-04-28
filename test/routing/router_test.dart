import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/net/http.dart';
import 'package:tripping/places/polyline.dart';
import 'package:tripping/routing/router.dart';

final at = DateTime.utc(2026, 10, 29, 6);
const here = (12.9763, 77.5929);
const there = (12.9716, 77.6412);

String trip(List<List<(double, double)>> legs, {double km = 8.669}) =>
    jsonEncode({
      'trip': {
        'status': 0,
        'summary': {'length': km, 'time': 1775.7},
        'legs': [
          for (final leg in legs) {'shape': encodePolyline(leg)},
        ],
      },
    });

void main() {
  test('a road route keeps its length, time and line, legs joined', () {
    final route = routeFromValhalla((
      status: 200,
      body: trip([
        [here, (12.975, 77.60)],
        [(12.975, 77.60), there],
      ]),
    ), at: at);
    expect(route.kind, RouteKind.road);
    expect(route.provider, 'valhalla');
    expect(route.meters, closeTo(8669, 0.01));
    expect(route.seconds, closeTo(1775.7, 0.01));
    expect(route.points, [here, (12.975, 77.60), there]);
    expect(route.computedAt, at);
  });

  test("Valhalla's refusals become plain words", () {
    RouteError refusal(int code) {
      try {
        routeFromValhalla((
          status: 400,
          body: jsonEncode({'error_code': code, 'error': 'x'}),
        ), at: at);
      } on RouteError catch (error) {
        return error;
      }
      fail('expected a RouteError');
    }

    expect(refusal(442).message, contains('No road route found'));
    expect(refusal(171).message, contains('No road route found'));
    expect(refusal(154).message, contains('Too far'));
    expect(refusal(999).message, contains('not answering'));
  });

  test('asks for car routes on the road and walking ones on foot', () async {
    final costings = <String>[];
    final router = ValhallaRouter(
      baseUrl: 'https://valhalla.test',
      fetch: (uri) async {
        final request = jsonDecode(uri.queryParameters['json']!) as Map;
        costings.add(request['costing'] as String);
        expect(request['locations'], [
          {'lat': here.$1, 'lon': here.$2},
          {'lat': there.$1, 'lon': there.$2},
        ]);
        return (
          status: 200,
          body: trip([
            [here, there],
          ]),
        );
      },
    );
    await router.route(here, there, JourneyMode.road, at: at);
    await router.route(here, there, JourneyMode.expedition, at: at);
    expect(costings, ['auto', 'pedestrian']);
  });

  test('requests are at least a second apart', () async {
    final times = <DateTime>[];
    final router = ValhallaRouter(
      fetch: (_) async {
        times.add(DateTime.now());
        return (
          status: 200,
          body: trip([
            [here, there],
          ]),
        );
      },
    );
    await router.route(here, there, JourneyMode.road, at: at);
    await router.route(here, there, JourneyMode.road, at: at);
    expect(
      times[1].difference(times[0]),
      greaterThanOrEqualTo(const Duration(milliseconds: 990)),
    );
  });

  test('without a connection the error says so', () {
    final router = ValhallaRouter(
      fetch: (_) async => throw const NoConnection(),
    );
    expect(
      router.route(here, there, JourneyMode.road, at: at),
      throwsA(isA<RouteError>().having((e) => e.offline, 'offline', isTrue)),
    );
  });

  test('a straight line is labelled and has no travel time', () {
    final line = PlannedRoute.straight(here, there, at: at);
    expect(line.kind, RouteKind.straight);
    expect(line.seconds, isNull);
    expect(line.points, [here, there]);
    // About 5.2 km across Bengaluru.
    expect(line.meters, closeTo(5240, 60));
  });
}
