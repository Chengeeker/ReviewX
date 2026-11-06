package com.review.x

private const val hashtagChars="\\p{L}\\p{M}\\p{N}_\\u200c\\u200d\\ua67e\\u05be\\u05f3\\u05f4\\uff5e\\u301c\\u309b\\u309c\\u30a0\\u30fb\\u3003\\u0f0b\\u0f0c\\u00b7"
private val hashtagPattern=Regex("(^|[^&$hashtagChars])([#＃])(?![\\uFE0F\\u20E3])([$hashtagChars]*[\\p{L}\\p{M}][$hashtagChars]*)")
private val basicLinkPattern=Regex("https?://[^\\s<>]+|@[A-Za-z0-9_]{1,15}|\\$[A-Za-z]{1,12}")

internal fun textLinks(text:String):List<TextRange> {
    val links=basicLinkPattern.findAll(text).map {TextRange(it.range.first,it.value.length,it.value)}.toMutableList()
    hashtagPattern.findAll(text).forEach {match->
        val start=match.range.first+match.groupValues[1].length
        if(links.none {start>=it.offset&&start<it.offset+it.length}) {
            val tag=match.groupValues[2]+match.groupValues[3]
            links.add(TextRange(start,tag.length,tag))
        }
    }
    return links.sortedBy {it.offset}
}
internal fun textLinkUrl(value:String)=when {
    value.startsWith("@") -> "https://x.com/"+value.drop(1)
    value.startsWith("#")||value.startsWith("＃")||value.startsWith("$") -> "https://x.com/search?q="+java.net.URLEncoder.encode(value,"UTF-8")
    else -> value
}
