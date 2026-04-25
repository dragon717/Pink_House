package com.pinkhouse.android.feature.pet

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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.LocalDining
import androidx.compose.material.icons.filled.Paid
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pinkhouse.android.core.assets.PinkHouseAssets
import com.pinkhouse.android.core.ui.PinkHouseDesignTokens

private data class PetMessage(
    val text: String,
    val fromUser: Boolean,
)

@Composable
fun PetRoute(
    onBackToWardrobe: () -> Unit,
) {
    var selectedPetIndex by rememberSaveable { mutableIntStateOf(0) }
    var hunger by rememberSaveable { mutableIntStateOf(62) }
    var cleanliness by rememberSaveable { mutableIntStateOf(74) }
    var coins by rememberSaveable { mutableIntStateOf(120) }
    var input by rememberSaveable { mutableStateOf("") }
    val petName = if (selectedPetIndex == 0) "奶茶" else "毛毛"
    val petImage = if (selectedPetIndex == 0) PinkHouseAssets.naichaPortrait else PinkHouseAssets.maomaoPortrait
    val messages = remember {
        mutableStateListOf(
            PetMessage("欢迎回来呀，今天想看衣橱、尾款，还是让我陪你聊聊穿搭？", fromUser = false),
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(PinkHouseDesignTokens.Background, Color(0xFFFFF8FA)),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                IconButton(onClick = onBackToWardrobe) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回衣橱")
                }
                Text("萌宠对话", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Surface(shape = CircleShape, color = Color.White.copy(alpha = 0.86f)) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Paid, contentDescription = null, tint = PinkHouseDesignTokens.WarmAccent)
                        Text(" $coins", fontWeight = FontWeight.Bold)
                    }
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(26.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.88f)),
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Image(
                        painter = painterResource(petImage),
                        contentDescription = petName,
                        modifier = Modifier.size(108.dp),
                        contentScale = ContentScale.Fit,
                    )
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(petName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text("本地规则式陪伴模式", color = PinkHouseDesignTokens.TextSecondary)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(onClick = {}, label = { Text("饱腹 $hunger") })
                            AssistChip(onClick = {}, label = { Text("清洁 $cleanliness") })
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(
                                onClick = { selectedPetIndex = 0 },
                                label = { Text("奶茶") },
                            )
                            AssistChip(
                                onClick = { selectedPetIndex = 1 },
                                label = { Text("毛毛") },
                            )
                        }
                    }
                }
            }

            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(messages) { message ->
                    PetBubble(message)
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    modifier = Modifier.weight(1f),
                    onClick = {
                        hunger = (hunger + 12).coerceAtMost(100)
                        coins = (coins - 5).coerceAtLeast(0)
                        messages += PetMessage("$petName 吃饱了一点，开始认真听你讲今天的裙子。", false)
                    },
                ) {
                    Icon(Icons.Filled.LocalDining, contentDescription = null)
                    Text("喂食")
                }
                Button(
                    modifier = Modifier.weight(1f),
                    onClick = {
                        cleanliness = 100
                        messages += PetMessage("$petName 已经清清爽爽，适合开启新一轮穿搭分析。", false)
                    },
                ) {
                    Icon(Icons.Filled.CleaningServices, contentDescription = null)
                    Text("清洁")
                }
                Button(
                    modifier = Modifier.weight(1f),
                    onClick = {
                        coins += 20
                        messages += PetMessage("$petName 去打工带回 20 个喵币。", false)
                    },
                ) {
                    Icon(Icons.Filled.Pets, contentDescription = null)
                    Text("打工")
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    placeholder = { Text("问穿搭、尾款、衣橱状态...") },
                    shape = RoundedCornerShape(18.dp),
                )
                Button(
                    enabled = input.isNotBlank(),
                    onClick = {
                        val question = input.trim()
                        messages += PetMessage(question, true)
                        messages += PetMessage(ruleReply(question, petName), false)
                        input = ""
                    },
                ) {
                    Text("发送")
                }
            }
            Spacer(Modifier.height(6.dp))
        }
    }
}

@Composable
private fun PetBubble(message: PetMessage) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (message.fromUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(0.82f),
            shape = RoundedCornerShape(
                topStart = 20.dp,
                topEnd = 20.dp,
                bottomStart = if (message.fromUser) 20.dp else 4.dp,
                bottomEnd = if (message.fromUser) 4.dp else 20.dp,
            ),
            color = if (message.fromUser) PinkHouseDesignTokens.Primary else Color.White.copy(alpha = 0.9f),
        ) {
            Text(
                modifier = Modifier.padding(14.dp),
                text = message.text,
                color = if (message.fromUser) Color.White else PinkHouseDesignTokens.TextPrimary,
            )
        }
    }
}

private fun ruleReply(question: String, petName: String): String {
    val normalized = question.lowercase()
    return when {
        "尾款" in normalized || "定金" in normalized -> "$petName 建议先看心愿尾款页的月份统计，把最近截止的尾款排在前面。"
        "穿搭" in normalized || "ootd" in normalized -> "$petName 会优先找同色系、同标签和最近没穿过的裙子做搭配。"
        "衣橱" in normalized || "裙" in normalized -> "$petName 可以帮你从衣橱里按品牌、颜色、尺码和价格范围筛选。"
        "喵币" in normalized || "钱" in normalized -> "$petName 觉得今天可以去 House 的来财入口看看储蓄状态。"
        else -> "$petName 记下啦。等 AI 能力接入前，我会先用本地规则陪你整理衣橱。"
    }
}
