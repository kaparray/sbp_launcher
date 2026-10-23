import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/sbp.dart';

const _url = 'https://qr.nspk.ru/AS1000?type=02&bank=100000000111&sum=10000&cur=RUB&crc=AB75';

C2bmembersModel _model() => C2bmembersModel.fromJson({
      'version': '1.0',
      'dictionary': [
        {'bankName': 'Сбербанк', 'schema': 'bank100000000111', 'package_name': 'ru.sberbankmobile'},
        {'bankName': 'Т-Банк', 'schema': 'bank100000000004', 'package_name': 'com.idamob.tinkoff.android'},
        {'bankName': 'Без пакета', 'schema': 'bank100000000284'},
        {'bankName': 'РСХБ', 'schema': 'bank100000000020', 'package_name': 'ru.rshb.dbo'},
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
          {
            'schema': 'bank100000000111',
            'package_name': 'ru.sberbankmobile',
            'package_names': ['ru.sberbankmobile'],
          },
          {
            'schema': 'bank100000000004',
            'package_name': 'com.idamob.tinkoff.android',
            'package_names': ['com.idamob.tinkoff.android'],
          },
          {'schema': 'bank100000000284', 'package_name': '', 'package_names': <String>[]},
          {
            'schema': 'bank100000000020',
            'package_name': 'ru.rshb.dbo',
            // новое приложение РСХБ из sbpExtraAndroidPackageNames
            'package_names': ['ru.rshb.dbo', 'ru.rshb.ownfinance'],
          },
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

    test('detection can be disabled on Android', () async {
      mockChannel((_) => fail('channel must not be called'));

      expect(await Sbp.getInstalledBanks(_model(), android: SbpAndroidDetection.disabled), isEmpty);
      final banks = await Sbp.getBanks(_model(), android: SbpAndroidDetection.disabled);
      expect(banks.installed, isEmpty);
      expect(banks.others.length, 4);
      expect(calls, isEmpty);
    });

    test('getBanks splits installed and other banks keeping json order', () async {
      mockChannel((_) => [
            {'schema': 'bank100000000004', 'package_name': 'com.idamob.tinkoff.android'},
          ]);

      final banks = await Sbp.getBanks(_model());

      expect(banks.installed.map((b) => b.bankName), ['Т-Банк']);
      expect(banks.others.map((b) => b.bankName), ['Сбербанк', 'Без пакета', 'РСХБ']);
    });

    test('custom extra packages replace the default ones', () async {
      mockChannel((_) => []);

      await Sbp.getInstalledBanks(_model(), extraAndroidPackageNames: {
        'bank100000000284': ['ru.zhuck.webapp'],
      });

      final banks = (calls.single.arguments as Map)['banks'] as List;
      expect(banks[2]['package_names'], ['ru.zhuck.webapp']);
      expect(banks[3]['package_names'], ['ru.rshb.dbo']);
    });

    test('launchBank opens bank scheme link with the installed package', () async {
      mockChannel((_) => true);
      final bank = _model().c2bmembersModel.first..installedPackageName = 'ru.sberbankmobile.real';

      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.opened);
      expect(calls.single.arguments, {
        'url': 'bank100000000111://qr.nspk.ru/AS1000?type=02&bank=100000000111&sum=10000&cur=RUB&crc=AB75',
        'package_name': 'ru.sberbankmobile.real',
        'https_url': _url,
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
      mockChannel((call) => call.method == 'getQueriesSchemes' ? <String>[] : ['bank100000000004']);

      final installed = await Sbp.getInstalledBanks(_model());

      expect(calls.first.method, 'getInstalledBanks');
      expect(calls.first.arguments, {
        'schema_applications': ['bank100000000111', 'bank100000000004', 'bank100000000284', 'bank100000000020'],
      });
      expect(installed.single.bankName, 'Т-Банк');
    });

    test('debug warning about the 50 schemes limit is printed once', () async {
      final printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = originalDebugPrint);
      Sbp.debugResetIosLimitWarning();
      // 60 схем в Info.plist: Сбербанк в первых 50, РСХБ - за пределами лимита
      final plist = ['bank100000000111', 'bank100000000004', 'bank100000000284', for (var i = 0; i < 57; i++) 'x$i'];
      plist.add('bank100000000020');
      mockChannel((call) => call.method == 'getQueriesSchemes' ? plist : <String>[]);

      await Sbp.getInstalledBanks(_model());
      await Sbp.getInstalledBanks(_model());

      expect(printed, hasLength(2));
      expect(printed.first, contains('61 entries'));
      expect(printed.last, contains('1 of 4 banks cannot be detected'));
    });

    test('detection can be disabled on iOS', () async {
      mockChannel((_) => fail('channel must not be called'));

      final banks = await Sbp.getBanks(_model(), ios: SbpIosDetection.disabled);

      expect(banks.installed, isEmpty);
      expect(banks.others.length, 4);
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

  test('recommended iOS schemes fit the limit and exist in the bundled snapshot', () {
    final snapshot = C2bmembersModel.fromJson(c2bmembersData).c2bmembersModel.map((b) => b.schema).toSet();

    expect(sbpIosPriorityBankSchemes.length, lessThanOrEqualTo(sbpIosQueriesSchemesLimit));
    expect(sbpIosPriorityBankSchemes.toSet().length, sbpIosPriorityBankSchemes.length);
    expect(snapshot.containsAll(sbpIosPriorityBankSchemes), isTrue,
        reason: 'missing: ${sbpIosPriorityBankSchemes.where((s) => !snapshot.contains(s))}');
    expect(snapshot.containsAll(sbpExtraAndroidPackageNames.keys), isTrue);
  });

  test('example Info.plist contains exactly the recommended iOS schemes', () {
    final plist = File('example/ios/Runner/Info.plist').readAsStringSync();
    final array = RegExp(r'<key>LSApplicationQueriesSchemes</key>\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist)!
        .group(1)!;
    final schemes = RegExp(r'<string>([^<]+)</string>').allMatches(array).map((m) => m.group(1)).toList();

    expect(schemes, sbpIosPriorityBankSchemes);
  });

  test('launchBank rejects an invalid url before calling the platform', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    mockChannel((_) => fail('channel must not be called'));

    expect(await Sbp.launchBank('not a url', _model().c2bmembersModel.first), SbpOpenResult.error);
    expect(await Sbp.launchBank('', _model().c2bmembersModel.first), SbpOpenResult.error);
  });

  test('bankLink replaces only the leading http(s) scheme', () {
    expect(Sbp.bankLink('https://qr.nspk.ru/A?r=https://x', 'bank1'), 'bank1://qr.nspk.ru/A?r=https://x');
    expect(Sbp.bankLink('HTTP://qr.nspk.ru/A', 'bank1'), 'bank1://qr.nspk.ru/A');
    expect(Sbp.bankLink('bank2://qr.nspk.ru/A', 'bank1'), 'bank2://qr.nspk.ru/A');
    expect(Sbp.bankLink('https://qr.nspk.ru/A', ''), 'https://qr.nspk.ru/A');
  });
}
