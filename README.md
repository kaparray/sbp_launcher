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

// 2. Установленные банки (сверху шторки) и остальные — блок «Другие банки», их тоже можно открыть
final banks = await Sbp.getBanks(loaded.model);
banks.installed; // ⚠️ на iOS — не больше 50 банков, см. «iOS: лимит 50 схем»
banks.others;

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

### Определение установленных банков: настройка разработчика

Определение можно выключить отдельно для каждой платформы. Тогда `getInstalledBanks` вернёт пустой список,
`getBanks` положит все банки в `others`, а пользователь выберет банк из полного списка
(`launchBank` откроет любой).

```dart
final banks = await Sbp.getBanks(
  model,
  android: SbpAndroidDetection.intentQueries, // или SbpAndroidDetection.disabled
  ios: SbpIosDetection.queriesSchemesMax50,   // или SbpIosDetection.disabled
);
```

Значение по умолчанию для iOS специально называется `queriesSchemesMax50`: ограничение видно прямо в
сигнатуре метода и в подсказках IDE. В debug-сборке на iOS плагин один раз пишет в лог, если в
`LSApplicationQueriesSchemes` больше 50 записей и сколько банков из списка нельзя определить.

Когда выключать определение:
* вы показываете свой короткий список банков (например, по истории оплат пользователя);
* на iOS ваша аудитория пользуется банками, которые не помещаются в 50 схем, и вы не хотите делить список
  на «установленные» и «другие»;
* нужно убрать из манифеста `<queries>` плагина (`tools:node="remove"`): без них определение на Android 11+
  не работает, а открытие через `launchBank` работает.

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

**Дополнительные пакеты.** Если у банка появилось новое приложение, которого ещё нет в `c2bmembers.json`,
его пакет можно добавить по `schema` банка. Встроенный список — `sbpExtraAndroidPackageNames`
(сейчас там новое приложение РСХБ `ru.rshb.ownfinance`). Свой список передаётся параметром:

```dart
await Sbp.getBanks(model, extraAndroidPackageNames: {
  ...sbpExtraAndroidPackageNames,
  'bank100000000020': ['ru.rshb.ownfinance'],
});
```

Банк с таким приложением определяется, даже если приложение не объявляет схему банка, но открывает
`https://qr.nspk.ru`. То, что `ru.rshb.ownfinance` открывает ссылки СБП, на реальном устройстве пока не
проверено.

Требования: `minSdk 21`, Java 17.

### iOS: лимит 50 схем

> ⚠️ **На iOS установленными определяются не больше 50 банков.** Это ограничение iOS, обойти его нельзя.

`canOpenURL` честно отвечает только для схем из `LSApplicationQueriesSchemes` в `Info.plist`. В приложениях,
собранных с iOS 15+ SDK (то есть во всех актуальных сборках), учитываются **только первые 50 записей**: для
остальных схем `canOpenURL` всегда возвращает `false`
([документация Apple](https://developer.apple.com/documentation/uikit/uiapplication/1622952-canopenurl)).
`Info.plist` зашивается при сборке, поменять список на лету нельзя, а API со списком установленных
приложений в iOS нет.

Что это значит для оплаты:

| | Банк в первых 50 схемах | Банк вне списка |
| --- | --- | --- |
| Определяется как установленный | да | нет, попадает в «Другие банки» |
| Открывается через `launchBank` | да | да — `UIApplication.open` не требует `LSApplicationQueriesSchemes` |
| Результат открытия | реальный `opened` / `notInstalled` | реальный `opened` / `notInstalled` |

То есть пользователь банка вне списка не увидит его в верхнем блоке, но найдёт в «Других банках» и
заплатит.

**Какие 50 схем добавлять.** В плагине есть рекомендуемый список `sbpIosPriorityBankSchemes`:

1. крупнейшие банки по вкладам физлиц (Brobank, данные на 01.08.2025) — прокси размера розничной базы;
2. крупные банки, которые не раскрывают отчётность и поэтому выпали из рейтингов (Райффайзен, ПСБ);
3. кошельки экосистем и маркетплейсов, через которые много платят (Озон Банк, ВБ Банк, ЮMoney, МТС Деньги,
   Авито Кошелек);
4. только банки из реестра `c2bmembers.json`.

Записать рекомендуемый список в `Info.plist` вашего приложения (команда запускается из корня приложения):

```bash
dart run sbp:ios_queries_schemes --write=ios/Runner/Info.plist
```

Пример — [example/ios/Runner/Info.plist](example/ios/Runner/Info.plist).

#### Если рекомендуемый список вам не подходит — отредактируйте его

Список 50 банков — только рекомендация. `Info.plist` принадлежит вашему приложению, плагин его не
меняет и не читает ничего, кроме этого списка, поэтому вы вправе держать там любые схемы.

**1. Найдите schema нужного банка.** Это поле `schema` в
[c2bmembers.json](https://qr.nspk.ru/proxyapp/c2bmembers.json) (или во встроенном
`lib/data/c2bmembers_data.dart`), вида `bank100000000153`:

```bash
curl -s https://qr.nspk.ru/proxyapp/c2bmembers.json \
  | python3 -c "import json,sys; [print(b['schema'], b['bankName']) for b in json.load(sys.stdin)['dictionary']]" \
  | grep -i 'венец'
# bank100000000153 Банк Венец
```

**2. Поменяйте список одним из способов.**

Командой — добавить и убрать схемы относительно рекомендуемого списка:

```bash
dart run sbp:ios_queries_schemes \
  --remove=bank100000000022,bank100000000289 \
  --add=bank100000000153,bank100000000059 \
  --write=ios/Runner/Info.plist
```

Или задать полностью свой список:

```bash
dart run sbp:ios_queries_schemes --only=bank100000000111,bank100000000004,bank110000000005 --write=ios/Runner/Info.plist
```

Без `--write` команда только печатает блок `LSApplicationQueriesSchemes`. Команда проверяет, что схем
не больше 50 и что все они есть в реестре. Новый банк, которого ещё нет во встроенном снимке,
можно добавить с `--force`.

Вручную — откройте `ios/Runner/Info.plist` (в Xcode: Runner → Info → *Queried URL Schemes*) и
добавьте или удалите строки в массиве:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>bank100000000111</string> <!-- Сбербанк -->
  <string>bank100000000153</string> <!-- Банк Венец -->
</array>
```

**3. Пересоберите приложение.** `Info.plist` читается при установке, hot reload и hot restart
изменения не подхватят. Нужен полный перезапуск: `flutter run`.

**4. Проверьте в debug-логе.** Если схем больше 50, плагин напишет при первом вызове
`getInstalledBanks`:

```
sbp: LSApplicationQueriesSchemes has 61 entries, iOS uses only the first 50. See sbpIosPriorityBankSchemes.
sbp: 12 of 195 banks cannot be detected on iOS (...)
```

Правила:
* не больше 50 записей: iOS учитывает первые 50, остальные молча игнорируются;
* порядок не важен, если записей не больше 50;
* в `Info.plist` нужны только банки, которые вы хотите показывать как «установленные». Остальные банки
  из `c2bmembers.json` всё равно доступны в «Других банках» и открываются через `launchBank`;
* схему из списка можно удалить, даже если банк остаётся в `c2bmembers.json`: он просто переедет в
  «Другие банки».

**Как выбрать свои 50.** Обычно 10–15 банков закрывают почти все оплаты. Логируйте, каким банком
пользователь заплатил (`launchBank` вернул `opened`), и раз в несколько релизов пересобирайте список
по этой статистике.

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
| 1000 схем в `Info.plist` | до 50 схем (`sbpIosPriorityBankSchemes`) + «другие банки» |
| — | `Sbp.getBanks`, настройки `android:` / `ios:` |
| `getInstalledBanks`, `openAndroidBank`, `openBankIOS` | без изменений сигнатур |

На iOS `openBankIOS` теперь возвращает `false`, если ссылка не открылась (раньше — всегда `true`).

---

## English

### Quick start

```dart
import 'package:sbp/sbp.dart';

final loaded = await C2bmembersRepository(url: 'https://your-proxy.example.com/c2bmembers.json').load();
final banks = await Sbp.getBanks(loaded.model); // banks.installed first, banks.others below — both can be opened
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

### Detection settings

Detection can be turned off per platform: `Sbp.getBanks(model, android: SbpAndroidDetection.disabled,
ios: SbpIosDetection.disabled)` puts every bank into `others`. The iOS default is named
`SbpIosDetection.queriesSchemesMax50` so the limit is visible in the signature and in IDE hints; in debug
builds the plugin logs once when `LSApplicationQueriesSchemes` has more than 50 entries.
Extra Android packages per bank schema: `extraAndroidPackageNames` (defaults to `sbpExtraAndroidPackageNames`,
which includes the new RSHB app `ru.rshb.ownfinance`).

### iOS

> ⚠️ At most 50 banks can be detected as installed on iOS — this is an OS limit.

`canOpenURL` only works for schemes in `LSApplicationQueriesSchemes`, and since iOS 15 only the first
**50** entries count. Put up to 50 priority bank schemes there; list all other banks as "other banks" and
open them with `launchBank` — `UIApplication.open` does not need the allow-list, and the plugin returns the
real result from its completion handler. A recommended list is `sbpIosPriorityBankSchemes`
(`dart run sbp:ios_queries_schemes --write=ios/Runner/Info.plist` writes it). The list is only a
recommendation — edit it with `--add=`, `--remove=` or `--only=` (comma-separated schemes, max 50), or by hand in
`Info.plist`, then do a full rebuild; a list built from your own payment analytics is better. Requires iOS 12.0+.

### Migration from 0.1.x

`openBank` is deprecated in favour of `launchBank`; `getInstalledBanks`, `openAndroidBank` and `openBankIOS`
keep their signatures. `openBankIOS` now returns `false` when the link did not open. Remove bank
`<package>` entries from your manifest and trim `LSApplicationQueriesSchemes` to 50 entries.
