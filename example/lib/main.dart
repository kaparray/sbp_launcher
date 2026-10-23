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

/// Банки для шторки: установленные сверху, остальные - «другие банки»
class SbpBanks {
  final List<C2bmemberModel> installed;
  final List<C2bmemberModel> others;
  final C2bmembersSource source;

  const SbpBanks(this.installed, this.others, this.source);
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  /// В продакшене укажите url своего прокси для c2bmembers.json
  final _repository = C2bmembersRepository();
  late final Future<SbpBanks> _banks = _loadBanks();

  Future<SbpBanks> _loadBanks() async {
    final loaded = await _repository.load();
    final all = loaded.model.c2bmembersModel;
    final installed = await Sbp.getInstalledBanks(loaded.model);
    final installedSchemas = installed.map((bank) => bank.schema).toSet();
    final others = all.where((bank) => !installedSchemas.contains(bank.schema)).toList();
    return SbpBanks(installed, others, loaded.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('СБП')),
      body: Center(
        child: FilledButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (_) => FutureBuilder<SbpBanks>(
              future: _banks,
              builder: (context, snapshot) {
                final banks = snapshot.data;
                if (banks == null) {
                  return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                }
                return SbpBanksSheet(banks: banks, url: sbpPaymentUrl);
              },
            ),
          ),
          child: const Text('Оплатить через СБП'),
        ),
      ),
    );
  }
}

class SbpBanksSheet extends StatelessWidget {
  final SbpBanks banks;
  final String url;

  const SbpBanksSheet({super.key, required this.banks, required this.url});

  Future<void> _open(BuildContext context, C2bmemberModel bank) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Sbp.launchBank(url, bank);
    switch (result) {
      case SbpOpenResult.opened:
        break;
      case SbpOpenResult.notInstalled:
        messenger.showSnackBar(SnackBar(content: Text('Приложение «${bank.bankName}» не установлено')));
      case SbpOpenResult.error:
        messenger.showSnackBar(SnackBar(content: Text('Не удалось открыть «${bank.bankName}»')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: _Header(source: banks.source)),
          if (banks.installed.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Не нашли установленных банков. Выберите свой банк из списка ниже.'),
              ),
            )
          else
            _BankList(banks.installed, onTap: (bank) => _open(context, bank)),
          if (banks.others.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Другие банки', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            _BankList(banks.others, onTap: (bank) => _open(context, bank)),
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
