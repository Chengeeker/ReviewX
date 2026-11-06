package com.review.x

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONObject
import java.security.KeyStore
import android.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import java.security.spec.MGF1ParameterSpec

object LegacyImport {
    @Suppress("DEPRECATION")
    fun credentials(context: Context, settings: AppSettings) {
        if (settings.bool("flutter_credentials_imported")) return
        val existing = context.getSharedPreferences("FlutterSecureStorage", 0)
        val vault = SessionVault(context)
        if (existing.all.isEmpty()) { settings.set("flutter_credentials_imported", true); return }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val prefix = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_"
        val names=listOf("twitter_session_v1","webdav_config")
        val encrypted=existing.contains("__androidx_security_crypto_encrypted_prefs_key_keyset__") && names.none {existing.contains(prefix+it)}
        val values=if(encrypted) {
            check(store.containsAlias(MasterKey.DEFAULT_MASTER_KEY_ALIAS) && existing.contains("__androidx_security_crypto_encrypted_prefs_value_keyset__")) { "旧安全存储密钥不可用，原数据已保留；可重新登录或导入备份" }
            val prefs=EncryptedSharedPreferences.create(context,"FlutterSecureStorage",MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
            names.associateWith {prefs.getString(prefix+it,null)}
        } else if(names.none {existing.contains(prefix+it)}) emptyMap() else {
            val oaep=when(existing.getString("FlutterSecureSAlgorithmKey","RSA_ECB_PKCS1Padding")) {"RSA_ECB_PKCS1Padding"->false;"RSA_ECB_OAEPwithSHA_256andMGF1Padding"->true;else->error("旧安全存储算法不受支持，原数据已保留")}
            val gcm=when(existing.getString("FlutterSecureSAlgorithmStorage","AES_CBC_PKCS7Padding")) {"AES_CBC_PKCS7Padding"->false;"AES_GCM_NoPadding"->true;else->error("旧安全存储算法不受支持，原数据已保留")}
            val alias=context.packageName+".FlutterSecureStoragePluginKey"+if(oaep)"OAEP"else ""
            val key=store.getKey(alias,null) ?: error("旧安全存储密钥不可用，原数据已保留")
            val wrapped=context.getSharedPreferences("FlutterSecureKeyStorage",0).getString(if(gcm)"VGhpcyBpcyB0aGUga2V5IGZvcihBIHNlY3XyZZBzdG9yYWdlIEFFUyBLZXkK"else "VGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK",null) ?: error("旧安全存储密钥不可用，原数据已保留")
            val rsa=Cipher.getInstance(if(oaep)"RSA/ECB/OAEPPadding"else "RSA/ECB/PKCS1Padding","AndroidKeyStoreBCWorkaround")
            rsa.init(Cipher.UNWRAP_MODE,key,if(oaep)OAEPParameterSpec("SHA-256","MGF1",MGF1ParameterSpec.SHA1,PSource.PSpecified.DEFAULT)else null)
            val aes=rsa.unwrap(Base64.decode(wrapped,Base64.DEFAULT),"AES",Cipher.SECRET_KEY)
            names.associateWith {name->existing.getString(prefix+name,null)?.let {raw->
                require(raw.length<=1024*1024){"旧安全存储内容过大，原数据已保留"}
                decryptLegacy(Base64.decode(raw,Base64.DEFAULT),aes,gcm).toString(Charsets.UTF_8)
            }}
        }
        if (vault.read() == null) values["twitter_session_v1"]?.let { raw ->
            val data = JSONObject(raw); val session = validatedSession(data)
            vault.save(session)
        }
        val dav = SessionVault(context, "compose-webdav-v1")
        if (dav.readSecret() == null) values["webdav_config"]?.let { dav.writeSecret(JSONObject(it).toString()) }
        settings.set("flutter_credentials_imported", true)
    }
    internal fun decryptLegacy(bytes:ByteArray,key:java.security.Key,gcm:Boolean):ByteArray {
        val ivSize=if(gcm)12 else 16
        require(bytes.size>=ivSize+16 && bytes.size<=1024*1024){"旧安全存储内容损坏，原数据已保留"}
        val cipher=Cipher.getInstance(if(gcm)"AES/GCM/NoPadding"else "AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE,key,if(gcm)GCMParameterSpec(128,bytes.copyOfRange(0,ivSize))else IvParameterSpec(bytes.copyOfRange(0,ivSize)))
        return cipher.doFinal(bytes,ivSize,bytes.size-ivSize)
    }
    fun validatedSession(raw: JSONObject): Session {
        val user = raw.str("userId")
        require(user.matches(Regex("\\d+"))) { "备份中的账号无效" }
        val session = Session.parse(raw.getString("cookie"))
        require(session.userId == null || session.userId == user) { "备份中的账号不一致" }
        return if (session.userId == null) Session.parse(session.cookie + "; twid=u%3D$user") else session
    }
}
