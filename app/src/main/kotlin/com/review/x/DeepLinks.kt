package com.review.x

import java.net.URI
import java.net.URLDecoder

data class LinkTarget(val kind:String,val value:String="")
object DeepLinks {
    val hosts=setOf("x.com","www.x.com","twitter.com","www.twitter.com","mobile.twitter.com")
    fun parse(raw:String):LinkTarget? = runCatching {
        val uri=URI(raw); val scheme=uri.scheme?.lowercase()
        if(scheme !in listOf("http","https") || uri.host?.lowercase() !in hosts || uri.userInfo!=null || uri.port !in listOf(-1,if(scheme=="https")443 else 80)) return null
        val path=uri.path.split('/').filter { it.isNotEmpty() }
        for(i in 0 until path.size-1) if(path[i].lowercase() in listOf("status","statuses") && path[i+1].matches(Regex("\\d{1,30}"))) return LinkTarget("post",path[i+1])
        val lower=path.map(String::lowercase)
        when {
            path.isEmpty() || lower.first()=="home" -> LinkTarget("home")
            lower.first()=="explore" -> LinkTarget("explore")
            lower.first()=="notifications" || lower.take(2)==listOf("i","notifications") -> LinkTarget("notifications")
            lower.take(2)==listOf("i","bookmarks") -> LinkTarget("bookmarks")
            lower.first()=="search" -> LinkTarget("search",uri.rawQuery.orEmpty().split('&').firstOrNull { it.substringBefore('=')=="q" }?.substringAfter('=')?.let { URLDecoder.decode(it,"UTF-8") }.orEmpty())
            path.size==1 && path[0].matches(Regex("[A-Za-z0-9_]{1,15}")) -> LinkTarget("profile",path[0])
            else -> LinkTarget("other",raw)
        }
    }.getOrNull()
}
