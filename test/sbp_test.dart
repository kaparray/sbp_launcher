import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbp/sbp.dart';

const _url = 'https://qr.nspk.ru/AS1000?type=02&bank=100000000111&sum=10000&cur=RUB&crc=AB75';

C2bmembersModel _model() => C2bmembersModel.fromJson({
      'version': '1.0',
      'dictionary': [
        {'bankName': 'Сбербанк', 'schema': 'bank100000000111', 'package_name': 'ru.sberbankmobile'},
        {'bankName': 'Т-Банк', 'schema': 'bank100000000004', 'package_name': 'com.idamob.tinkoff.android'},
        {'bankName': 'Без пакета', 'schema': 'bank100000000284'},
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sbp');
  final calls = <MethodCall>[];

  void mockChannel(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('getInstalledBanks sends schemas with packages and maps the result by schema', () async {
      final icon = Uint8List.fromList([1, 2, 3]);
      mockChannel((_) => [
            {'schema': 'bank100000000284', 'package_name': 'ru.zhuck.webapp', 'name': 'Жук', 'bitmap': icon},
            {'schema': 'bank100000000111', 'package_name': 'ru.sberbankmobile', 'name': null, 'bitmap': null},
          ]);

      final installed = await Sbp.getInstalledBanks(_model(), useAndroidLocalIcons: true);

      expect(calls.single.arguments, {
        'banks': [
          {'schema': 'bank100000000111', 'package_name': 'ru.sberbankmobile'},
          {'schema': 'bank100000000004', 'package_name': 'com.idamob.tinkoff.android'},
          {'schema': 'bank100000000284', 'package_name': ''},
        ],
        'use_android_local_icons': true,
        'use_android_local_names': false,
      });
      // порядок - как в json, а не как вернула платформа
      expect(installed.map((b) => b.schema), ['bank100000000111', 'bank100000000284']);
      expect(installed.last.installedPackageName, 'ru.zhuck.webapp');
      expect(installed.last.localName, 'Жук');
      expect(installed.last.bitmap, icon);
    });

    test('launchBank opens bank scheme link with the installed package', () async {
      mockChannel((_) => true);
      final bank = _model().c2bmembersModel.first..installedPackageName = 'ru.sberbankmobile.real';

      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.opened);
      expect(calls.single.arguments, {
        'url': 'bank100000000111://qr.nspk.ru/AS1000?type=02&bank=100000000111&sum=10000&cur=RUB&crc=AB75',
        'package_name': 'ru.sberbankmobile.real',
      });
    });

    test('launchBank maps NOT_INSTALLED and other platform errors', () async {
      final bank = _model().c2bmembersModel.first;

      mockChannel((_) => throw PlatformException(code: 'NOT_INSTALLED'));
      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.notInstalled);

      mockChannel((_) => throw PlatformException(code: 'OPEN_FAILED'));
      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.error);
    });

    test('deprecated openBank keeps returning bool', () async {
      mockChannel((_) => throw PlatformException(code: 'NOT_INSTALLED'));
      // ignore: deprecated_member_use_from_same_package
      expect(await Sbp.openBank(_url, _model().c2bmembersModel.first), isFalse);
    });
  });

  group('iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('getInstalledBanks filters by schemas reported by canOpenURL', () async {
      mockChannel((_) => ['bank100000000004']);

      final installed = await Sbp.getInstalledBanks(_model());

      expect(calls.single.arguments, {
        'schema_applications': ['bank100000000111', 'bank100000000004', 'bank100000000284'],
      });
      expect(installed.single.bankName, 'Т-Банк');
    });

    test('launchBank returns the real result of UIApplication.open', () async {
      final bank = _model().c2bmembersModel.first;

      mockChannel((_) => true);
      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.opened);
      expect(calls.last.arguments, {'url': _url, 'schema': 'bank100000000111'});

      mockChannel((_) => false);
      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.notInstalled);

      mockChannel((_) => throw PlatformException(code: 'INVALID_ARGUMENT'));
      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.error);
    });
  });

  group('unsupported platform', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);

    test('getInstalledBanks throws UnsupportedError, launchBank returns error', () async {
      expect(() => Sbp.getInstalledBanks(_model()), throwsUnsupportedError);
      expect(await Sbp.launchBank(_url, _model().c2bmembersModel.first), SbpOpenResult.error);
      expect(calls, isEmpty);
    });
  });

  test('bankLink replaces only the leading http(s) scheme', () {
    expect(Sbp.bankLink('https://qr.nspk.ru/A?r=https://x', 'bank1'), 'bank1://qr.nspk.ru/A?r=https://x');
    expect(Sbp.bankLink('HTTP://qr.nspk.ru/A', 'bank1'), 'bank1://qr.nspk.ru/A');
    expect(Sbp.bankLink('bank2://qr.nspk.ru/A', 'bank1'), 'bank2://qr.nspk.ru/A');
    expect(Sbp.bankLink('https://qr.nspk.ru/A', ''), 'https://qr.nspk.ru/A');
  });
}
