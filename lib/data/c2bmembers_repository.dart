import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/models/c2bmembers_model.dart';

/// Откуда взят список банков
enum C2bmembersSource {
  /// загружен с сервера
  network,

  /// взят из кэша, TTL не истёк
  cache,

  /// сервер недоступен, взят просроченный кэш
  staleCache,

  /// сервер и кэш недоступны, взят встроенный снимок c2bmembersData
  bundled,
}

/// Результат загрузки списка банков
class C2bmembersLoadResult {
  final C2bmembersModel model;
  final C2bmembersSource source;

  /// время загрузки данных с сервера; null для встроенного снимка
  final DateTime? fetchedAt;

  const C2bmembersLoadResult(this.model, this.source, this.fetchedAt);
}

/// Запись в кэше: сырой ответ сервера и время загрузки
class C2bmembersCacheEntry {
  final String url;
  final String body;
  final DateTime fetchedAt;

  const C2bmembersCacheEntry({required this.url, required this.body, required this.fetchedAt});
}

/// Хранилище кэша списка банков. По умолчанию [FileC2bmembersCache].
abstract class C2bmembersCache {
  Future<C2bmembersCacheEntry?> read();

  Future<void> write(C2bmembersCacheEntry entry);
}

/// Кэш в файле в каталоге поддержки приложения (path_provider)
class FileC2bmembersCache implements C2bmembersCache {
  final Future<Directory> Function() _directory;
  final String fileName;

  FileC2bmembersCache({Future<Directory> Function()? directory, this.fileName = 'sbp_c2bmembers_cache.json'})
      : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> get _file async => File('${(await _directory()).path}/$fileName');

  @override
  Future<C2bmembersCacheEntry?> read() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final fetchedAt = DateTime.tryParse('${json['fetchedAt']}');
      final body = json['body'];
      if (fetchedAt == null || body is! String) return null;
      return C2bmembersCacheEntry(url: '${json['url']}', body: body, fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(C2bmembersCacheEntry entry) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'url': entry.url,
      'fetchedAt': entry.fetchedAt.toUtc().toIso8601String(),
      'body': entry.body,
    }));
  }
}

/// Кэш в памяти: для тестов или если хранить данные на диске не нужно
class MemoryC2bmembersCache implements C2bmembersCache {
  C2bmembersCacheEntry? entry;

  MemoryC2bmembersCache([this.entry]);

  @override
  Future<C2bmembersCacheEntry?> read() async => entry;

  @override
  Future<void> write(C2bmembersCacheEntry entry) async => this.entry = entry;
}

/// Загрузка списка банков СБП с сервера с кэшем и fallback на встроенный снимок.
///
/// Порядок: свежий кэш (моложе [ttl]) → сервер → просроченный кэш → встроенный [c2bmembersData].
/// Метод [load] не бросает исключений: в худшем случае возвращается встроенный снимок.
class C2bmembersRepository {
  /// официальный реестр НСПК. Для продакшена рекомендуем свой прокси.
  static const defaultUrl = 'https://qr.nspk.ru/proxyapp/c2bmembers.json';

  final Uri url;
  final Duration timeout;
  final Duration ttl;
  final C2bmembersCache cache;
  final http.Client? _client;
  final DateTime Function() _now;

  C2bmembersRepository({
    String url = defaultUrl,
    this.timeout = const Duration(seconds: 10),
    this.ttl = const Duration(hours: 24),
    C2bmembersCache? cache,
    http.Client? client,
    DateTime Function()? now,
  })  : url = Uri.parse(url),
        cache = cache ?? FileC2bmembersCache(),
        _client = client,
        _now = now ?? DateTime.now;

  /// [forceRefresh] - игнорировать свежий кэш и сразу идти на сервер
  Future<C2bmembersLoadResult> load({bool forceRefresh = false}) async {
    final cached = await _readCache();
    if (!forceRefresh && cached != null && _now().difference(cached.entry.fetchedAt) < ttl) {
      return C2bmembersLoadResult(cached.model, C2bmembersSource.cache, cached.entry.fetchedAt);
    }

    final fetched = await _fetch();
    if (fetched != null) {
      try {
        await cache.write(fetched.entry);
      } catch (_) {
        // кэш - оптимизация, ошибка записи не должна ломать загрузку
      }
      return C2bmembersLoadResult(fetched.model, C2bmembersSource.network, fetched.entry.fetchedAt);
    }

    if (cached != null) {
      return C2bmembersLoadResult(cached.model, C2bmembersSource.staleCache, cached.entry.fetchedAt);
    }
    return C2bmembersLoadResult(C2bmembersModel.fromJson(c2bmembersData), C2bmembersSource.bundled, null);
  }

  Future<_Parsed?> _readCache() async {
    try {
      final entry = await cache.read();
      // кэш другого url не используем
      if (entry == null || entry.url != url.toString()) return null;
      final model = _parse(entry.body);
      return model == null ? null : _Parsed(entry, model);
    } catch (_) {
      return null;
    }
  }

  Future<_Parsed?> _fetch() async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(url).timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final model = _parse(body);
      if (model == null) return null;
      return _Parsed(C2bmembersCacheEntry(url: url.toString(), body: body, fetchedAt: _now()), model);
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// null, если ответ не похож на реестр банков: тогда лучше взять кэш или снимок
  static C2bmembersModel? _parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final dictionary = json['dictionary'];
      if (dictionary is List) {
        for (final bank in dictionary) {
          // в ответе сервера нет локальных иконок плагина - берём их из встроенного снимка
          if (bank is Map && bank['icon'] == null) {
            final icon = _bundledIcons[bank['schema']];
            if (icon != null) bank['icon'] = icon;
          }
        }
      }
      final model = C2bmembersModel.fromJson(Map<String, dynamic>.from(json));
      final valid = model.c2bmembersModel.where((bank) => bank.schema.isNotEmpty).toList();
      if (valid.isEmpty) return null;
      model.c2bmembersModel = valid;
      return model;
    } catch (_) {
      return null;
    }
  }
}

final Map<Object?, Object?> _bundledIcons = {
  for (final bank in (c2bmembersData['dictionary'] as List).cast<Map<String, Object?>>())
    if (bank['icon'] != null) bank['schema']: bank['icon'],
};

class _Parsed {
  final C2bmembersCacheEntry entry;
  final C2bmembersModel model;

  _Parsed(this.entry, this.model);
}
