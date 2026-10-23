// Печатает LSApplicationQueriesSchemes для Info.plist из sbpIosPriorityBankSchemes.
//
//   dart run tool/ios_queries_schemes.dart
import 'dart:io';

import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/data/sbp_bank_lists.dart';

void main() {
  final names = {
    for (final bank in (c2bmembersData['dictionary'] as List).cast<Map<String, Object?>>())
      bank['schema']: bank['bankName'],
  };
  stdout
    ..writeln('\t<!-- iOS учитывает не больше 50 схем. Сгенерировано tool/ios_queries_schemes.dart -->')
    ..writeln('\t<key>LSApplicationQueriesSchemes</key>')
    ..writeln('\t<array>');
  for (final schema in sbpIosPriorityBankSchemes) {
    stdout.writeln('\t\t<string>$schema</string><!-- ${names[schema]} -->');
  }
  stdout.writeln('\t</array>');
}
