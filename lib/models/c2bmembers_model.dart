import 'dart:typed_data';

/// данные, которые приходят с сервера: https://qr.nspk.ru/proxyapp/c2bmembers.json
class C2bmembersModel {
  /// [version] - версия json
  late final String version;

  /// [c2bmembersModel] - Список C2bmemberModel, которая содержит необходимую информацию о приложении
  List<C2bmemberModel> c2bmembersModel = [];

  /// Получение данных из словаря.
  /// Отсутствующие поля заменяются значениями по умолчанию, лишние поля игнорируются,
  /// записи неверного типа пропускаются.
  C2bmembersModel.fromJson(Map<String, dynamic> json) {
    version = _string(json['version']);
    final dictionary = json['dictionary'];
    if (dictionary is List) {
      for (final c2bmemberModel in dictionary) {
        if (c2bmemberModel is Map) {
          c2bmembersModel.add(C2bmemberModel.fromJson(Map<String, dynamic>.from(c2bmemberModel)));
        }
      }
    }
  }
}

/// Содержит всю необходимую информацию о приложении банка
class C2bmemberModel {
  /// [bankName] - название приложения
  late final String bankName;

  /// [logoURL] - иконка приложения
  late final String logoURL;

  /// [schema] - schema приложения
  late final String schema;

  /// [packageName] - packageName приложения из json
  late final String packageName;

  /// [icon] - локальная иконка из ассетов плагина (поле есть только во встроенном списке)
  late final String icon;

  /// [webClientUrl] - адрес веб-клиента банка, если есть
  late final String? webClientUrl;

  /// [isWebClientActive] - доступен ли веб-клиент банка
  late final bool isWebClientActive;

  /// [bitmap] - иконка приложения, если выставить use_android_local_icons = true (Android)
  Uint8List? bitmap;

  /// [localName] - название приложения, если выставить use_android_local_names = true (Android)
  String? localName;

  /// [installedPackageName] - реальный package установленного приложения,
  /// который вернул PackageManager (Android). Может отличаться от [packageName] в json.
  String? installedPackageName;

  /// Получение данных из словаря
  C2bmemberModel.fromJson(Map<String, dynamic> json) {
    bankName = _string(json['bankName']);
    logoURL = _string(json['logoURL']);
    schema = _string(json['schema']);
    packageName = _string(json['package_name']);
    icon = _string(json['icon']);
    final webClient = _string(json['webClientUrl']);
    webClientUrl = webClient.isEmpty ? null : webClient;
    isWebClientActive = json['isWebClientActive'] == true;
  }
}

String _string(Object? value) => value == null ? '' : value.toString();
