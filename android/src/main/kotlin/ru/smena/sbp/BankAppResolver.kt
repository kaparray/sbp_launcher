package ru.smena.sbp

/**
 * Банк из c2bmembers.json, который нужно найти на устройстве.
 * [packageNames] - package из json и дополнительные известные пакеты банка (по приоритету).
 */
internal data class BankQuery(val schema: String, val packageNames: List<String>)

/** Найденный банк: schema из json и реальный package приложения, которое её обрабатывает */
internal data class ResolvedBank(val schema: String, val packageName: String)

/**
 * Определяет установленные банки без статического списка пакетов.
 *
 * Источник 1: приложение, которое обрабатывает ссылку `<schema>://qr.nspk.ru/`.
 * Источник 2: приложение с одним из пакетов банка, которое обрабатывает `https://qr.nspk.ru/`.
 *
 * [handlersFor] возвращает пакеты activity, которые открывают переданную ссылку
 * (PackageManager.queryIntentActivities). Вынесено в параметр, чтобы логику можно было
 * тестировать без Android.
 */
internal class BankAppResolver(private val handlersFor: (String) -> List<String>) {

    fun resolve(banks: List<BankQuery>): List<ResolvedBank> {
        val httpsHandlers by lazy { handlersFor(NSPK_HTTPS_URI).toSet() }
        val resolved = mutableListOf<ResolvedBank>()
        for (bank in banks) {
            val schemeHandlers =
                if (isValidScheme(bank.schema)) handlersFor(schemeUri(bank.schema)) else emptyList()
            val packageName = when {
                schemeHandlers.isNotEmpty() ->
                    bank.packageNames.firstOrNull { it in schemeHandlers } ?: schemeHandlers.first()

                bank.packageNames.isNotEmpty() ->
                    bank.packageNames.firstOrNull { it in httpsHandlers }

                else -> null
            }
            if (packageName != null) resolved.add(ResolvedBank(bank.schema, packageName))
        }
        return resolved
    }

    companion object {
        const val NSPK_HOST = "qr.nspk.ru"
        const val NSPK_HTTPS_URI = "https://$NSPK_HOST/"

        private val SCHEME = Regex("[A-Za-z][A-Za-z0-9+.-]*")

        fun schemeUri(schema: String) = "$schema://$NSPK_HOST/"

        fun isValidScheme(schema: String) = SCHEME.matches(schema)
    }
}
