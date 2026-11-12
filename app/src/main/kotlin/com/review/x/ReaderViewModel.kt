package com.review.x

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import java.util.UUID

data class ReaderScreen(val feed: Feed = Feed(), val posts: List<Post> = emptyList(), val cursor: String? = null,
    val loaded: Boolean = false, val busy: Boolean = false, val error: String? = null, val profile: User? = null,
    val users: List<User> = emptyList(), val notifications: List<SocialNotification> = emptyList(), val trends: List<Trend> = emptyList(),
    val key: String = UUID.randomUUID().toString(), val selectedPost: Post? = null,val replyParent:Post?=null,
    val auxiliaryError:String?=null,val profileError:Boolean=false, val topCursor:String?=null,val markedRead:Boolean=false,val markingRead:Boolean=false,val readUncertain:Boolean=false,
    val restoredSnapshot: Boolean = false, val pullRefreshing: Boolean = false) {
    val canLoadMore get() = cursor != null || restoredSnapshot
    internal fun shouldPrefetch(lastVisible: Int, totalItems: Int, hasScrolled: Boolean): Boolean =
        loaded && !busy && error == null && canLoadMore && totalItems > 0 && lastVisible >= 0 &&
            (!restoredSnapshot || hasScrolled) &&
            (lastVisible >= totalItems - 8 || lastVisible + 1 >= totalItems * .6f)
}
data class ReaderState(val user: User? = null, val accountId: String? = null, val authenticating: Boolean = true, val loginError: String? = null,
    val screens: List<ReaderScreen> = listOf(ReaderScreen()), val expired: Boolean = false, val theme: String = "system",
    val rootTab: Int = 0, val homeTab: Int = 0, val pending: Set<String> = emptySet(), val uncertain: Set<String> = emptySet(),
    val message: String? = null, val restoring:Boolean=false,val startupError:String?=null, val settings: JSONObject = JSONObject()) {
    val screen get() = screens.last()
    val loggedIn get() = accountId != null
}
class ReaderViewModel(application: Application) : AndroidViewModel(application) {
    val settings = AppSettings(application)
    val backup = BackupService(application, settings)
    private val snapshots = LocalSnapshots(settings)
    private val repository = ReaderRepository(application)
    private val vault = SessionVault(application)
    private val mutable = MutableStateFlow(ReaderState(restoring=true,settings=settings.snapshot()))
    val state = mutable.asStateFlow()
    private var session: Session? = null
    private var work: Job? = null
    private var generation = 0
    private var accountEpoch = 0
    private val roots = mutableMapOf<String, ReaderScreen>()
    private val mutations = mutableMapOf<String,Job>()
    private val deleted=mutableSetOf<String>()
    private val updated = mutableMapOf<String,Post>()
    private var pendingLink: String? = null
    init {
        viewModelScope.launch { settings.changes.collect { mutable.value=mutable.value.copy(settings=JSONObject(it.toString())) } }
        restore()
    }
    fun restore() {
        work?.cancel(); val epoch=++generation
        mutable.value=mutable.value.copy(authenticating=true,restoring=true,startupError=null,loginError=null)
        work=viewModelScope.launch {
            try {
                val stored=withContext(Dispatchers.IO) {
                    backup.recoverInterruptedRestore(); settings.importFlutter(getApplication())
                    try { LegacyImport.credentials(getApplication(),settings) } catch (_:Exception) { message("旧登录无法自动读取，原数据已保留；请重新登录或导入备份") }
                    AppNetwork.initialize(getApplication())
                    try { NativeServices.enforceCacheLimit(getApplication()) }
                    catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) { DiagnosticLog.record("cache.automatic.failure", error = error) }
                    vault.read()
                }
                if(epoch!=generation) {return@launch}
                val changed=session?.cookie!=stored?.cookie
                if(changed || mutable.value.screen.feed.kind=="Login") {
                    accountEpoch++;mutations.values.toList().forEach {it.cancel()};mutations.clear();updated.clear();deleted.clear();roots.clear()
                    mutable.value=ReaderState(authenticating=true,restoring=true,settings=settings.snapshot())
                }
                session=stored
                if(stored==null) { mutable.value=mutable.value.copy(authenticating=false,restoring=false); return@launch }
                val account = requireNotNull(stored.userId)
                val (user, homeSnapshots) = withContext(Dispatchers.IO) {
                    snapshots.profile(account) to listOf(Feed(), Feed("HomeLatestTimeline", title = "正在关注"))
                        .mapNotNull { feed -> snapshots.homeScreen(account, feed) }
                }
                if (epoch != generation || session !== stored) return@launch
                homeSnapshots.forEach { roots.putIfAbsent(rootId(it.feed), it) }
                val current = mutable.value
                val screen = current.screen
                val restored = if (!screen.loaded && screen.posts.isEmpty() && current.screens.size == 1)
                    roots[rootId(screen.feed)] ?: screen
                else screen
                mutable.value = current.copy(
                    user = user, accountId = account, authenticating = false, restoring = false,
                    screens = current.screens.dropLast(1) + restored.copy(busy = false),
                )
                work = null
                if (!restored.loaded) load()
                refreshIdentity()
                NotificationWorker.sync(getApplication(),true)
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==generation) mutable.value=mutable.value.copy(authenticating=false,restoring=false,startupError=safeError(error),loginError=safeError(error),message=safeError(error)) }
        }
    }
    suspend fun reloadAfterBackup() {
        val epoch=accountEpoch
        val restored=withContext(Dispatchers.IO){vault.read()}
        if(epoch!=accountEpoch)return
        if(session?.cookie!=restored?.cookie) {
            work?.cancel();generation++;accountEpoch++
            mutations.values.toList().forEach{it.cancel()};mutations.clear();updated.clear();deleted.clear();roots.clear()
            session=restored
            mutable.value=mutable.value.copy(user=null,accountId=restored?.userId,authenticating=false,restoring=false,expired=false,settings=settings.snapshot())
            refreshIdentity()
        }
    }
    fun login(cookie: String) {
        work?.cancel(); val epoch=++generation
        mutable.value=mutable.value.copy(authenticating=true,loginError=null)
        work=viewModelScope.launch {
            try {
                val (validated,user)=repository.validate(cookie)
                if(epoch!=generation) {return@launch}
                withContext(Dispatchers.IO) { vault.writeSecret(validated.cookie, recoverUnreadable = true); settings.set("flutter_credentials_imported",true); snapshots.profile(user.id,user) }
                accountEpoch++; session=validated; updated.clear();deleted.clear(); roots.clear()
                mutable.value=ReaderState(user=user,accountId=user.id,authenticating=false,settings=settings.snapshot())
                work=null; load(); NotificationWorker.sync(getApplication(),true)
                pendingLink?.let { pendingLink=null; handleLink(it) }
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==generation) mutable.value=mutable.value.copy(authenticating=false,loginError=safeError(error)) }
        }
    }
    fun refreshIdentity(userTriggered:Boolean=false,onValidated:((User)->Unit)?=null) {
        val captured=session ?: return; val epoch=accountEpoch
        if(userTriggered||onValidated!=null)mutable.value=mutable.value.copy(authenticating=true)
        viewModelScope.launch {
            try {
                val user=repository.validate(captured.cookie).second
                if(epoch!=accountEpoch) return@launch
                mutable.value=mutable.value.copy(user=user,expired=false)
                withContext(Dispatchers.IO) { snapshots.profile(user.id,user) }
                if(userTriggered && epoch==accountEpoch)message("X 已确认当前登录请求有效")
                if(epoch==accountEpoch)onValidated?.invoke(user)
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==accountEpoch) report(error) }
            finally {if((userTriggered||onValidated!=null) && epoch==accountEpoch)mutable.value=mutable.value.copy(authenticating=false)}
        }
    }
    fun openOwnProfile() {
        val state=mutable.value
        if(!state.loggedIn){open(Feed("Login",title="账号登录"));return}
        state.user?.let{openUser(it);return}
        if(state.authenticating){message("账号正在处理中，请稍后再试");return}
        refreshIdentity(onValidated={openUser(it)})
    }
    private fun rootId(feed:Feed)=feed.kind+":"+feed.option
    private fun rememberRoot() { if(mutable.value.screens.size==1) roots[rootId(mutable.value.screen.feed)]=mutable.value.screen.copy(busy=false) }
    fun selectRoot(tab:Int) {
        roots.keys.removeAll{it.startsWith("history:")}
        rememberRoot(); work?.cancel(); generation++
        val feed=when(tab) { 1->Feed("Explore",title="探索",option="true"); 2->Feed("Settings",title="设置"); else->if(mutable.value.homeTab==1) Feed("HomeLatestTimeline",title="正在关注") else Feed() }
        mutable.value=mutable.value.copy(rootTab=tab,screens=listOf(roots[rootId(feed)] ?: ReaderScreen(feed=feed)))
        if(!mutable.value.screen.loaded) load()
    }
    fun cachedHome(tab:Int):ReaderScreen {val feed=if(tab==1)Feed("HomeLatestTimeline",title="正在关注")else Feed();return roots[rootId(feed)] ?: ReaderScreen(feed=feed,key="home-placeholder-$tab")}
    fun selectHome(tab:Int) {
        if(tab==mutable.value.homeTab && mutable.value.rootTab==0)return
        roots.keys.removeAll{it.startsWith("history:")}
        rememberRoot(); work?.cancel(); generation++
        val feed=if(tab==1) Feed("HomeLatestTimeline",title="正在关注") else Feed()
        mutable.value=mutable.value.copy(homeTab=tab,rootTab=0,screens=listOf(roots[rootId(feed)] ?: ReaderScreen(feed=feed)))
        if(!mutable.value.screen.loaded) load()
    }
    fun explore(personalized:Boolean) { open(Feed("Explore",title="探索",option=personalized.toString()),root=true) }
    fun open(feed:Feed,profile:User?=null,root:Boolean=false,post:Post?=null) {
        if(!root && mutable.value.screen.feed==feed) return
        rememberRoot(); work?.cancel(); generation++
        if(root)roots.keys.removeAll{it.startsWith("history:")}
        val stack=if(root) emptyList() else mutable.value.screens.map { it.copy(busy=false) }
        mutable.value=mutable.value.copy(screens=stack+ReaderScreen(feed=feed,profile=profile,selectedPost=post))
        if(feed.kind=="TweetDetail" && post!=null) session?.userId?.let { id -> viewModelScope.launch(Dispatchers.IO) { runCatching { settings.addHistory(id,post) } } }
        load()
    }
    fun openPost(post:Post)=open(Feed("TweetDetail",post.id,"帖子详情"),post=effective(post))
    fun replaceFeed(feed:Feed) {
        work?.cancel(); generation++
        val screen=mutable.value.screen
        val sortingReplies = screen.feed.kind == "TweetDetail" && feed.kind == "TweetDetail" && feed.value == screen.feed.value
        if(screen.feed.option=="account_history")roots["history:${screen.key}:${screen.feed.kind}"]=screen.copy(busy=false)
        updateScreen {
            if (sortingReplies) screen.copy(feed=feed,cursor=null,busy=false,error=null,pullRefreshing=false)
            else if(feed.option=="account_history")roots["history:${screen.key}:${feed.kind}"] ?: ReaderScreen(feed=feed,key=screen.key)
            else ReaderScreen(feed=feed,key=screen.key,profile=screen.profile,selectedPost=screen.selectedPost,replyParent=screen.replyParent)
        }
        if(sortingReplies || !mutable.value.screen.loaded)load()
    }
    fun openUser(user:User)=open(Feed("UserTweets",user.id,user.name),profile=user)
    fun search(query:String,product:String="Top") {
        if(query.isBlank()) return
        session?.userId?.let { settings.addSearch(it,query) }
        val feed=Feed("SearchTimeline",query.trim(),"搜索结果",product)
        if(mutable.value.screen.feed.kind=="SearchTimeline")replaceFeed(feed)else open(feed)
    }
    suspend fun suggestedUsers(query:String):List<User> {
        val captured=session ?: return emptyList();val epoch=accountEpoch
        val result=repository.users(captured,Feed("SearchTimeline",query,option="People"),null).users.take(8)
        return if(epoch==accountEpoch && session===captured)result else emptyList()
    }
    fun back() {
        if(mutable.value.screens.size<=1) return
        work?.cancel(); generation++
        val removed=mutable.value.screen.key
        roots.keys.removeAll{it.startsWith("history:$removed:")}
        mutable.value=mutable.value.copy(screens=mutable.value.screens.dropLast(1))
        if(!mutable.value.screen.loaded) load()
    }
    fun load(more:Boolean=false, fromPull:Boolean=false) {
        val screen=mutable.value.screen
        if(screen.feed.kind=="Likes" && screen.profile!=null && screen.profile.id!=mutable.value.accountId){updateScreen {it.copy(loaded=true,busy=false,error=null)};return}
        val remote=screen.feed.kind in apiFeeds
        if(!remote) { updateScreen { it.copy(loaded=true,busy=false) }; return }
        val captured=session ?: return
        if(screen.busy || (more && !screen.canLoadMore)) return
        val epoch=++generation; val account=accountEpoch
        updateScreen { it.copy(busy=true,error=null,pullRefreshing=fromPull) }
        work=viewModelScope.launch {
            try {
                val feed=screen.feed; val cursor=if(more) screen.cursor else null
                if(feed.kind=="ProfileLink"){
                    val user=repository.userByHandle(captured,feed.value)
                    if(epoch!=generation||account!=accountEpoch||session!==captured)return@launch
                    updateScreen{it.copy(feed=Feed("UserTweets",user.id,user.name),profile=user,loaded=false,busy=false,error=null)}
                    work=null;load();return@launch
                }
                var confirmedPosts=emptySet<String>()
                val next=when {
                    feed.kind=="Explore" -> {
                        var failure:String?=null
                        val trends=try {repository.trends(captured,feed.option!="false")}catch(e:CancellationException){throw e}catch(e:Exception){failure=safeError(e);screen.trends}
                        val users=if(feed.option=="false")emptyList()else try {repository.recommended(captured)}catch(e:CancellationException){throw e}catch(e:Exception){if(failure==null)failure=safeError(e);screen.users}
                        screen.copy(trends=trends,users=users,cursor=null,auxiliaryError=failure)
                    }
                    feed.kind=="NotificationsTimeline" -> {
                        val page=repository.notifications(captured,cursor)
                        screen.copy(notifications=((if(more || page.notifications.isEmpty()) screen.notifications else emptyList())+page.notifications).distinctBy { it.id }.takeLast(300),cursor=page.cursor,
                            topCursor=if(more)screen.topCursor else page.topCursor,markedRead=more && screen.markedRead,readUncertain=more && screen.readUncertain)
                    }
                    feed.kind in listOf("Followers","Following") || (feed.kind=="SearchTimeline" && feed.option=="People") -> {
                        val page=repository.users(captured,feed,cursor)
                        screen.copy(users=((if(more) screen.users else emptyList())+page.users).distinctBy { it.id }.takeLast(300),cursor=page.cursor)
                    }
                    feed.kind=="Article" -> screen.copy(posts=listOf(repository.article(captured,feed.value)),cursor=null)
                    else -> {
                        val page=repository.page(captured,feed,cursor,screen.loaded && !more,screen.posts.map { it.id })
                        confirmedPosts=page.posts.map {it.id}.toSet()
                        var profile=screen.profile;var profileError=false
                        if(feed.kind in profileFeeds && screen.profile!=null && !more) profile=try { repository.user(captured,feed.value).preservingCounts(profile) } catch(e:CancellationException) { throw e } catch(_:Exception) { profileError=true;profile }
                        var selected=screen.selectedPost
                        var parent=screen.replyParent
                        var posts=page.posts
                        if(feed.kind=="TweetDetail") {
                            selected=page.posts.firstOrNull { it.id==feed.value } ?: selected
                            parent=page.posts.firstOrNull {it.id==selected?.replyToId} ?: parent
                            if(selected==null && !more) throw ApiFailure("X 未返回链接对应的帖子")
                            val rootIndex=posts.indexOfFirst { it.id==feed.value }
                            posts=posts.drop(if(rootIndex>=0)rootIndex+1 else 0).filter { it.id!=feed.value && (selected?.conversationId.isNullOrBlank() || it.conversationId.isBlank() || it.conversationId==selected?.conversationId) }
                        }
                        screen.copy(posts=mergePosts(if(more || posts.isEmpty()) screen.posts else emptyList(),posts),cursor=page.cursor,profile=profile,profileError=profileError,selectedPost=selected,replyParent=parent)
                    }
                }
                if(epoch!=generation || account!=accountEpoch || session!==captured) return@launch
                if(!more) confirmedPosts.forEach { updated.remove(it) }
                mutable.value=mutable.value.copy(uncertain=mutable.value.uncertain-confirmedPosts-next.users.map { "user:${it.id}" }.toSet()-listOfNotNull(next.profile?.let { "user:${it.id}" }).toSet())
                updateScreen { next.copy(cursor=next.cursor?.takeUnless { more && it==screen.cursor },loaded=true,busy=false,error=null,restoredSnapshot=false,pullRefreshing=false) }
                if(screen.feed.kind=="TweetDetail" && !more)next.selectedPost?.let { post->withContext(Dispatchers.IO) { settings.addHistory(captured.userId!!,post) } }
                if (!more && confirmedPosts.isNotEmpty()) cacheHome(captured, next)
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==generation) { updateScreen { it.copy(busy=false,error=safeError(error),pullRefreshing=false) }; report(error,false) } }
        }
    }
    private suspend fun cacheHome(session:Session,screen:ReaderScreen) {
        val kind=cacheKind(screen.feed.kind) ?: return
        withContext(Dispatchers.IO) { runCatching { snapshots.timeline(session.userId!!,kind,screen.posts) } }
    }
    fun isDeleted(id:String)=id in deleted
    fun effective(post:Post):Post {
        val current=updated[post.id] ?: post
        return if(current.quote!=null) current.copy(quote=effective(current.quote)) else current
    }
    fun blocked(id:String)=id in mutable.value.pending || id in mutable.value.uncertain || mutable.value.expired
    fun markNotificationsRead() {
        val captured=session ?: return;val screen=mutable.value.screen;val cursor=screen.topCursor ?: return
        if(screen.markedRead||screen.markingRead||screen.readUncertain)return
        val epoch=accountEpoch;updateScreen {it.copy(markingRead=true)}
        viewModelScope.launch {
            try {repository.markRead(captured,cursor);if(epoch==accountEpoch && mutable.value.screen.key==screen.key)updateScreen {it.copy(markedRead=true)}}
            catch(e:CancellationException){throw e}
            catch(e:Exception){if(epoch==accountEpoch && mutable.value.screen.key==screen.key){updateScreen {it.copy(readUncertain=true)};report(e)}}
            finally{if(epoch==accountEpoch && mutable.value.screen.key==screen.key)updateScreen {it.copy(markingRead=false)}}
        }
    }
    fun mutate(post:Post,action:String) {
        val captured=session ?: return
        if(blocked(post.id)) return
        val current=effective(post); val epoch=accountEpoch
        mutable.value=mutable.value.copy(pending=mutable.value.pending+post.id)
        mutations[post.id]=viewModelScope.launch {
            try {
                val next=when(action) {
                    "like" -> { repository.like(captured,current.id,!current.liked); current.copy(liked=!current.liked,likes=(current.likes+if(current.liked) -1 else 1).coerceAtLeast(0)) }
                    "bookmark" -> { repository.bookmark(captured,current.id,!current.bookmarked); current.copy(bookmarked=!current.bookmarked) }
                    "repost" -> { repository.repost(captured,current.id,!current.reposted); current.copy(reposted=!current.reposted,reposts=(current.reposts+if(current.reposted) -1 else 1).coerceAtLeast(0)) }
                    "delete" -> { require(current.author.id==captured.userId); repository.delete(captured,current.id); null }
                    else -> throw IllegalArgumentException()
                }
                if(epoch!=accountEpoch) return@launch
                if(next!=null) updated[current.id]=next
                else {
                    deleted.add(current.id);updated.remove(current.id)
                    mutable.value=mutable.value.copy(screens=mutable.value.screens.map { it.copy(posts=it.posts.filterNot { p -> p.id==current.id }) })
                    roots.replaceAll { _,s -> s.copy(posts=s.posts.filterNot { it.id==current.id }) }
                    snapshots.remove(captured.userId!!,current.id)
                    if(mutable.value.screen.selectedPost?.id==current.id)back() else message("已删除帖子")
                }
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==accountEpoch) { if(error is ApiFailure && error.uncertain) mutable.value=mutable.value.copy(uncertain=mutable.value.uncertain+post.id); report(error) } }
            finally { if(epoch==accountEpoch) mutable.value=mutable.value.copy(pending=mutable.value.pending-post.id); if(mutations[post.id]===coroutineContext[Job])mutations.remove(post.id) }
        }
    }
    fun follow(user:User) {
        val captured=session ?: return; val key="user:${user.id}"; val epoch=accountEpoch
        if(blocked(key)) return
        mutable.value=mutable.value.copy(pending=mutable.value.pending+key)
        mutations[key]=viewModelScope.launch {
            try {
                val updated=repository.follow(captured,user.id,!user.isFollowing).preservingCounts(user)
                if(epoch==accountEpoch) mutable.value=mutable.value.copy(screens=mutable.value.screens.map { screen -> screen.copy(profile=if(screen.profile?.id==updated.id) updated else screen.profile,users=screen.users.map { if(it.id==updated.id) updated else it }) })
            } catch(cancelled:CancellationException) { throw cancelled }
            catch(error:Exception) { if(epoch==accountEpoch) { if(error is ApiFailure && error.uncertain) mutable.value=mutable.value.copy(uncertain=mutable.value.uncertain+key); report(error) } }
            finally { if(epoch==accountEpoch) mutable.value=mutable.value.copy(pending=mutable.value.pending-key); if(mutations[key]===coroutineContext[Job])mutations.remove(key) }
        }
    }
    suspend fun publish(text:String,reply:Post?,quote:Post?):String {
        val captured=session ?: throw ApiFailure("请登录 X")
        val epoch=accountEpoch
        val id=repository.publish(captured,text,reply?.id,quote?.let { "https://x.com/${it.author.handle}/status/${it.id}" })
        if(epoch!=accountEpoch) throw ApiFailure("账号已切换")
        return id
    }
    fun logout() {
        work?.cancel(); mutations.values.forEach { it.cancel() }; mutations.clear(); generation++; accountEpoch++
        work=viewModelScope.launch {
            try {
                val id=session?.userId
                withContext(Dispatchers.IO) { vault.clear(); settings.set("flutter_credentials_imported",true); if(id!=null) snapshots.clear(id) }
                session=null; updated.clear();deleted.clear(); roots.clear()
                mutable.value=ReaderState(authenticating=false,settings=settings.snapshot())
                NotificationWorker.sync(getApplication(),false)
            } catch(error:Exception) { report(error) }
        }
    }
    fun setSetting(key:String,value:Any):Boolean = runCatching { settings.set(key,value);if(key.startsWith("notification_"))NotificationWorker.sync(getApplication(),session!=null) }.onFailure { message("设置保存失败") }.isSuccess
    fun setReading(key:String,value:Any) {
        runCatching { settings.setReading(key,value) }.onFailure {
            mutable.value=mutable.value.copy(settings=settings.snapshot())
            message("设置保存失败")
        }
    }
    fun previewReading(key:String,value:Any) {
        val data=JSONObject(mutable.value.settings.toString())
        data.put("reading_settings",AppSettings.validatedReading(JSONObject(data.str("reading_settings","{}")).put(key,value)).toString())
        mutable.value=mutable.value.copy(settings=data)
    }
    fun setTheme(theme:String)=setSetting("theme_mode",when(theme){ "light"->1;"dark"->2;else->0 })
    suspend fun cookie():String=withContext(Dispatchers.IO) { vault.read()?.cookie ?: throw ApiFailure("当前没有登录会话") }
    fun message(text:String?) { mutable.value=mutable.value.copy(message=text) }
    private fun report(error:Exception,show:Boolean=true) { if(error is ApiFailure && error.expired) mutable.value=mutable.value.copy(expired=true); if(show) message(safeError(error)) }
    fun safeError(error:Throwable)=when(error) { is ApiFailure->error.message.orEmpty();is IllegalArgumentException->error.message?.take(160) ?: "输入格式无效";else->"操作未完成，请重试；原有数据已保留" }
    private fun updateScreen(transform:(ReaderScreen)->ReaderScreen) { mutable.value=mutable.value.copy(screens=mutable.value.screens.dropLast(1)+transform(mutable.value.screen)) }
    fun handleLink(url:String) {
        val target=DeepLinks.parse(url) ?: return
        if(session==null) { pendingLink=url; open(Feed("Login",title="账号登录")); return }
        when(target.kind) {
            "post" -> open(Feed("TweetDetail",target.value,"帖子详情"))
            "home" -> selectRoot(0)
            "explore" -> selectRoot(1)
            "search" -> search(target.value)
            "bookmarks" -> open(Feed("Bookmarks",title="书签"))
            "notifications" -> open(Feed("NotificationsTimeline",title="通知"))
            "profile" -> open(Feed("ProfileLink",target.value,"@${target.value}"))
            else -> open(Feed("Browser",url,"网页"))
        }
    }
    companion object {
        val profileFeeds=setOf("UserTweets","UserTweetsAndReplies","UserHighlightsTweets","UserRepostsTimeline","UserPhotoTimeline","UserVideoTimeline","UserArticlesTweets","Likes")
        val apiFeeds=profileFeeds+setOf("HomeTimeline","HomeLatestTimeline","SearchTimeline","TweetDetail","Bookmarks","Followers","Following","Explore","NotificationsTimeline","Article","ProfileLink")
    }
}
internal fun mergePosts(previous:List<Post>,incoming:List<Post>)=(previous+incoming).distinctBy { it.id }.takeLast(300)

