package ru.smena.sbp

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BankAppResolverTest {

    private fun resolver(handlers: Map<String, List<String>>, queried: MutableList<String> = mutableListOf()) =
        BankAppResolver { uri ->
            queried.add(uri)
            handlers[uri].orEmpty()
        }

    @Test
    fun `bank is found by its scheme even without package in json`() {
        val result = resolver(mapOf("bank100000000284://qr.nspk.ru/" to listOf("ru.zhuck.webapp")))
            .resolve(listOf(BankQuery("bank100000000284", emptyList())))

        assertEquals(listOf(ResolvedBank("bank100000000284", "ru.zhuck.webapp")), result)
    }

    @Test
    fun `real package from PackageManager wins over stale package in json`() {
        val result = resolver(mapOf("bank100000000030://qr.nspk.ru/" to listOf("ru.unicredit.android")))
            .resolve(listOf(BankQuery("bank100000000030", listOf("ru.ucb.android"))))

        assertEquals("ru.unicredit.android", result.single().packageName)
    }

    @Test
    fun `json package is preferred when several apps handle the scheme`() {
        val result = resolver(mapOf("bank1://qr.nspk.ru/" to listOf("other.app", "bank.app")))
            .resolve(listOf(BankQuery("bank1", listOf("bank.app"))))

        assertEquals("bank.app", result.single().packageName)
    }

    @Test
    fun `https handler is used as a second source and matched by package`() {
        val result = resolver(
            mapOf(BankAppResolver.NSPK_HTTPS_URI to listOf("com.android.chrome", "ru.sberbankmobile")),
        ).resolve(
            listOf(
                BankQuery("bank100000000111", listOf("ru.sberbankmobile")),
                BankQuery("bank100000000004", listOf("com.idamob.tinkoff.android")),
            ),
        )

        assertEquals(listOf(ResolvedBank("bank100000000111", "ru.sberbankmobile")), result)
    }

    @Test
    fun `white-label app serving several banks is reported for each bank`() {
        val atlas = "com.intervale.sbp.atlas"
        val result = resolver(
            mapOf("bank100000000148://qr.nspk.ru/" to listOf(atlas), "bank100000000197://qr.nspk.ru/" to listOf(atlas)),
        ).resolve(listOf(BankQuery("bank100000000148", listOf(atlas)), BankQuery("bank100000000197", listOf(atlas))))

        assertEquals(listOf("bank100000000148", "bank100000000197"), result.map { it.schema })
    }

    @Test
    fun `extra package of the bank is found via https handlers`() {
        val result = resolver(mapOf(BankAppResolver.NSPK_HTTPS_URI to listOf("ru.rshb.ownfinance")))
            .resolve(listOf(BankQuery("bank100000000020", listOf("ru.rshb.dbo", "ru.rshb.ownfinance"))))

        assertEquals(listOf(ResolvedBank("bank100000000020", "ru.rshb.ownfinance")), result)
    }

    @Test
    fun `json package wins over extra package when both handle the scheme`() {
        val result = resolver(mapOf("bank100000000020://qr.nspk.ru/" to listOf("ru.rshb.ownfinance", "ru.rshb.dbo")))
            .resolve(listOf(BankQuery("bank100000000020", listOf("ru.rshb.dbo", "ru.rshb.ownfinance"))))

        assertEquals("ru.rshb.dbo", result.single().packageName)
    }

    @Test
    fun `not installed bank and invalid scheme are skipped without querying`() {
        val queried = mutableListOf<String>()
        val result = resolver(emptyMap(), queried)
            .resolve(listOf(BankQuery("bank1", listOf("bank.app")), BankQuery("", emptyList()), BankQuery("bad scheme", emptyList())))

        assertTrue(result.isEmpty())
        assertEquals(listOf("bank1://qr.nspk.ru/", BankAppResolver.NSPK_HTTPS_URI), queried)
    }
}
