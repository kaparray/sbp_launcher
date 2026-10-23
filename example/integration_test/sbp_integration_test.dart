// Интеграционные тесты плагина на реальной ОС (эмулятор/симулятор/устройство).
//
// Перед запуском установите fake-банки (см. integration_test/fake_banks и run_matrix.sh):
//   Android: ru.smena.fakebank (bank100000000111, bank100000000153), ru.rshb.ownfinance (только https://qr.nspk.ru)
//   iOS:     ru.smena.fakebank (bank100000000111 - есть в Info.plist, bank100000000153 - нет)
//
//   flutter test integration_test -d <device>
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/sbp.dart';

const _url = 'https://qr.nspk.ru/AS10003P3RH0LJ2A9ROO038L6NT5RU1M?type=01&bank=000000000001&sum=10000&cur=RUB&crc=F3D0';

const _sber = 'bank100000000111'; // fake-банк, схема в Info.plist
const _venets = 'bank100000000153'; // fake-банк, схемы нет в Info.plist
const _tbank = 'bank100000000004'; // не установлен
const _rshb = 'bank100000000020'; // Android: fake ru.rshb.ownfinance, только https

C2bmembersModel _model() => C2bmembersModel.fromJson({
      'dictionary': [
        {'bankName': 'Сбербанк', 'schema': _sber, 'package_name': 'ru.sberbankmobile'},
        {'bankName': 'Банк Венец', 'schema': _venets, 'package_name': 'ru.ftc.faktura.venetsbank'},
        {'bankName': 'Т-Банк', 'schema': _tbank, 'package_name': 'com.idamob.tinkoff.android'},
        {'bankName': 'РСХБ', 'schema': _rshb, 'package_name': 'ru.rshb.dbo'},
      ],
    });

C2bmemberModel _bank(String schema) => _model().c2bmembersModel.firstWhere((bank) => bank.schema == schema);

Set<String> _schemas(List<C2bmemberModel> banks) => banks.map((bank) => bank.schema).toSet();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('common', () {
    test('file cache round-trips in the real app support directory', () async {
      final directory = await getApplicationSupportDirectory();
      final cache = FileC2bmembersCache(fileName: 'sbp_integration_test_cache.json');
      final entry =
          C2bmembersCacheEntry(url: 'https://example.com/c.json', body: '{"x":1}', fetchedAt: DateTime.utc(2026));

      await cache.write(entry);
      final read = await cache.read();

      expect(read?.body, entry.body);
      expect(read?.fetchedAt, entry.fetchedAt);
      expect(File('${directory.path}/sbp_integration_test_cache.json').existsSync(), isTrue);
    });

    test('detection can be disabled', () async {
      final banks = await Sbp.getBanks(
        _model(),
        android: SbpAndroidDetection.disabled,
        ios: SbpIosDetection.disabled,
      );

      expect(banks.installed, isEmpty);
      expect(banks.others.length, 4);
    });

    test('not installed bank is reported as notInstalled', () async {
      expect(await Sbp.launchBank(_url, _bank(_tbank)), SbpOpenResult.notInstalled);
    });

    test('invalid url is an error, not a crash', () async {
      expect(await Sbp.launchBank('not a url', _bank(_tbank)), SbpOpenResult.error);
    });

    test('the whole bundled registry is checked fast enough', () async {
      final stopwatch = Stopwatch()..start();
      final installed = await Sbp.getInstalledBanks(C2bmembersModel.fromJson(c2bmembersData));
      stopwatch.stop();

      // ignore: avoid_print
      print('sbp: ${installed.length} installed of ${(c2bmembersData['dictionary'] as List).length} '
          'in ${stopwatch.elapsedMilliseconds} ms');
      expect(_schemas(installed), contains(_sber));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });

  group('Android', skip: !Platform.isAndroid, () {
    test('bank is detected by its scheme with the real package', () async {
      final installed = await Sbp.getInstalledBanks(_model());

      expect(_schemas(installed), containsAll([_sber, _venets]));
      expect(_schemas(installed), isNot(contains(_tbank)));
      for (final bank in installed.where((bank) => bank.schema == _sber || bank.schema == _venets)) {
        expect(bank.installedPackageName, 'ru.smena.fakebank');
      }
    });

    test('extra package is detected through https://qr.nspk.ru handlers', () async {
      final installed = await Sbp.getInstalledBanks(_model());
      final rshb = installed.where((bank) => bank.schema == _rshb).single;

      expect(rshb.installedPackageName, 'ru.rshb.ownfinance');
    });

    test('without extra packages the https-only app is not matched', () async {
      final installed = await Sbp.getInstalledBanks(_model(), extraAndroidPackageNames: const {});

      expect(_schemas(installed), isNot(contains(_rshb)));
    });

    test('local icons and names come from the installed app', () async {
      final installed = await Sbp.getInstalledBanks(_model(), useAndroidLocalIcons: true, useAndroidLocalNames: true);
      final sber = installed.firstWhere((bank) => bank.schema == _sber);

      expect(sber.localName, 'fake_scheme_bank');
      expect(sber.bitmap, isNotNull);
      expect(sber.bitmap!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG
    });

    test('openAndroidBank falls back to the scheme when the package is wrong', () async {
      expect(await Sbp.openAndroidBank('$_venets://qr.nspk.ru/AS1', 'com.example.wrong'), isTrue);
    });

    test('https-only bank app opens with the original https link', () async {
      final bank = (await Sbp.getInstalledBanks(_model())).firstWhere((bank) => bank.schema == _rshb);

      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.opened);
    });

    test('installed bank opens', () async {
      final bank = (await Sbp.getInstalledBanks(_model())).firstWhere((bank) => bank.schema == _sber);

      expect(await Sbp.launchBank(_url, bank), SbpOpenResult.opened);
    });
  });

  group('iOS', skip: !Platform.isIOS, () {
    test('Info.plist has the recommended 50 schemes', () async {
      final schemes = await const MethodChannel('sbp').invokeListMethod<String>('getQueriesSchemes');

      expect(schemes, sbpIosPriorityBankSchemes);
    });

    test('only banks from LSApplicationQueriesSchemes are detected (50 limit)', () async {
      final installed = await Sbp.getInstalledBanks(_model());

      // fake-банк обрабатывает обе схемы, но bank100000000153 нет в Info.plist
      expect(_schemas(installed), {_sber});
    });

    test('bank outside Info.plist still opens and reports the real result', () async {
      expect(await Sbp.launchBank(_url, _bank(_venets)), SbpOpenResult.opened);
      await Future<void>.delayed(const Duration(seconds: 2)); // fake-банк возвращает нас обратно
    });

    test('installed bank opens', () async {
      expect(await Sbp.launchBank(_url, _bank(_sber)), SbpOpenResult.opened);
      await Future<void>.delayed(const Duration(seconds: 2));
    });
  });
}
