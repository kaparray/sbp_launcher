import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sbp/data/c2bmembers_repository.dart';
import 'package:sbp/models/c2bmembers_model.dart';

export 'package:sbp/data/c2bmembers_repository.dart';
export 'package:sbp/models/c2bmembers_model.dart';

/// Результат открытия банка
enum SbpOpenResult {
  /// приложение банка открылось
  opened,

  /// на устройстве нет приложения, которое может открыть ссылку
  notInstalled,

  /// неверные аргументы, неподдерживаемая платформа или ошибка системы
  error,
}

/// Плагин Flutter, с помощью которого можно получить список банков, установленных на устройстве
/// пользователя, а также запустить ссылку для оплаты СБП вида https://qr.nspk.ru/.../
class Sbp {
  static const MethodChannel _channel = MethodChannel('sbp');

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Загрузка списка банков с сервера с кэшем на устройстве.
  /// При ошибке сети возвращается кэш, а без него - встроенный снимок c2bmembersData.
  /// Для контроля над источником данных используйте [C2bmembersRepository] напрямую.
  static Future<C2bmembersModel> loadBanks({
    String url = C2bmembersRepository.defaultUrl,
    Duration ttl = const Duration(hours: 24),
    Duration timeout = const Duration(seconds: 10),
    bool forceRefresh = false,
  }) async {
    final repository = C2bmembersRepository(url: url, ttl: ttl, timeout: timeout);
    return (await repository.load(forceRefresh: forceRefresh)).model;
  }

  /// Получение списка банков, установленных на устройстве пользователя: IOS/Android
  /// передаем модель json, который приходит с https://qr.nspk.ru/proxyapp/c2bmembers.json (C2bmembersModel)
  ///
  /// Android: банк установлен, если есть приложение, которое открывает ссылку `<schema>://qr.nspk.ru`.
  /// iOS: определяются только банки, чьи схемы есть в LSApplicationQueriesSchemes (не больше 50).
  /// Банки, которых нет в результате, всё равно можно открыть через [launchBank].
  static Future<List<C2bmemberModel>> getInstalledBanks(
    C2bmembersModel c2bmembersModel, {
    bool useAndroidLocalIcons = false,
    bool useAndroidLocalNames = false,
  }) async {
    final banks = c2bmembersModel.c2bmembersModel;
    if (_isIOS) {
      final installed = await _channel.invokeListMethod<String>('getInstalledBanks', {
        'schema_applications': banks.map((bank) => bank.schema).toList(),
      });
      final schemas = (installed ?? const <String>[]).toSet();
      return banks.where((bank) => schemas.contains(bank.schema)).toList();
    }
    if (_isAndroid) {
      final installed = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getInstalledBanks', {
        'banks': [
          for (final bank in banks) {'schema': bank.schema, 'package_name': bank.packageName},
        ],
        'use_android_local_icons': useAndroidLocalIcons,
        'use_android_local_names': useAndroidLocalNames,
      });
      final bySchema = {for (final app in installed ?? const <Map<dynamic, dynamic>>[]) app['schema']: app};
      final result = <C2bmemberModel>[];
      for (final bank in banks) {
        final app = bySchema[bank.schema];
        if (app == null) continue;
        bank
          ..installedPackageName = app['package_name'] as String?
          ..bitmap = app['bitmap'] as Uint8List?
          ..localName = app['name'] as String?;
        result.add(bank);
      }
      return result;
    }
    throw UnsupportedError('sbp: getInstalledBanks is supported only on Android and iOS');
  }

  /// Открываем банк: Android/IOS.
  /// [url] - ссылка вида 'https://qr.nspk.ru/...', [bank] - банк из списка (установленный или нет).
  /// Не бросает исключений: результат - [SbpOpenResult].
  static Future<SbpOpenResult> launchBank(String url, C2bmemberModel bank) async {
    try {
      if (_isIOS) {
        return await openBankIOS(url, bank.schema) ? SbpOpenResult.opened : SbpOpenResult.notInstalled;
      }
      if (_isAndroid) {
        final packageName = bank.installedPackageName ?? bank.packageName;
        return await openAndroidBank(bankLink(url, bank.schema), packageName)
            ? SbpOpenResult.opened
            : SbpOpenResult.notInstalled;
      }
      return SbpOpenResult.error;
    } on PlatformException catch (exception) {
      return exception.code == 'NOT_INSTALLED' ? SbpOpenResult.notInstalled : SbpOpenResult.error;
    }
  }

  /// Заменяет https:// или http:// в начале ссылки на схему банка:
  /// https://qr.nspk.ru/AS1... -> bank100000000111://qr.nspk.ru/AS1...
  @visibleForTesting
  static String bankLink(String url, String schema) {
    if (schema.isEmpty) return url;
    final match = RegExp(r'^https?://', caseSensitive: false).firstMatch(url);
    return match == null ? url : '$schema://${url.substring(match.end)}';
  }

  /// открываем банк: Android
  /// отдаем ссылку в виде ('https://qr.nspk.ru/...' deprecated) bank10000000000://qr.nspk.ru/.
  /// package_name: com.example.android (может быть пустым - тогда приложение выберет система).
  /// Бросает PlatformException с кодом NOT_INSTALLED, если ссылку некому открыть.
  static Future<bool> openAndroidBank(
    String url,
    String packageName,
  ) async =>
      await _channel.invokeMethod<bool>(
        'openBank',
        {
          'url': url,
          'package_name': packageName,
        },
      ) ??
      false;

  /// открываем банк: IOS
  /// отдаем ссылку в виде 'https://qr.nspk.ru/...'
  /// schema: bank10000000000
  /// Возвращает false, если ссылка не открылась (например, банк не установлен).
  static Future<bool> openBankIOS(String url, String schema) async =>
      await _channel.invokeMethod<bool>(
        'openBank',
        {
          'url': url,
          'schema': schema,
        },
      ) ??
      false;

  /// открываем банк: Android/IOS
  /// отдаем ссылку в виде 'https://qr.nspk.ru/...'
  /// c2bmemberModel установленный банк
  @Deprecated('Use Sbp.launchBank: it returns SbpOpenResult and distinguishes notInstalled from errors')
  static Future<bool> openBank(String url, C2bmemberModel c2bmemberModel) async =>
      await launchBank(url, c2bmemberModel) == SbpOpenResult.opened;
}
