import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sbp_launcher/data/c2bmembers_repository.dart';
import 'package:sbp_launcher/data/sbp_bank_lists.dart';
import 'package:sbp_launcher/models/c2bmembers_model.dart';

export 'package:sbp_launcher/data/c2bmembers_repository.dart';
export 'package:sbp_launcher/data/sbp_bank_lists.dart';
export 'package:sbp_launcher/models/c2bmembers_model.dart';

/// Сколько записей LSApplicationQueriesSchemes учитывает iOS (приложения с iOS 15+ SDK)
const sbpIosQueriesSchemesLimit = 50;

/// Как определять установленные банки на Android
enum SbpAndroidDetection {
  /// Банк установлен, если есть приложение, которое открывает `<schema>://qr.nspk.ru/`
  /// (intent-запросы из манифеста плагина). Лимита на число банков нет.
  intentQueries,

  /// Не определять: [Sbp.getInstalledBanks] вернёт пустой список,
  /// все банки показываются списком и открываются через [Sbp.launchBank].
  disabled,
}

/// Как определять установленные банки на iOS.
///
/// ⚠️ iOS определяет не больше 50 банков: `canOpenURL` честно отвечает только для схем
/// из `LSApplicationQueriesSchemes` в Info.plist, а учитываются первые 50 записей.
/// Банки вне списка всё равно открываются через [Sbp.launchBank].
/// Рекомендуемый список схем - [sbpIosPriorityBankSchemes].
enum SbpIosDetection {
  /// `canOpenURL` по схемам из `LSApplicationQueriesSchemes`.
  /// ⚠️ Определяются не больше 50 банков - тех, чьи схемы есть в Info.plist.
  queriesSchemesMax50,

  /// Не определять: [Sbp.getInstalledBanks] вернёт пустой список,
  /// все банки показываются списком и открываются через [Sbp.launchBank].
  disabled,
}

/// Банки для экрана выбора: установленные и остальные («другие банки»)
class SbpBanks {
  /// найденные на устройстве - показывать сверху
  final List<C2bmemberModel> installed;

  /// остальные банки из списка - их тоже можно открыть через [Sbp.launchBank]
  final List<C2bmemberModel> others;

  const SbpBanks({required this.installed, required this.others});
}

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
  static const MethodChannel _channel = MethodChannel('sbp_launcher');

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
  /// [android] - способ определения на Android, по умолчанию [SbpAndroidDetection.intentQueries].
  /// [ios] - способ определения на iOS, по умолчанию [SbpIosDetection.queriesSchemesMax50]:
  /// ⚠️ на iOS определяются не больше 50 банков (схемы из LSApplicationQueriesSchemes).
  /// [extraAndroidPackageNames] - дополнительные пакеты банков по schema, которых нет в json.
  ///
  /// Банки, которых нет в результате, всё равно можно открыть через [launchBank].
  static Future<List<C2bmemberModel>> getInstalledBanks(
    C2bmembersModel c2bmembersModel, {
    bool useAndroidLocalIcons = false,
    bool useAndroidLocalNames = false,
    SbpAndroidDetection android = SbpAndroidDetection.intentQueries,
    SbpIosDetection ios = SbpIosDetection.queriesSchemesMax50,
    Map<String, List<String>> extraAndroidPackageNames = sbpExtraAndroidPackageNames,
  }) async {
    final banks = c2bmembersModel.c2bmembersModel;
    if (_isIOS) {
      if (ios == SbpIosDetection.disabled) return [];
      final installed = await _channel.invokeListMethod<String>('getInstalledBanks', {
        'schema_applications': banks.map((bank) => bank.schema).toList(),
      });
      if (kDebugMode) await _warnAboutIosLimit(banks);
      final schemas = (installed ?? const <String>[]).toSet();
      return banks.where((bank) => schemas.contains(bank.schema)).toList();
    }
    if (_isAndroid) {
      if (android == SbpAndroidDetection.disabled) return [];
      final installed = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getInstalledBanks', {
        'banks': [
          for (final bank in banks)
            {
              'schema': bank.schema,
              'package_name': bank.packageName,
              'package_names': {
                if (bank.packageName.isNotEmpty) bank.packageName,
                ...?extraAndroidPackageNames[bank.schema],
              }.toList(),
            },
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
    throw UnsupportedError('sbp_launcher: getInstalledBanks is supported only on Android and iOS');
  }

  /// Банки для экрана выбора: установленные (сверху) и все остальные («другие банки»).
  /// Параметры - как у [getInstalledBanks]. ⚠️ На iOS установленными определяются не больше 50 банков.
  static Future<SbpBanks> getBanks(
    C2bmembersModel c2bmembersModel, {
    bool useAndroidLocalIcons = false,
    bool useAndroidLocalNames = false,
    SbpAndroidDetection android = SbpAndroidDetection.intentQueries,
    SbpIosDetection ios = SbpIosDetection.queriesSchemesMax50,
    Map<String, List<String>> extraAndroidPackageNames = sbpExtraAndroidPackageNames,
  }) async {
    final installed = await getInstalledBanks(
      c2bmembersModel,
      useAndroidLocalIcons: useAndroidLocalIcons,
      useAndroidLocalNames: useAndroidLocalNames,
      android: android,
      ios: ios,
      extraAndroidPackageNames: extraAndroidPackageNames,
    );
    final installedSchemas = installed.map((bank) => bank.schema).toSet();
    return SbpBanks(
      installed: installed,
      others: c2bmembersModel.c2bmembersModel.where((bank) => !installedSchemas.contains(bank.schema)).toList(),
    );
  }

  static bool _iosLimitWarned = false;

  @visibleForTesting
  static void debugResetIosLimitWarning() => _iosLimitWarned = false;

  /// В debug один раз подсказывает, сколько банков iOS не сможет определить
  static Future<void> _warnAboutIosLimit(List<C2bmemberModel> banks) async {
    if (_iosLimitWarned) return;
    _iosLimitWarned = true;
    try {
      final schemes = await _channel.invokeListMethod<String>('getQueriesSchemes') ?? const [];
      final counted = schemes.take(sbpIosQueriesSchemesLimit).toSet();
      final undetectable = banks.where((bank) => !counted.contains(bank.schema)).length;
      if (schemes.length > sbpIosQueriesSchemesLimit) {
        debugPrint('sbp_launcher: LSApplicationQueriesSchemes has ${schemes.length} entries, iOS uses only the first '
            '$sbpIosQueriesSchemesLimit. See sbpIosPriorityBankSchemes.');
      }
      if (undetectable > 0) {
        debugPrint('sbp_launcher: $undetectable of ${banks.length} banks cannot be detected on iOS (not in the first '
            '$sbpIosQueriesSchemesLimit LSApplicationQueriesSchemes). Show them as "other banks" and open with '
            'Sbp.launchBank.');
      }
    } on PlatformException catch (_) {
      // старая нативная часть без getQueriesSchemes - подсказка не обязательна
    } on MissingPluginException catch (_) {}
  }

  /// Открываем банк: Android/IOS.
  /// [url] - ссылка вида 'https://qr.nspk.ru/...', [bank] - банк из списка (установленный или нет).
  /// Не бросает исключений: результат - [SbpOpenResult].
  ///
  /// ⚠️ iOS: если открыть банк не по нажатию пользователя (например, автоматически после загрузки),
  /// iOS спросит «… wants to open …». При отказе iOS возвращает false, и результат будет
  /// [SbpOpenResult.notInstalled] - отличить отказ от неустановленного банка iOS не позволяет.
  static Future<SbpOpenResult> launchBank(String url, C2bmemberModel bank) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || url.contains(' ')) return SbpOpenResult.error;
    try {
      if (_isIOS) {
        return await openBankIOS(url, bank.schema) ? SbpOpenResult.opened : SbpOpenResult.notInstalled;
      }
      if (_isAndroid) {
        final packageName = bank.installedPackageName ?? bank.packageName;
        final opened = await _channel.invokeMethod<bool>('openBank', {
          'url': bankLink(url, bank.schema),
          'package_name': packageName,
          // приложение банка может открывать только https://qr.nspk.ru (без своей схемы)
          if (url.toLowerCase().startsWith('https://')) 'https_url': url,
        });
        return opened == true ? SbpOpenResult.opened : SbpOpenResult.notInstalled;
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
