package com.pinkhouse.android.feature.wardrobe

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import com.pinkhouse.android.domain.usecase.AddSampleWardrobeItems
import com.pinkhouse.android.domain.usecase.GetWardrobeItems
import java.text.NumberFormat
import kotlinx.coroutines.launch

@Composable
fun WardrobeRoute(
    getWardrobeItems: GetWardrobeItems,
    addSampleWardrobeItems: AddSampleWardrobeItems,
) {
    var searchQuery by rememberSaveable { androidx.compose.runtime.mutableStateOf("") }
    val itemFlow = remember(searchQuery) { getWardrobeItems(searchQuery) }
    val items by itemFlow.collectAsStateWithLifecycle(initialValue = emptyList())
    val coroutineScope = rememberCoroutineScope()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        WardrobeHeader(itemCount = items.size)
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("按名称搜索") },
            placeholder = { Text("例如：开衫、半身裙") },
            singleLine = true,
            trailingIcon = {
                if (searchQuery.isNotBlank()) {
                    TextButton(onClick = { searchQuery = "" }) {
                        Text("清除")
                    }
                }
            },
        )

        if (items.isEmpty()) {
            WardrobeEmptyState(
                hasSearchQuery = searchQuery.isNotBlank(),
                onAddSampleItems = {
                    coroutineScope.launch {
                        addSampleWardrobeItems()
                    }
                },
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Button(
                        onClick = {
                            coroutineScope.launch {
                                addSampleWardrobeItems()
                            }
                        },
                    ) {
                        Text("添加示例衣物")
                    }
                }
                items(
                    items = items,
                    key = { it.id },
                ) { item ->
                    WardrobeItemCard(item = item)
                }
            }
        }
    }
}

@Composable
private fun WardrobeHeader(itemCount: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = "我的衣橱",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = "本地 Room 数据驱动，当前展示 $itemCount 件未删除衣物",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun WardrobeEmptyState(
    hasSearchQuery: Boolean,
    onAddSampleItems: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.Start,
        ) {
            Text(
                text = if (hasSearchQuery) "没有找到匹配衣物" else "衣橱还是空的",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = if (hasSearchQuery) {
                    "换个关键词试试，当前 MVP 先支持按名称模糊搜索。"
                } else {
                    "先添加几件示例衣物，验证列表、搜索和 Room 持久化链路。"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!hasSearchQuery) {
                Button(onClick = onAddSampleItems) {
                    Text("添加示例数据")
                }
            }
        }
    }
}

@Composable
private fun WardrobeItemCard(item: WardrobeItem) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
        ),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = item.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = listOfNotNull(item.category, item.brand, item.color).joinToString(" · "),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    text = item.status.displayName(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }

            Spacer(modifier = Modifier.height(2.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = item.price?.let { NumberFormat.getCurrencyInstance().format(it) } ?: "未记录价格",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = item.purchaseDate?.toString() ?: "未记录购买日期",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun WardrobeItemStatus.displayName(): String {
    return when (this) {
        WardrobeItemStatus.Reserved -> "想买"
        WardrobeItemStatus.Owned -> "拥有"
        WardrobeItemStatus.Sold -> "已出"
        WardrobeItemStatus.Trashed -> "已删除"
    }
}
