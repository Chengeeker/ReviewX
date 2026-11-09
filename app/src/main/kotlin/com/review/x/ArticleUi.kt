package com.review.x

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.*
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.*

@Composable fun ArticleScreen(state:ReaderState,model:ReaderViewModel) {
    val screen=state.screen;val post=screen.posts.firstOrNull() ?: screen.selectedPost;val article=post?.article;val actions=LocalActions.current;val context=LocalContext.current;val reading=LocalReading.current
    LazyColumn(contentPadding=PaddingValues(20.dp)) {
        if (screen.busy || screen.error != null) item { RequestStatus(screen.busy, screen.error, model::load) }
        if (article == null || post == null) {
            if (screen.loaded && screen.error == null) item { Text("文章暂不可用") }
            return@LazyColumn
        }
        item{Text(article.title,Modifier.flutterLineHeight(MaterialTheme.typography.headlineMedium.lineHeight),style=MaterialTheme.typography.headlineMedium);Spacer(Modifier.height(12.dp));Text("${post.author.name} · @${post.author.handle}");Spacer(Modifier.height(16.dp))}
        article.cover?.let {cover->item{ArticleMedia(listOf(cover),post.author.handle)}}
        if(article.blocks.isEmpty())item{if(!screen.busy){Text("X 本次只返回文章摘要，完整内容请打开原文。");Spacer(Modifier.height(12.dp))};SelectionContainer{Text(article.preview)};FlutterTextButton(onClick={NativeServices.open(context,post.url)}){Text("在 X 阅读完整文章")}}
        var number=0
        article.blocks.forEach {block->if(block.type=="ordered-list-item")number++ else number=0;val label=number
            item {
                if(block.type=="atomic") {if(block.media.isEmpty())FlutterTextButton(onClick={NativeServices.open(context,post.url)}){Text("此嵌入内容请在 X 查看")}else {ArticleMedia(block.media,post.author.handle);if(block.caption.isNotBlank())Text(block.caption)}}
                else {
                    val heading=listOf("header-one","header-two","header-three","header-four","header-five","header-six").indexOf(block.type)
                    val font=if(heading>=0)(28-heading*2).toFloat() else reading.optDouble("fontSize",16.0).toFloat()
                    val linkStyle=if(reading.optBoolean("coloredLinks",true))SpanStyle(color=MaterialTheme.colorScheme.primary)else SpanStyle()
                    val codeBackground=MaterialTheme.colorScheme.surfaceContainerHighest
                    val annotated=buildAnnotatedString {
                        append(block.text)
                        block.styles.forEach {range->val start=range.offset.coerceIn(0,length);val end=(range.offset+range.length).coerceIn(start,length);val style=when(range.value){"BOLD"->SpanStyle(fontWeight=FontWeight.Bold);"ITALIC"->SpanStyle(fontStyle=FontStyle.Italic);"UNDERLINE"->SpanStyle(textDecoration=TextDecoration.Underline);"STRIKETHROUGH"->SpanStyle(textDecoration=TextDecoration.LineThrough);"CODE"->SpanStyle(fontFamily=FontFamily.Monospace,background=codeBackground);else->SpanStyle()};addStyle(style,start,end)}
                        block.links.ifEmpty {textLinks(block.text)}.forEach {range->val start=range.offset.coerceIn(0,length);val end=(range.offset+range.length).coerceIn(start,length);if(end>start)addLink(LinkAnnotation.Clickable(range.value,TextLinkStyles(linkStyle)){actions.link(textLinkUrl(range.value))},start,end)}
                    }
                    Row(Modifier.padding(vertical=8.dp)) {if(block.type=="unordered-list-item")Text("•  ");if(block.type=="ordered-list-item")Text("$label.  ");if(block.type=="blockquote"){Box(Modifier.width(3.dp).height(24.dp).background(MaterialTheme.colorScheme.primary));Spacer(Modifier.width(12.dp))};SelectionContainer(Modifier.weight(1f)) {Text(annotated,fontSize=font.sp,lineHeight=(font*reading.optDouble("lineHeight",1.5)).toFloat().sp,fontWeight=if(heading>=0)FontWeight.Bold else null,fontStyle=if(block.type=="blockquote")FontStyle.Italic else null)}}
                }
            }
        }
    }
}
@Composable fun ArticleMedia(media:List<Media>,author:String) {
    val actions=LocalActions.current;val bounds=remember(media){mutableMapOf<Int,androidx.compose.ui.layout.LayoutCoordinates>()}
    val galleryScope=remember{Any()}
    val previews = remember(media) { mutableMapOf<Int, androidx.compose.ui.graphics.ImageBitmap>() }
    Column {media.forEachIndexed {index,item->
        var sourceImage by remember(item.url){mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null)}
        Box(Modifier.padding(vertical=8.dp).fillMaxWidth().onGloballyPositioned {bounds[index]=it}.hideGallerySource(galleryScope,index).hapticClickable {actions.gallery(GalleryRequest(media,index,author,sourceAnchor=if(item.video)null else {i->bounds[i]?.galleryAnchor()},sourceCovers=false,sourceScope=galleryScope,sourceImage=sourceImage,previewImage={previews[it]}))}) {
            NetworkImage(item.url,item.description,Modifier.fillMaxWidth().then(if(item.width>0&&item.height>0)Modifier.aspectRatio(item.width.toFloat()/item.height)else Modifier).clip(RoundedCornerShape(16.dp)),scale=ContentScale.Fit,onImageReady={sourceImage=it;previews[index]=it})
            if(item.video)Glyph("play_circle",size=48,color=Color.White,modifier=Modifier.align(Alignment.Center))
        }
    }}
}
