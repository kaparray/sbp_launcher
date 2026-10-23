// Список LSApplicationQueriesSchemes для Info.plist (iOS учитывает не больше 50 схем).
//
// Из приложения, которое подключает sbp:
//   dart run sbp:ios_queries_schemes                                  # напечатать рекомендуемый список
//   dart run sbp:ios_queries_schemes --write=ios/Runner/Info.plist    # записать в Info.plist
//   dart run sbp:ios_queries_schemes --remove=bank100000000022 --add=bank100000000153 --write=ios/Runner/Info.plist
//   dart run sbp:ios_queries_schemes --only=bank100000000111,bank100000000004 --write=ios/Runner/Info.plist
//
// --only    - свой список вместо рекомендуемого sbpIosPriorityBankSchemes
// --add     - добавить схемы (через запятую)
// --remove  - убрать схемы (через запятую)
// --write   - заменить LSApplicationQueriesSchemes в указанном Info.plist (или добавить, если его нет)
// --force   - разрешить схемы, которых нет во встроенном реестре, и больше 50 записей
import 'dart:io';

import 'package:sbp/data/c2bmembers_data.dart';
import 'package:sbp/data/sbp_bank_lists.dart';

const _limit = 50;

void main(List<String> args) {
  final options = <String, String>{};
  for (final arg in args) {
    if (arg == '--force') {
      options['force'] = 'true';
    } else if (arg.startsWith('--') && arg.contains('=')) {
      options[arg.substring(2, arg.indexOf('='))] = arg.substring(arg.indexOf('=') + 1);
    } else {
      stderr.writeln('Unknown argument: $arg');
      exit(64);
    }
  }
  List<String> list(String key) =>
      (options[key] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final names = {
    for (final bank in (c2bmembersData['dictionary'] as List).cast<Map<String, Object?>>())
      bank['schema'] as String: bank['bankName'] as String? ?? '',
  };

  final remove = list('remove').toSet();
  final schemes = <String>{
    ...(options.containsKey('only') ? list('only') : sbpIosPriorityBankSchemes),
    ...list('add'),
  }.where((schema) => !remove.contains(schema)).toList();

  final force = options['force'] == 'true';
  final unknown = schemes.where((schema) => !names.containsKey(schema)).toList();
  if (unknown.isNotEmpty && !force) {
    stderr.writeln('Not in the bundled c2bmembers.json: ${unknown.join(', ')} (use --force to keep them)');
    exit(65);
  }
  if (schemes.length > _limit && !force) {
    stderr.writeln('${schemes.length} schemes, but iOS uses only the first $_limit. '
        'Remove ${schemes.length - _limit} with --remove (or use --force).');
    exit(65);
  }

  final block = StringBuffer()
    ..writeln('\t<!-- iOS учитывает не больше $_limit схем. Сгенерировано: dart run sbp:ios_queries_schemes -->')
    ..writeln('\t<key>LSApplicationQueriesSchemes</key>')
    ..writeln('\t<array>');
  for (final schema in schemes) {
    final name = names[schema];
    block.writeln('\t\t<string>$schema</string>${name == null ? '' : '<!-- $name -->'}');
  }
  block.writeln('\t</array>');

  final path = options['write'];
  if (path == null) {
    stdout.write(block);
    return;
  }

  final file = File(path);
  final plist = file.readAsStringSync();
  final existing = RegExp(
    r'(?:[ \t]*<!--[^\n]*-->\n)?[ \t]*<key>LSApplicationQueriesSchemes</key>\s*<array>.*?</array>\n?',
    dotAll: true,
  );
  final String updated;
  if (existing.hasMatch(plist)) {
    updated = plist.replaceFirst(existing, block.toString());
  } else {
    final dict = plist.indexOf('<dict>');
    if (dict < 0) {
      stderr.writeln('$path: <dict> not found');
      exit(65);
    }
    final insertAt = plist.indexOf('\n', dict) + 1;
    updated = plist.substring(0, insertAt) + block.toString() + plist.substring(insertAt);
  }
  file.writeAsStringSync(updated);
  stdout.writeln('$path: ${schemes.length} schemes');
}
