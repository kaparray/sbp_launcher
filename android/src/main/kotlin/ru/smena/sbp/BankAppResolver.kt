package ru.smena.sbp

/** Банк из c2bmembers.json, который нужно найти на устройстве */
internal data class BankQuery(val schema: String, val packageName: String?)

/** Найденный банк: schema из json и реальный package приложения, которое её обрабатывает */
internal data class ResolvedBank(val schema: String, val packageName: String)

/**
 * Определяет установленные банки без статического списка пакетов.
 *
 * Источник 1: приложение, которое обрабатывает ссылку `<schema>://qr.nspk.ru/`.
 * Источник 2: приложение с package из json, которое обрабатывает `https://qr.nspk.ru/`.
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
                    schemeHandlers.firstOrNull { it == bank.packageName } ?: schemeHandlers.first()

                !bank.packageName.isNullOrBlank() && bank.packageName in httpsHandlers ->
                    bank.packageName

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
