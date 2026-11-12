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

class SessionVault(private val context: Context, private val name: String = "compose-session-v1", private val keyProvider: ((Boolean)->SecretKey)? = null) {
    private val file = AtomicFile(File(context.noBackupFilesDir, name.also { require(it.matches(Regex("compose-[a-z0-9-]+"))) }))
    private fun key(create: Boolean = true): SecretKey {
        keyProvider?.let { return it(create) }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        if(!create)throw SecretReadFailure(SecretFailureKind.MISSING_KEY)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(): Session? = readSecret()?.let(Session::parse)
    fun readSecret(): String? = synchronized(lock) { readEncrypted {
        require(file.baseFile.length() <= 16 * 1024 * 1024) { "本机加密文件损坏" }
        val bytes = try { file.readFully() } catch (_: FileNotFoundException) { return@readEncrypted null }
        require(bytes.size in 28..(16 * 1024 * 1024)) { "本机加密文件损坏" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
    } }
    fun save(session: Session) = writeSecret(session.cookie)
    fun writeSecret(value: String, recoverUnreadable: Boolean = false) = synchronized(lock) {
        try {readSecret()}catch(e:SecretReadFailure){if(!recoverUnreadable || !e.recoverable)throw e;archiveEncryptedFile(context,file.baseFile)}
        require(value.toByteArray(Charsets.UTF_8).size <= 16 * 1024 * 1024 - 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val bytes = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream);if(name=="compose-session-v1")revision.incrementAndGet() }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
    internal fun encryptedSnapshot():ByteArray? = synchronized(lock) {try{file.readFully()}catch(_:FileNotFoundException){null}}
    internal fun restoreEncrypted(bytes:ByteArray?) = synchronized(lock) {
        if(bytes==null)file.delete()else {
            val output=file.startWrite()
            try{output.write(bytes);file.finishWrite(output)}catch(e:Exception){file.failWrite(output);throw e}
        }
        if(name=="compose-session-v1")revision.incrementAndGet()
    }
    fun clear() = synchronized(lock) { file.delete();if(name=="compose-session-v1")revision.incrementAndGet();Unit }
    companion object { private const val ALIAS = "reviewx-compose-session-v1"; private val lock = Any()
        internal val revision=java.util.concurrent.atomic.AtomicLong()
        internal fun <T> atomic(block:()->T):T = synchronized(lock,block)
    }
}
