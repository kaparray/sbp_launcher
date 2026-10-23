import 'package:flutter/material.dart';
import 'package:sbp/sbp.dart';

void main() {
  runApp(const MyApp());
}

/// Ссылка на оплату, которую обычно отдаёт бэкенд
const sbpPaymentUrl =
    'https://qr.nspk.ru/AS10003P3RH0LJ2A9ROO038L6NT5RU1M?type=01&bank=000000000001&sum=10000&cur=RUB&crc=F3D0';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: PaymentScreen());
  }
}

/// Банки для шторки и источник списка
class LoadedBanks {
  final SbpBanks banks;
  final C2bmembersSource source;

  const LoadedBanks(this.banks, this.source);
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// Реестр банков с портала НСПК: https://qr.nspk.ru/proxyapp/c2bmembers.json
  final _repository = C2bmembersRepository();

  /// Настройка разработчика: определять ли установленные банки.
  /// Выключено - все банки показываются одним списком и открываются через launchBank.
  bool _detectInstalled = true;

  Future<LoadedBanks> _loadBanks() async {
    final loaded = await _repository.load();
    final banks = await Sbp.getBanks(
      loaded.model,
      android: _detectInstalled ? SbpAndroidDetection.intentQueries : SbpAndroidDetection.disabled,
      // ⚠️ на iOS определяются только банки из первых 50 схем LSApplicationQueriesSchemes
      ios: _detectInstalled ? SbpIosDetection.queriesSchemesMax50 : SbpIosDetection.disabled,
    );
    return LoadedBanks(banks, loaded.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('СБП')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Определять установленные банки'),
              value: _detectInstalled,
              onChanged: (value) => setState(() => _detectInstalled = value),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => FutureBuilder<LoadedBanks>(
                  future: _loadBanks(),
                  builder: (context, snapshot) {
                    final loaded = snapshot.data;
                    if (loaded == null) {
                      return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                    }
                    return SbpBanksSheet(banks: loaded.banks, source: loaded.source, url: sbpPaymentUrl);
                  },
                ),
              ),
              child: const Text('Оплатить через СБП'),
            ),
          ],
        ),
      ),
    );
  }
}

class SbpBanksSheet extends StatefulWidget {
  final SbpBanks banks;
  final C2bmembersSource source;
  final String url;

  const SbpBanksSheet({super.key, required this.banks, required this.source, required this.url});

  @override
  State<SbpBanksSheet> createState() => _SbpBanksSheetState();
}

class _SbpBanksSheetState extends State<SbpBanksSheet> {
  /// сообщение показываем в шторке: SnackBar экрана оказался бы под ней
  String? _message;

  Future<void> _open(C2bmemberModel bank) async {
    setState(() => _message = null);
    final result = await Sbp.launchBank(widget.url, bank);
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        SbpOpenResult.opened => null,
        SbpOpenResult.notInstalled => 'Приложение «${bank.bankName}» не установлено. Выберите другой банк.',
        SbpOpenResult.error => 'Не удалось открыть «${bank.bankName}».',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final banks = widget.banks;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: _Header(source: widget.source)),
          if (_message != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
          if (banks.installed.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Выберите свой банк из списка ниже.'),
              ),
            )
          else
            _BankList(banks.installed, onTap: _open),
          if (banks.others.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Другие банки', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            _BankList(banks.others, onTap: _open),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final C2bmembersSource source;

  const _Header({required this.source});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          height: 5,
          width: 50,
          decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(10)), color: Colors.grey),
        ),
        const SizedBox(height: 20),
        Image.asset('packages/sbp/assets/sbp.png', width: 100),
        const SizedBox(height: 10),
        const Text('Выберите банк для оплаты по СБП'),
        Text('Список банков: ${source.name}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _BankList extends StatelessWidget {
  final List<C2bmemberModel> banks;
  final ValueChanged<C2bmemberModel> onTap;

  const _BankList(this.banks, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: banks.length,
      itemBuilder: (context, index) {
        final bank = banks[index];
        return ListTile(
          leading: SizedBox.square(
            dimension: 40,
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _BankIcon(bank)),
          ),
          title: Text(bank.localName ?? bank.bankName),
          onTap: () => onTap(bank),
        );
      },
    );
  }
}

class _BankIcon extends StatelessWidget {
  final C2bmemberModel bank;

  const _BankIcon(this.bank);

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.account_balance);
    if (bank.bitmap != null) return Image.memory(bank.bitmap!);
    if (bank.icon.isNotEmpty) return Image.asset(bank.icon, errorBuilder: (_, __, ___) => fallback);
    if (bank.logoURL.isNotEmpty) return Image.network(bank.logoURL, errorBuilder: (_, __, ___) => fallback);
    return fallback;
  }
}
