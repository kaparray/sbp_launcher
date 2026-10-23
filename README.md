# sbp

[Русский](#русский) · [English](#english)

Flutter plugin, with which you can get a list of banks installed on the user's device, as well as
launch a link to pay via SBP (Система быстрых платежей) of the form `https://qr.nspk.ru/.../`.

<p float="left">
 <img src="https://github.com/smenateam/sbp/blob/master/doc/screenshots/sbp_android1.jpg?raw=true" height="600">
 <img src="https://github.com/smenateam/sbp/blob/master/doc/screenshots/sbp_android2.jpg?raw=true" height="600">
</p>

---

## Русский

### Быстрый старт

```dart
import 'package:sbp/sbp.dart';

// 1. Список банков: сервер → кэш на устройстве (24 ч) → встроенный снимок
final repository = C2bmembersRepository(url: 'https://your-proxy.example.com/c2bmembers.json');
final loaded = await repository.load();
final allBanks = loaded.model.c2bmembersModel;

// 2. Установленные банки — показываем сверху шторки
final installed = await Sbp.getInstalledBanks(loaded.model);

// 3. Остальные банки — блок «Другие банки». Их тоже можно открыть
final installedSchemas = installed.map((b) => b.schema).toSet();
final others = allBanks.where((b) => !installedSchemas.contains(b.schema)).toList();

// 4. Открываем банк и честно узнаём результат
final result = await Sbp.launchBank('https://qr.nspk.ru/AS1000...', bank);
switch (result) {
  case SbpOpenResult.opened:       // банк открылся
  case SbpOpenResult.notInstalled: // приложения нет — предложите другой банк
  case SbpOpenResult.error:        // неверная ссылка или ошибка системы
}
```

Полный пример — [example/lib/main.dart](example/lib/main.dart).

### Список банков

`C2bmembersRepository.load()` никогда не бросает исключений и возвращает `C2bmembersLoadResult`
с моделью и источником (`network`, `cache`, `staleCache`, `bundled`). Порядок:

1. свежий кэш (моложе `ttl`, по умолчанию 24 часа) — без запроса в сеть;
2. сервер (`url`, `timeout` по умолчанию 10 секунд);
3. просроченный кэш, если сервер недоступен;
4. встроенный снимок `c2bmembersData` (`lib/data/c2bmembers_data.dart`, дата — `c2bmembersDataDate`).

Ответ, в котором нет ни одного банка (страница ошибки прокси, пустой список), не попадает в кэш.
Короткий вариант без настроек — `Sbp.loadBanks()`.

**Рекомендация:** держите свой прокси для `c2bmembers.json` и логотипов. `qr.nspk.ru` бывает медленным
или недоступным из некоторых сетей, а свой прокси позволяет быстро исправить данные банка без
релиза приложения.

Обновить встроенный снимок: `dart run tool/update_c2bmembers.dart` (или `--file=path.json`).

### Android

**Начиная с 0.2.0 больше не нужен `<queries>` со списком пакетов банков.** Плагин сам объявляет в
своём манифесте (он попадает в приложение через manifest merge):

```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="*" android:host="qr.nspk.ru" />
  </intent>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="https" android:host="qr.nspk.ru" />
  </intent>
</queries>
```

Банк считается установленным, если есть приложение, которое открывает ссылку
`<schema>://qr.nspk.ru/` (`PackageManager.queryIntentActivities`, `MATCH_DEFAULT_ONLY`).
Дополнительно сверяются пакеты, которые открывают `https://qr.nspk.ru/`. Поэтому:

* находятся банки, которых нет ни в каком статическом списке, и банки без `package_name` в json;
* если банк сменил пакет, это не ломает определение (`C2bmemberModel.installedPackageName` — реальный пакет);
* новый банк в `c2bmembers.json` начинает работать без релиза плагина и приложения.

`launchBank` сначала открывает ссылку в пакете банка, а если не получилось — без пакета, по схеме банка.
Если ссылку открыть некому, возвращается `notInstalled`.

Если вы раньше добавляли в свой `AndroidManifest.xml` `<package>`-записи банков, их можно удалить.

Требования: `minSdk 21`, Java 17.

### iOS

`canOpenURL` честно отвечает только для схем из `LSApplicationQueriesSchemes` в `Info.plist`,
а с iOS 15 там учитываются **не больше 50 записей** — остальные схемы молча считаются неустановленными
([документация Apple](https://developer.apple.com/documentation/uikit/uiapplication/1622952-canopenurl)).

Стратегия:

1. Добавьте в `Info.plist` до 50 схем приоритетных банков (для вашей аудитории). Они определяются как
   установленные и показываются сверху.
2. Все остальные банки из json показывайте блоком «Другие банки». `launchBank` откроет их напрямую:
   `UIApplication.open` не требует `LSApplicationQueriesSchemes`, а плагин возвращает реальный результат
   из `completionHandler` — `opened` или `notInstalled`.

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>bank100000000111</string> <!-- Сбербанк -->
  <string>bank100000000004</string> <!-- Т-Банк -->
  <string>bank110000000005</string> <!-- ВТБ -->
  <!-- ... не больше 50 -->
</array>
```

Готовый список 50 первых банков реестра — в [example/ios/Runner/Info.plist](example/ios/Runner/Info.plist).

Требования: iOS 12.0+.

### Локальные иконки

Поле `icon` есть только во встроенном снимке (для данных с сервера плагин подставляет его по `schema`).
Чтобы использовать иконки, подключите их в `pubspec.yaml` приложения:

```yaml
flutter:
  assets:
    - packages/sbp/assets/sbp.png
    - packages/sbp/assets/icons/sber.png
    # ...
```

На Android можно взять иконку и название из установленного приложения:
`getInstalledBanks(model, useAndroidLocalIcons: true, useAndroidLocalNames: true)` заполнит
`bitmap` и `localName`.

### Миграция с 0.1.x

| 0.1.x | 0.2.0 |
| --- | --- |
| `Sbp.openBank(url, bank) -> bool` | `Sbp.launchBank(url, bank) -> SbpOpenResult` (`openBank` работает, помечен `@Deprecated`) |
| `C2bmembersModel.fromJson(c2bmembersData)` | `C2bmembersRepository().load()` / `Sbp.loadBanks()` |
| `<queries>` с `<package>` банков в приложении | не нужен |
| 1000 схем в `Info.plist` | до 50 приоритетных схем + «другие банки» |
| `getInstalledBanks`, `openAndroidBank`, `openBankIOS` | без изменений сигнатур |

На iOS `openBankIOS` теперь возвращает `false`, если ссылка не открылась (раньше — всегда `true`).

---

## English

### Quick start

```dart
import 'package:sbp/sbp.dart';

final loaded = await C2bmembersRepository(url: 'https://your-proxy.example.com/c2bmembers.json').load();
final installed = await Sbp.getInstalledBanks(loaded.model);   // show these first
// show the rest of loaded.model.c2bmembersModel as "other banks" — they can be opened too
final result = await Sbp.launchBank('https://qr.nspk.ru/AS1000...', bank); // opened / notInstalled / error
```

See [example/lib/main.dart](example/lib/main.dart).

### Bank list

`C2bmembersRepository.load()` never throws. It returns a fresh on-device cache (default TTL 24 h), otherwise
downloads the list (default URL `https://qr.nspk.ru/proxyapp/c2bmembers.json`, 10 s timeout), otherwise
falls back to a stale cache and finally to the bundled snapshot `c2bmembersData`. Responses without
any bank are never cached. We recommend serving `c2bmembers.json` from your own proxy.

Regenerate the bundled snapshot with `dart run tool/update_c2bmembers.dart`.

### Android

**Since 0.2.0 you no longer need a `<queries>` block listing bank packages.** The plugin manifest declares
`VIEW` intent queries for `*://qr.nspk.ru` and `https://qr.nspk.ru`. A bank is installed when some activity
resolves `<schema>://qr.nspk.ru/` (`queryIntentActivities`, `MATCH_DEFAULT_ONLY`); `https://qr.nspk.ru`
handlers are matched by `package_name` as a second source. New banks work without a plugin or app release,
banks without `package_name` are detected, and the real package is returned in `installedPackageName`.
`launchBank` tries the bank package first and retries without it; `notInstalled` is returned when nothing
can open the link. Requires `minSdk 21` and Java 17.

### iOS

`canOpenURL` only works for schemes in `LSApplicationQueriesSchemes`, and since iOS 15 only the first
**50** entries count. Put up to 50 priority bank schemes there; list all other banks as "other banks" and
open them with `launchBank` — `UIApplication.open` does not need the allow-list, and the plugin returns the
real result from its completion handler. Requires iOS 12.0+.

### Migration from 0.1.x

`openBank` is deprecated in favour of `launchBank`; `getInstalledBanks`, `openAndroidBank` and `openBankIOS`
keep their signatures. `openBankIOS` now returns `false` when the link did not open. Remove bank
`<package>` entries from your manifest and trim `LSApplicationQueriesSchemes` to 50 entries.
