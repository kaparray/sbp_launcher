import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sbp_launcher/data/c2bmembers_data.dart';
import 'package:sbp_launcher/data/c2bmembers_repository.dart';

const _url = C2bmembersRepository.defaultUrl;

String _registry(List<String> schemas) => jsonEncode({
      'version': '1.0',
      'dictionary': [
        for (final schema in schemas) {'bankName': schema, 'schema': schema, 'logoURL': ''},
      ],
    });

void main() {
  late DateTime now;
  late int requests;

  setUp(() {
    now = DateTime.utc(2026, 10, 23, 12);
    requests = 0;
  });

  C2bmembersRepository repository({
    required C2bmembersCache cache,
    http.Response Function()? respond,
    String url = _url,
  }) =>
      C2bmembersRepository(
        url: url,
        cache: cache,
        now: () => now,
        timeout: const Duration(milliseconds: 200),
        client: MockClient((request) async {
          requests++;
          expect(request.url.toString(), url);
          if (respond == null) throw const SocketException('offline');
          return respond();
        }),
      );

  C2bmembersCacheEntry entry(List<String> schemas, Duration age, {String url = _url}) =>
      C2bmembersCacheEntry(url: url, body: _registry(schemas), fetchedAt: now.subtract(age));

  test('loads from network and writes the cache', () async {
    final cache = MemoryC2bmembersCache();
    final result =
        await repository(cache: cache, respond: () => http.Response(_registry(['bank1', 'bank2']), 200)).load();

    expect(result.source, C2bmembersSource.network);
    expect(result.model.c2bmembersModel.map((b) => b.schema), ['bank1', 'bank2']);
    expect(cache.entry!.fetchedAt, now);
    expect(cache.entry!.url, _url);
  });

  test('fresh cache is used without a network request', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(entry(['cached'], const Duration(hours: 23))),
      respond: () => http.Response(_registry(['network']), 200),
    ).load();

    expect(requests, 0);
    expect(result.source, C2bmembersSource.cache);
    expect(result.model.c2bmembersModel.single.schema, 'cached');
  });

  test('expired cache is refreshed from network', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(entry(['cached'], const Duration(hours: 25))),
      respond: () => http.Response(_registry(['network']), 200),
    ).load();

    expect(requests, 1);
    expect(result.source, C2bmembersSource.network);
    expect(result.model.c2bmembersModel.single.schema, 'network');
  });

  test('forceRefresh ignores fresh cache', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(entry(['cached'], Duration.zero)),
      respond: () => http.Response(_registry(['network']), 200),
    ).load(forceRefresh: true);

    expect(result.source, C2bmembersSource.network);
  });

  test('network error falls back to stale cache', () async {
    final result = await repository(cache: MemoryC2bmembersCache(entry(['cached'], const Duration(days: 30)))).load();

    expect(result.source, C2bmembersSource.staleCache);
    expect(result.model.c2bmembersModel.single.schema, 'cached');
  });

  test('network error without cache falls back to bundled snapshot', () async {
    final result = await repository(cache: MemoryC2bmembersCache()).load();

    expect(result.source, C2bmembersSource.bundled);
    expect(result.fetchedAt, isNull);
    expect(result.model.c2bmembersModel.length, (c2bmembersData['dictionary'] as List).length);
  });

  for (final response in [
    () => http.Response('Service Unavailable', 503),
    () => http.Response('<html>proxy error</html>', 200),
    () => http.Response('{"dictionary": []}', 200),
  ]) {
    test('invalid response ${response().statusCode} ${response().body} is not cached', () async {
      final cache = MemoryC2bmembersCache();
      final result = await repository(cache: cache, respond: response).load();

      expect(result.source, C2bmembersSource.bundled);
      expect(cache.entry, isNull);
    });
  }

  test('timeout falls back to bundled snapshot', () async {
    final result = await C2bmembersRepository(
      cache: MemoryC2bmembersCache(),
      timeout: const Duration(milliseconds: 50),
      client: MockClient((_) => Future.delayed(const Duration(seconds: 5), () => http.Response('', 200))),
    ).load();

    expect(result.source, C2bmembersSource.bundled);
  });

  test('cache of another url is ignored', () async {
    final result = await repository(
      url: 'https://proxy.example.com/c2bmembers.json',
      cache: MemoryC2bmembersCache(entry(['nspk'], Duration.zero)),
      respond: () => http.Response(_registry(['proxy']), 200),
    ).load();

    expect(result.source, C2bmembersSource.network);
    expect(result.model.c2bmembersModel.single.schema, 'proxy');
  });

  test('corrupted cache is ignored', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(C2bmembersCacheEntry(url: _url, body: 'not json', fetchedAt: now)),
    ).load();

    expect(result.source, C2bmembersSource.bundled);
  });

  test('local icons are taken from the bundled snapshot by schema', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(),
      respond: () => http.Response(_registry(['bank100000000111']), 200),
    ).load();

    expect(result.model.c2bmembersModel.single.icon, 'packages/sbp_launcher/assets/icons/sber.png');
  });

  test('response body is decoded as UTF-8 regardless of headers', () async {
    final result = await repository(
      cache: MemoryC2bmembersCache(),
      respond: () => http.Response.bytes(utf8.encode(_registry(['Сбербанк'])), 200),
    ).load();

    expect(result.model.c2bmembersModel.single.bankName, 'Сбербанк');
  });

  test('FileC2bmembersCache round-trips and tolerates garbage', () async {
    final directory = await Directory.systemTemp.createTemp('sbp_cache_test');
    addTearDown(() => directory.delete(recursive: true));
    final cache = FileC2bmembersCache(directory: () async => directory);

    expect(await cache.read(), isNull);
    await cache.write(entry(['bank1'], Duration.zero));
    final read = await cache.read();
    expect(read!.url, _url);
    expect(read.fetchedAt, now);
    expect(read.body, _registry(['bank1']));

    await File('${directory.path}/${cache.fileName}').writeAsString('garbage');
    expect(await cache.read(), isNull);
  });
}
