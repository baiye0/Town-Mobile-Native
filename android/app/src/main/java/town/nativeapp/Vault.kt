package town.nativeapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class Vault(context: Context, private val namespace: String = "vault") {
    private val prefs = context.getSharedPreferences(namespace, Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(if (namespace == "vault") "town-connection" else "town-$namespace", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(if (namespace == "vault") "town-connection" else "town-$namespace", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(link: String?) {
        if (link == null) { check(prefs.edit().clear().commit()); return }
        val c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE, key())
        check(prefs.edit().putString("data", Base64.encodeToString(c.iv + c.doFinal(link.toByteArray()), Base64.NO_WRAP)).commit())
    }
    fun load(): String? = runCatching {
        val bytes = Base64.decode(prefs.getString("data", null) ?: return null, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        String(c.doFinal(bytes.copyOfRange(12, bytes.size)))
    }.getOrNull()
}
