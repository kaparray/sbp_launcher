import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbp/sbp.dart';
import 'package:sbp_example/main.dart';

C2bmemberModel _bank(String schema, String name) => C2bmembersModel.fromJson({
      'dictionary': [
        {'schema': schema, 'bankName': name},
      ],
    }).c2bmembersModel.single;

void main() {
  testWidgets('installed banks are listed above other banks', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SbpBanksSheet(
          url: sbpPaymentUrl,
          source: C2bmembersSource.bundled,
          banks: SbpBanks(installed: [_bank('bank1', 'Установленный')], others: [_bank('bank2', 'Другой')]),
        ),
      ),
    ));

    final installed = tester.getTopLeft(find.text('Установленный'));
    final header = tester.getTopLeft(find.text('Другие банки'));
    final other = tester.getTopLeft(find.text('Другой'));
    expect(installed.dy, lessThan(header.dy));
    expect(header.dy, lessThan(other.dy));
  });
}
