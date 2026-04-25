package com.pinkhouse.android.feature.petchat

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens
import com.pinkhouse.android.core.ui.theme.PinkHouseTheme
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class ChatRole { Welcome, User, Pet }

private data class ChatMessage(
    val id: Long,
    val role: ChatRole,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
)

private data class IntentChip(val label: String, val title: String)

private val intentChips = listOf(
    IntentChip("A", "帮我搭一套"),
    IntentChip("B", "看天气穿搭"),
    IntentChip("C", "帮我找裙子"),
)

private val fallbackPetReplies = listOf(
    "听不懂呢…主人在说什么呀?",
    "咦?这个词好像没听过耶~",
    "(歪头) 主人再说一遍?",
    "(摇尾巴) 我好像听不太明白…",
    "喵呜…能换个说法吗?",
    "主人想跟我说什么呀?",
    "嗯嗯，毛毛在听呢~",
    "(竖耳朵) 没听懂诶…",
    "再说一次嘛 主人~",
    "毛毛的小脑袋瓜转不过来啦~",
)

private const val WELCOME_TEXT = "午后时光慢，岁月静好处。喵~ 我是你的衣橱管家，有什么可以帮你的吗?\n你想先聊哪一类呢?"

@Composable
fun PetChatRoute(
    modifier: Modifier = Modifier,
    petName: String = "毛毛",
    onNavigateBack: () -> Unit = {},
) {
    val messages = remember { mutableStateListOf<ChatMessage>() }
    var inputText by rememberSaveable { mutableStateOf("") }
    var nextId by rememberSaveable { mutableStateOf(1L) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current

    LaunchedEffect(Unit) {
        if (messages.isEmpty()) {
            messages.add(ChatMessage(id = 0L, role = ChatRole.Welcome, text = WELCOME_TEXT))
        }
    }

    fun appendUserAndReply(userText: String) {
        if (userText.isBlank()) return
        messages.add(ChatMessage(id = nextId++, role = ChatRole.User, text = userText.trim()))
        messages.add(
            ChatMessage(id = nextId++, role = ChatRole.Pet, text = fallbackPetReplies.random()),
        )
        scope.launch { listState.animateScrollToItem(messages.lastIndex) }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(PinkHouseDesignTokens.Background, PinkHouseDesignTokens.Surface),
                ),
            ),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            PetChatTopBar(
                petName = petName,
                onBack = onNavigateBack,
                modifier = Modifier.statusBarsPadding(),
            )

            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentPadding = PaddingValues(
                    horizontal = PinkHouseDesignTokens.PageHorizontalPadding,
                    vertical = 12.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(items = messages, key = { it.id }) { msg ->
                    when (msg.role) {
                        ChatRole.Welcome -> WelcomeBubble(
                            text = msg.text,
                            timestamp = msg.timestamp,
                            onIntent = { chip -> appendUserAndReply(chip.title) },
                        )
                        ChatRole.User -> UserBubble(text = msg.text)
                        ChatRole.Pet -> PetBubble(text = msg.text)
                    }
                }
            }

            ChatInputBar(
                text = inputText,
                onTextChange = { inputText = it },
                onSend = {
                    appendUserAndReply(inputText)
                    inputText = ""
                    keyboard?.hide()
                },
                modifier = Modifier
                    .imePadding()
                    .navigationBarsPadding(),
            )
        }
    }
}

@Composable
private fun PetChatTopBar(
    petName: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 6.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "返回",
                tint = PinkHouseDesignTokens.TextPrimary,
            )
        }
        Spacer(Modifier.weight(1f))
        Text(
            text = "${petName}的悄悄话",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = PinkHouseDesignTokens.TextPrimary,
        )
        Spacer(Modifier.weight(1f))
        IconButton(onClick = { /* TODO(petchat-history): 历史搜索 */ }) {
            Icon(
                imageVector = Icons.Default.Search,
                contentDescription = "历史搜索",
                tint = PinkHouseDesignTokens.TextSecondary,
            )
        }
    }
}

@Composable
private fun WelcomeBubble(
    text: String,
    timestamp: Long,
    onIntent: (IntentChip) -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // TODO(asset): 替换为多姿态萌宠聊天立绘 webp，本批复用 maomaoPortrait 占位
        Image(
            painter = painterResource(PinkHouseAssets.maomaoPortrait),
            contentDescription = "毛毛立绘",
            modifier = Modifier.size(120.dp),
        )

        Surface(
            shape = RoundedCornerShape(PinkHouseDesignTokens.LargeCardRadius),
            color = PinkHouseDesignTokens.SurfaceStrong,
            shadowElevation = 2.dp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodyLarge,
                    color = PinkHouseDesignTokens.TextPrimary,
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    intentChips.forEach { chip ->
                        IntentChipButton(
                            chip = chip,
                            onClick = { onIntent(chip) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                Text(
                    text = formatTime(timestamp),
                    style = MaterialTheme.typography.labelSmall,
                    color = PinkHouseDesignTokens.TextMuted,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.End,
                )
            }
        }
    }
}

@Composable
private fun IntentChipButton(
    chip: IntentChip,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        color = PinkHouseDesignTokens.Background,
        onClick = onClick,
    ) {
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = PinkHouseDesignTokens.Accent, fontWeight = FontWeight.SemiBold)) {
                    append("${chip.label}. ")
                }
                append(chip.title)
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = PinkHouseDesignTokens.TextPrimary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun UserBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
        Surface(
            shape = RoundedCornerShape(
                topStart = PinkHouseDesignTokens.LargeCardRadius,
                topEnd = PinkHouseDesignTokens.LargeCardRadius,
                bottomStart = PinkHouseDesignTokens.LargeCardRadius,
                bottomEnd = 4.dp,
            ),
            color = PinkHouseDesignTokens.Accent,
            modifier = Modifier.padding(start = 48.dp),
        ) {
            Text(
                text = text,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White,
            )
        }
    }
}

@Composable
private fun PetBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(
                topStart = PinkHouseDesignTokens.LargeCardRadius,
                topEnd = PinkHouseDesignTokens.LargeCardRadius,
                bottomStart = 4.dp,
                bottomEnd = PinkHouseDesignTokens.LargeCardRadius,
            ),
            color = PinkHouseDesignTokens.SurfaceStrong,
            shadowElevation = 1.dp,
            modifier = Modifier.padding(end = 48.dp),
        ) {
            Text(
                text = text,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = PinkHouseDesignTokens.TextPrimary,
            )
        }
    }
}

@Composable
private fun ChatInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        shape = RoundedCornerShape(28.dp),
        color = PinkHouseDesignTokens.SurfaceStrong,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Surface(
                modifier = Modifier.size(40.dp),
                shape = CircleShape,
                color = PinkHouseDesignTokens.Background,
                onClick = { /* TODO(petchat-menu): 拓展菜单 */ },
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "拓展功能",
                        tint = PinkHouseDesignTokens.Accent,
                    )
                }
            }

            TextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        text = "和毛毛对话…",
                        color = PinkHouseDesignTokens.TextMuted,
                    )
                },
                singleLine = true,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    disabledContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { onSend() }),
            )

            val sendEnabled = text.isNotBlank()
            Surface(
                modifier = Modifier.size(40.dp),
                shape = CircleShape,
                color = if (sendEnabled) PinkHouseDesignTokens.Accent else PinkHouseDesignTokens.Background,
                onClick = { if (sendEnabled) onSend() },
                enabled = sendEnabled,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Send,
                        contentDescription = "发送",
                        tint = if (sendEnabled) Color.White else PinkHouseDesignTokens.TextMuted,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

private fun formatTime(timestamp: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(timestamp))

@Preview(showBackground = true, widthDp = 393, heightDp = 852)
@Composable
private fun PetChatRoutePreview() {
    PinkHouseTheme {
        PetChatRoute()
    }
}
