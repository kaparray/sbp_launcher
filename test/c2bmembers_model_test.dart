import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/models/c2bmembers_model.dart';

void main() {
  test('parses a full NSPK entry and ignores unknown fields', () {
    final model = C2bmembersModel.fromJson(jsonDecode('''
      {"version": "1.0", "dictionary": [{
        "bankName": "Сбербанк", "isDrActive": true, "isSsnpActive": true,
        "logoURL": "https://qr.nspk.ru/proxyapp/logo/bank100000000111.png",
        "package_name": "ru.sberbankmobile", "schema": "bank100000000111",
        "webClientUrl": "https://v.sber.ru/sms/sbpqr?params=", "isWebClientActive": true,
        "somethingNew": {"nested": 1}
      }]}
    '''));

    final bank = model.c2bmembersModel.single;
    expect(model.version, '1.0');
    expect(bank.bankName, 'Сбербанк');
    expect(bank.schema, 'bank100000000111');
    expect(bank.packageName, 'ru.sberbankmobile');
    expect(bank.logoURL, 'https://qr.nspk.ru/proxyapp/logo/bank100000000111.png');
    expect(bank.webClientUrl, 'https://v.sber.ru/sms/sbpqr?params=');
    expect(bank.isWebClientActive, isTrue);
    expect(bank.icon, '');
  });

  test('missing fields get defaults', () {
    final bank = C2bmembersModel.fromJson({
      'dictionary': [
        {'schema': 'bank100000000284'},
      ],
    }).c2bmembersModel.single;

    expect(bank.bankName, '');
    expect(bank.packageName, '');
    expect(bank.logoURL, '');
    expect(bank.webClientUrl, isNull);
    expect(bank.isWebClientActive, isFalse);
    expect(bank.installedPackageName, isNull);
  });

  test('missing or broken dictionary and wrong entry types do not throw', () {
    expect(C2bmembersModel.fromJson({}).c2bmembersModel, isEmpty);
    expect(C2bmembersModel.fromJson({'dictionary': 'oops'}).c2bmembersModel, isEmpty);

    final model = C2bmembersModel.fromJson({
      'version': 2,
      'dictionary': [
        'not a map',
        null,
        {'schema': 'bank1', 'bankName': 42},
      ],
    });
    expect(model.version, '2');
    expect(model.c2bmembersModel.single.bankName, '42');
  });

  test('bundled snapshot is valid', () {
    final banks = C2bmembersModel.fromJson(c2bmembersData).c2bmembersModel;
    expect(banks.length, greaterThan(150));
    expect(banks.every((bank) => RegExp(r'^bank\d{12}$').hasMatch(bank.schema)), isTrue);
    expect(banks.map((bank) => bank.schema).toSet().length, banks.length);
    // в старом снимке были испорчены package_name вида ru.avangard.packages/sbpent
    expect(banks.where((bank) => bank.packageName.contains('/')), isEmpty);
    expect(banks.firstWhere((bank) => bank.schema == 'bank100000000111').icon, 'packages/sbp/assets/icons/sber.png');
  });
}
