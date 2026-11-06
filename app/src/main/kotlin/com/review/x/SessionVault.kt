package com.review.x

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SessionVault(context: Context, name: String = "compose-session-v1") {
    private val file = AtomicFile(File(context.noBackupFilesDir, name.also { require(it.matches(Regex("compose-[a-z0-9-]+"))) }))
    private fun key(create: Boolean = true): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        check(create) { "本机加密密钥不可用，原数据已保留" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(): Session? = readSecret()?.let(Session::parse)
    fun readSecret(): String? = synchronized(lock) {
        require(file.baseFile.length() <= 16 * 1024 * 1024) { "本机加密文件损坏" }
        val bytes = try { file.readFully() } catch (_: FileNotFoundException) { return null }
        require(bytes.size in 29..(16 * 1024 * 1024)) { "本机加密文件损坏" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    }
    fun save(session: Session) = writeSecret(session.cookie)
    fun writeSecret(value: String) = synchronized(lock) {
        require(value.toByteArray(Charsets.UTF_8).size <= 16 * 1024 * 1024)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val bytes = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
    fun clear() = synchronized(lock) { file.delete() }
    companion object { private const val ALIAS = "reviewx-compose-session-v1"; private val lock = Any() }
}
