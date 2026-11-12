package com.review.x
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35],manifest=Config.NONE,shadows=[ReplacingAtomicFileShadow::class])
class BackupLoginRestoreTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()

    private val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private val session=SessionVault(context,keyProvider={key})
    private val dav=SessionVault(context,"compose-webdav-v1",keyProvider={key})
    private val journal=SessionVault(context,"compose-restore-journal-v1",keyProvider={key})
    private val settings=AppSettings(context)
    private val backup=BackupService(context,settings,session,dav,journal)
    private fun account(id:String)=Session.parse("auth_token=synthetic-$id; ct0=synthetic; twid=u%3D$id")
    private fun data(full:Boolean=true)=JSONObject().put("app","com.review.x").put("schema",1).put("backup_mode",if(full)"full"else"safe")
        .put("appearance",JSONObject().put("theme_mode",2)).put("reading",JSONObject()).put("webdav",JSONObject())
        .apply{if(full)put("credentials",JSONObject().put("session",JSONObject().put("userId","2").put("cookie",account("2").cookie)).put("webdav_password",""))}
    private fun seed(){session.save(account("1"));settings.replace(JSONObject().put("theme_mode",0))}
    private fun uid()=session.read()?.userId
    private fun theme()=settings.int("theme_mode",0)

    @Test fun verifiedLoginCommitsAndSurvivesARead()=runBlocking{seed();val result=backup.restore(data(),true){it};assertTrue(result.contains("通过验证"));assertEquals("2",uid());assertEquals(2,theme())}
    @Test fun validationFailureRestoresOnlyNonLoginData()=runBlocking{seed();val result=backup.restore(data(),true){error("synthetic validation failure")};assertTrue(result.contains("账号登录未恢复"));assertEquals("1",uid());assertEquals(2,theme())}
    @Test fun safeRestoreKeepsCurrentLogin()=runBlocking{seed();backup.restore(data(false),false){error("Safe restore must not verify")};assertEquals("1",uid());assertEquals(2,theme())}
    @Test fun newLoginDuringValidationOwnsTheState()=runBlocking{
        seed();try{backup.restore(data(),true){session.save(account("3"));it};fail("Stale restore must stop")}catch(_:IllegalStateException){}
        assertEquals("3",uid());assertEquals(0,theme())
    }
    @Test fun cancellationDoesNotLookLikePartialSuccess()=runBlocking{
        seed();try{backup.restore(data(),true){throw CancellationException()};fail("Cancellation must propagate")}catch(_:CancellationException){}
        assertEquals("1",uid());assertEquals(0,theme())
    }
}
