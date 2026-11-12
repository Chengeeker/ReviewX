package com.review.x
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35],manifest=Config.NONE,shadows=[ReplacingAtomicFileShadow::class])
class FreshLoginRecoveryTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private fun newKey()=KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private var deviceKey:SecretKey?=newKey()
    private val keys:(Boolean)->SecretKey={create->deviceKey?:if(create)newKey().also{deviceKey=it}else throw SecretReadFailure(SecretFailureKind.MISSING_KEY)}
    private fun archived(bytes:ByteArray)=File(context.noBackupFilesDir,"account-recovery").listFiles().orEmpty().any{it.readBytes().contentEquals(bytes)}

    private val vault=SessionVault(context,keyProvider=keys)
    private val file get()=File(context.noBackupFilesDir,"compose-session-v1")
    private fun account(id:String)=Session.parse("auth_token=synthetic-$id; ct0=synthetic; twid=u%3D$id")
    @Test fun verifiedFreshLoginCanReplaceWrongDeviceCiphertext() {
        vault.save(account("1"));val old=file.readBytes();deviceKey=newKey()
        vault.writeSecret(account("2").cookie,recoverUnreadable=true)
        assertEquals("2",vault.read()!!.userId);assertTrue(archived(old))
    }
    @Test fun ordinaryMigrationCannotReplaceMissingKey() {
        vault.save(account("1"));val old=file.readBytes();deviceKey=null
        try{vault.save(account("2"));fail()}catch(_:SecretReadFailure){}
        assertArrayEquals(old,file.readBytes());assertNull(deviceKey)
    }
}
