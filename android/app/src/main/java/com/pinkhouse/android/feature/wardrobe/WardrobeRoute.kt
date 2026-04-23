package com.pinkhouse.android.feature.wardrobe

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinkhouse.android.core.di.AppContainer
import com.pinkhouse.android.domain.model.WardrobeItem
import java.math.BigDecimal
import java.math.RoundingMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.foundation.Image as ComposeImage

private val PinkBackground = Color(0xFFF8E2E7)
private val PinkSurface = Color(0xFFFFF8FA)
private val PinkPrimary = Color(0xFFD98AA8)
private val PinkAccent = Color(0xFFFF7BA6)
private val SoftGrayText = Color(0xFF756B70)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WardrobeRoute(appContainer: AppContainer) {
    val factory = remember(appContainer) {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return WardrobeHomeViewModel(
                    wardrobeRepository = appContainer.wardrobeRepositoryForViewModel,
                    batchSoftDeleteWardrobeItems = appContainer.batchSoftDeleteWardrobeItems,
                    userPreferencesDataStore = appContainer.userPreferencesDataStore,
                    wardrobeImageStore = appContainer.wardrobeImageStore,
                ) as T
            }
        }
    }
    val viewModel: WardrobeHomeViewModel = viewModel(factory = factory)
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val coroutineScope = rememberCoroutineScope()

    var showCreateSheet by rememberSaveable { mutableStateOf(false) }
    var showFilterSheet by rememberSaveable { mutableStateOf(false) }
    var showDeleteDialog by rememberSaveable { mutableStateOf(false) }
    var showSortMenu by rememberSaveable { mutableStateOf(false) }
    var showLayoutMenu by rememberSaveable { mutableStateOf(false) }
    var showMoreMenu by rememberSaveable { mutableStateOf(false) }
    var showAddMenu by rememberSaveable { mutableStateOf(false) }

    BackHandler(enabled = uiState.isSelectionMode) {
        viewModel.exitSelectionMode()
    }

    LaunchedEffect(uiState.message) {
        if (uiState.message != null) {
            viewModel.consumeMessage()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PinkBackground),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            WardrobeTopControls(
                uiState = uiState,
                onTabSelected = viewModel::selectHomeTab,
                showSortMenu = showSortMenu,
                onShowSortMenuChange = { showSortMenu = it },
                showLayoutMenu = showLayoutMenu,
                onShowLayoutMenuChange = { showLayoutMenu = it },
                showMoreMenu = showMoreMenu,
                onShowMoreMenuChange = { showMoreMenu = it },
                showAddMenu = showAddMenu,
                onShowAddMenuChange = { showAddMenu = it },
                onSortSelected = viewModel::setSortOption,
                onLayoutSelected = viewModel::setLayoutMode,
                onDepositDisplaySelected = viewModel::setDepositDisplayMode,
                onFilterClick = { showFilterSheet = true },
                onSearchClick = { viewModel.setSearchVisible(true) },
                onEditClick = { viewModel.enterSelectionMode() },
                onAddManualClick = { showCreateSheet = true },
            )

            if (uiState.isSelectionMode) {
                SelectionHeader(
                    uiState = uiState,
                    onDone = viewModel::exitSelectionMode,
                    onToggleAll = {
                        viewModel.toggleSelectAll(uiState.visibleItems.map { it.id })
                    },
                )
            }

            if (uiState.isSearchVisible) {
                SearchField(
                    query = uiState.searchQuery,
                    onQueryChange = viewModel::setSearchQuery,
                    onClose = { viewModel.setSearchVisible(false) },
                )
            }

            if (uiState.homeTab == WardrobeHomeTab.Wardrobe) {
                WardrobeStatisticsCard(statistics = uiState.statistics)
                WardrobeContent(
                    uiState = uiState,
                    viewModel = viewModel,
                    onCreateClick = { showCreateSheet = true },
                    onItemClick = { item ->
                        if (uiState.isSelectionMode) {
                            viewModel.toggleItemSelection(item.id)
                        }
                    },
                )
            } else {
                DepositContent(
                    uiState = uiState,
                    onCreateClick = { showCreateSheet = true },
                )
            }
        }

        if (uiState.isSelectionMode) {
            BatchActionBar(
                selectedCount = uiState.selectedItemIds.size,
                onDelete = { showDeleteDialog = true },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
    }

    if (showCreateSheet) {
        CreateWardrobeItemSheet(
            viewModel = viewModel,
            onDismiss = { showCreateSheet = false },
            onSaved = {
                showCreateSheet = false
            },
        )
    }

    if (showFilterSheet) {
        FilterSheet(
            current = uiState.filterState,
            onDismiss = { showFilterSheet = false },
            onApply = {
                viewModel.setFilterState(it)
                showFilterSheet = false
            },
            onClear = {
                viewModel.clearFilters()
                showFilterSheet = false
            },
        )
    }

    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("移入回收站") },
            text = { Text("确定删除已选的 ${uiState.selectedItemIds.size} 件衣物吗？数据会软删除，后续可接回收站恢复。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteDialog = false
                        viewModel.softDeleteSelected()
                    },
                ) {
                    Text("删除")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("取消")
                }
            },
        )
    }
}

@Composable
private fun WardrobeTopControls(
    uiState: WardrobeHomeUiState,
    onTabSelected: (WardrobeHomeTab) -> Unit,
    showSortMenu: Boolean,
    onShowSortMenuChange: (Boolean) -> Unit,
    showLayoutMenu: Boolean,
    onShowLayoutMenuChange: (Boolean) -> Unit,
    showMoreMenu: Boolean,
    onShowMoreMenuChange: (Boolean) -> Unit,
    showAddMenu: Boolean,
    onShowAddMenuChange: (Boolean) -> Unit,
    onSortSelected: (WardrobeSortOption) -> Unit,
    onLayoutSelected: (WardrobeLayoutMode) -> Unit,
    onDepositDisplaySelected: (DepositDisplayMode) -> Unit,
    onFilterClick: () -> Unit,
    onSearchClick: () -> Unit,
    onEditClick: () -> Unit,
    onAddManualClick: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = Color.White.copy(alpha = 0.72f),
        ) {
            Row(modifier = Modifier.padding(4.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                WardrobeTabButton(
                    label = "少女衣橱",
                    selected = uiState.homeTab == WardrobeHomeTab.Wardrobe,
                    onClick = { onTabSelected(WardrobeHomeTab.Wardrobe) },
                )
                WardrobeTabButton(
                    label = "心愿尾款",
                    selected = uiState.homeTab == WardrobeHomeTab.DepositPlan,
                    onClick = { onTabSelected(WardrobeHomeTab.DepositPlan) },
                )
            }
        }

        Surface(
            shape = RoundedCornerShape(28.dp),
            color = Color.White.copy(alpha = 0.78f),
        ) {
            Row(modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)) {
                ToolbarIconButton(Icons.AutoMirrored.Filled.Sort, "排序") {
                    onShowSortMenuChange(true)
                }
                Box {
                    DropdownMenu(
                        expanded = showSortMenu,
                        onDismissRequest = { onShowSortMenuChange(false) },
                    ) {
                        WardrobeSortOption.entries.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.label) },
                                leadingIcon = {
                                    if (option == uiState.sortOption) {
                                        Icon(Icons.Filled.Check, contentDescription = null)
                                    }
                                },
                                onClick = {
                                    onSortSelected(option)
                                    onShowSortMenuChange(false)
                                },
                            )
                        }
                    }
                }

                ToolbarIconButton(
                    imageVector = Icons.Filled.FilterList,
                    contentDescription = "筛选",
                    badge = uiState.filterState.activeCount.takeIf { it > 0 }?.toString(),
                    onClick = onFilterClick,
                )

                ToolbarIconButton(
                    imageVector = if (uiState.layoutMode.gridColumns == null) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView,
                    contentDescription = "布局",
                ) {
                    onShowLayoutMenuChange(true)
                }
                Box {
                    DropdownMenu(
                        expanded = showLayoutMenu,
                        onDismissRequest = { onShowLayoutMenuChange(false) },
                    ) {
                        if (uiState.homeTab == WardrobeHomeTab.Wardrobe) {
                            WardrobeLayoutMode.entries.forEach { mode ->
                                DropdownMenuItem(
                                    text = { Text(mode.label) },
                                    leadingIcon = {
                                        if (mode == uiState.layoutMode) {
                                            Icon(Icons.Filled.Check, contentDescription = null)
                                        }
                                    },
                                    onClick = {
                                        onLayoutSelected(mode)
                                        onShowLayoutMenuChange(false)
                                    },
                                )
                            }
                        } else {
                            DepositDisplayMode.entries.forEach { mode ->
                                DropdownMenuItem(
                                    text = { Text(mode.label) },
                                    leadingIcon = {
                                        if (mode == uiState.depositDisplayMode) {
                                            Icon(Icons.Filled.Check, contentDescription = null)
                                        }
                                    },
                                    onClick = {
                                        onDepositDisplaySelected(mode)
                                        onShowLayoutMenuChange(false)
                                    },
                                )
                            }
                        }
                    }
                }

                if (uiState.homeTab == WardrobeHomeTab.DepositPlan) {
                    ToolbarIconButton(Icons.Filled.Notifications, "通知") {
                        onSearchClick()
                    }
                }

                ToolbarIconButton(Icons.Filled.MoreVert, "更多") {
                    onShowMoreMenuChange(true)
                }
                Box {
                    DropdownMenu(
                        expanded = showMoreMenu,
                        onDismissRequest = { onShowMoreMenuChange(false) },
                    ) {
                        DropdownMenuItem(
                            text = { Text("搜索") },
                            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                            onClick = {
                                onSearchClick()
                                onShowMoreMenuChange(false)
                            },
                        )
                        if (uiState.homeTab == WardrobeHomeTab.Wardrobe) {
                            DropdownMenuItem(
                                text = { Text("编辑") },
                                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                                onClick = {
                                    onEditClick()
                                    onShowMoreMenuChange(false)
                                },
                            )
                        }
                    }
                }

                ToolbarIconButton(Icons.Filled.Add, "添加") {
                    onShowAddMenuChange(true)
                }
                Box {
                    DropdownMenu(
                        expanded = showAddMenu,
                        onDismissRequest = { onShowAddMenuChange(false) },
                    ) {
                        DropdownMenuItem(
                            text = { Text("手动创建") },
                            leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                            onClick = {
                                onAddManualClick()
                                onShowAddMenuChange(false)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("批量导入") },
                            leadingIcon = { Icon(Icons.Filled.Image, contentDescription = null) },
                            onClick = {
                                onAddManualClick()
                                onShowAddMenuChange(false)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun WardrobeTabButton(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(22.dp),
        color = if (selected) Color.White else Color.Transparent,
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
            text = label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            color = if (selected) PinkPrimary else SoftGrayText.copy(alpha = 0.65f),
        )
    }
}

@Composable
private fun ToolbarIconButton(
    imageVector: ImageVector,
    contentDescription: String,
    badge: String? = null,
    onClick: () -> Unit,
) {
    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(
            modifier = Modifier.size(38.dp),
            onClick = onClick,
        ) {
            Icon(
                imageVector = imageVector,
                contentDescription = contentDescription,
                tint = Color(0xFF4F464B),
            )
        }
        if (badge != null) {
            Surface(
                shape = CircleShape,
                color = PinkAccent,
                modifier = Modifier.size(16.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = badge,
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun SelectionHeader(
    uiState: WardrobeHomeUiState,
    onDone: () -> Unit,
    onToggleAll: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.88f),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onDone) {
                Icon(Icons.Filled.Done, contentDescription = null)
                Spacer(Modifier.width(4.dp))
                Text("完成")
            }
            Text(
                text = "已选 ${uiState.selectedItemIds.size}/${uiState.visibleItems.size}",
                fontWeight = FontWeight.Bold,
            )
            TextButton(onClick = onToggleAll) {
                Text(if (uiState.allVisibleSelected) "取消全选" else "全选")
            }
        }
    }
}

@Composable
private fun SearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    onClose: () -> Unit,
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        trailingIcon = {
            IconButton(onClick = onClose) {
                Icon(Icons.Filled.Close, contentDescription = "关闭搜索")
            }
        },
        placeholder = { Text("搜索名称、品牌、类型、颜色、尺码...") },
        shape = RoundedCornerShape(18.dp),
    )
}

@Composable
private fun WardrobeStatisticsCard(statistics: WardrobeStatistics) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = Color.White.copy(alpha = 0.9f)),
    ) {
        Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                StatColumn("总件数/款", "${statistics.totalPieces}/${statistics.totalStyles}")
                StatColumn("裙装价值", statistics.wardrobeValue.moneyText())
                StatColumn("总价值", statistics.totalValue.moneyText())
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FeaturePill(Icons.Filled.CheckCircle, "今日穿搭色", PinkPrimary)
                FeaturePill(Icons.Filled.Menu, "穿搭手帐", PinkPrimary)
                FeaturePill(Icons.Filled.BarChart, "详细统计", Color(0xFF8D868B))
            }
        }
    }
}

@Composable
private fun StatColumn(title: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = SoftGrayText)
        Text(value, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun RowScope.FeaturePill(icon: ImageVector, label: String, tint: Color) {
    Surface(
        modifier = Modifier.weight(1f),
        shape = RoundedCornerShape(14.dp),
        color = Color(0xFFF6EEF1),
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(icon, contentDescription = null, tint = tint)
            Text(label, style = MaterialTheme.typography.labelMedium, color = tint, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun WardrobeContent(
    uiState: WardrobeHomeUiState,
    viewModel: WardrobeHomeViewModel,
    onCreateClick: () -> Unit,
    onItemClick: (WardrobeItem) -> Unit,
) {
    if (uiState.visibleItems.isEmpty()) {
        EmptyState(
            title = if (uiState.searchQuery.isBlank() && uiState.filterState.activeCount == 0) "衣橱还是空的" else "没有找到匹配衣物",
            description = "添加第一件裙装后，就能开始筛选、排序和记录心愿尾款。",
            onCreateClick = onCreateClick,
        )
        return
    }

    val columns = uiState.layoutMode.gridColumns
    if (columns == null) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = if (uiState.isSelectionMode) 96.dp else 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(uiState.visibleItems, key = { it.id }) { item ->
                WardrobeListRow(
                    item = item,
                    detailed = uiState.layoutMode == WardrobeLayoutMode.ListDetailed,
                    selected = uiState.selectedItemIds.contains(item.id),
                    isSelectionMode = uiState.isSelectionMode,
                    imagePath = item.imagePaths.firstOrNull()?.let(viewModel::imageFilePath),
                    onClick = { onItemClick(item) },
                )
            }
        }
    } else {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = if (uiState.isSelectionMode) 96.dp else 24.dp),
            horizontalArrangement = Arrangement.spacedBy(if (columns >= 6) 4.dp else 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(uiState.visibleItems, key = { it.id }) { item ->
                WardrobeGridCard(
                    item = item,
                    compact = columns >= 3,
                    selected = uiState.selectedItemIds.contains(item.id),
                    isSelectionMode = uiState.isSelectionMode,
                    imagePath = item.imagePaths.firstOrNull()?.let(viewModel::imageFilePath),
                    onClick = { onItemClick(item) },
                )
            }
        }
    }
}

@Composable
private fun DepositContent(
    uiState: WardrobeHomeUiState,
    onCreateClick: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ElevatedCard(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = Color.White.copy(alpha = 0.9f)),
        ) {
            Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    FeaturePill(Icons.Filled.CalendarMonth, "梦裙日历", PinkAccent)
                    FeaturePill(Icons.Filled.BarChart, "马上来财", Color(0xFFFF9B4A))
                    FeaturePill(Icons.Filled.BarChart, "裙装股市", Color(0xFF4BA3FF))
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("总待付尾款", color = SoftGrayText, style = MaterialTheme.typography.titleMedium)
                    Text(
                        uiState.statistics.depositBalance.moneyText(),
                        color = PinkAccent,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        Surface(shape = RoundedCornerShape(18.dp), color = Color.White.copy(alpha = 0.5f)) {
            Row(Modifier.fillMaxWidth().padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                DepositModeButton(
                    label = "按月视图",
                    selected = uiState.depositDisplayMode == DepositDisplayMode.Detail,
                )
                DepositModeButton(
                    label = "按系列视图",
                    selected = uiState.depositDisplayMode == DepositDisplayMode.Simple,
                )
            }
        }

        if (uiState.visibleItems.isEmpty()) {
            EmptyState(
                title = "暂无尾款数据",
                description = "在创建表单中打开「加入心愿尾款」，这里会按月份汇总待付尾款。",
                onCreateClick = onCreateClick,
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Text(
                        text = "最近月统计",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                items(uiState.visibleItems, key = { it.id }) { item ->
                    DepositItemRow(item = item)
                }
            }
        }
    }
}

@Composable
private fun RowScope.DepositModeButton(label: String, selected: Boolean) {
    Surface(
        modifier = Modifier.weight(1f),
        shape = RoundedCornerShape(14.dp),
        color = if (selected) Color.White else Color.Transparent,
    ) {
        Text(
            modifier = Modifier.padding(vertical = 10.dp),
            text = label,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            color = if (selected) Color(0xFF50474D) else SoftGrayText,
        )
    }
}

@Composable
private fun EmptyState(title: String, description: String, onCreateClick: () -> Unit) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = Color.White.copy(alpha = 0.9f)),
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.Image, contentDescription = null, tint = PinkPrimary, modifier = Modifier.size(40.dp))
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(description, style = MaterialTheme.typography.bodyMedium, color = SoftGrayText)
            Button(onClick = onCreateClick) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("添加第一件衣物")
            }
        }
    }
}

@Composable
private fun WardrobeGridCard(
    item: WardrobeItem,
    compact: Boolean,
    selected: Boolean,
    isSelectionMode: Boolean,
    imagePath: String?,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .then(
                if (selected) {
                    Modifier.border(2.dp, PinkAccent, RoundedCornerShape(18.dp))
                } else {
                    Modifier
                },
            ),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = PinkSurface),
    ) {
        Column(modifier = Modifier.padding(if (compact) 6.dp else 8.dp)) {
            Box {
                WardrobeImage(
                    imagePath = imagePath,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1f)
                        .clip(RoundedCornerShape(14.dp)),
                )
                if (item.isDepositPlan) {
                    Text(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(6.dp)
                            .background(Color(0xFF6D4C41).copy(alpha = 0.86f), RoundedCornerShape(8.dp))
                            .padding(horizontal = 6.dp, vertical = 3.dp),
                        text = "心愿尾款",
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
                if (isSelectionMode) {
                    Icon(
                        imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = if (selected) "已选择" else "未选择",
                        tint = if (selected) PinkAccent else Color.White,
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp),
                    )
                }
            }
            if (!compact) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = item.name,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = item.inventoryTotalPrice.moneyText(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF5F545A),
                )
            }
        }
    }
}

@Composable
private fun WardrobeListRow(
    item: WardrobeItem,
    detailed: Boolean,
    selected: Boolean,
    isSelectionMode: Boolean,
    imagePath: String?,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .then(if (selected) Modifier.border(2.dp, PinkAccent, RoundedCornerShape(18.dp)) else Modifier),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = PinkSurface),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box {
                WardrobeImage(
                    imagePath = imagePath,
                    modifier = Modifier
                        .size(if (detailed) 92.dp else 64.dp)
                        .clip(RoundedCornerShape(14.dp)),
                )
                if (isSelectionMode) {
                    Icon(
                        imageVector = if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (selected) PinkAccent else Color.White,
                    )
                }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    listOfNotNull(item.brand, item.category, item.colors.ifBlank { item.color }).joinToString(" · "),
                    color = SoftGrayText,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = if (detailed) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (detailed) {
                    Text(
                        "尺码 ${item.sizes.ifBlank { "-" }} · 状态 ${item.condition}",
                        color = SoftGrayText,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            Text(item.inventoryTotalPrice.moneyText(), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DepositItemRow(item: WardrobeItem) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = PinkSurface),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(item.name, fontWeight = FontWeight.Bold)
                Text(item.totalBalance.moneyText(), color = PinkAccent, fontWeight = FontWeight.Bold)
            }
            Text(
                text = listOfNotNull(
                    item.brand,
                    item.finalPaymentStartDate?.toString()?.let { "开始 $it" },
                    item.finalPaymentEndDate?.toString()?.let { "截止 $it" },
                ).joinToString(" · ").ifBlank { "暂无尾款日期" },
                color = SoftGrayText,
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = {}, label = { Text("定金 ${item.totalDeposit.moneyText()}") })
                AssistChip(onClick = {}, label = { Text("库存 ${item.stock}") })
            }
        }
    }
}

@Composable
private fun WardrobeImage(imagePath: String?, modifier: Modifier) {
    val bitmap by produceState<Bitmap?>(initialValue = null, key1 = imagePath) {
        value = imagePath?.let { path ->
            withContext(Dispatchers.IO) {
                decodeScaledBitmap(path, maxSize = 512)
            }
        }
    }
    if (bitmap != null) {
        ComposeImage(
            bitmap = bitmap!!.asImageBitmap(),
            contentDescription = null,
            modifier = modifier.background(Color.White),
            contentScale = ContentScale.Fit,
        )
    } else {
        Box(
            modifier = modifier.background(
                brush = Brush.verticalGradient(
                    colors = listOf(Color(0xFFF7F2F4), Color(0xFFEFE8EC)),
                ),
            ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Image, contentDescription = null, tint = PinkPrimary.copy(alpha = 0.45f), modifier = Modifier.size(36.dp))
        }
    }
}

@Composable
private fun BatchActionBar(
    selectedCount: Int,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(18.dp),
        shape = RoundedCornerShape(24.dp),
        color = Color.White.copy(alpha = 0.95f),
        tonalElevation = 8.dp,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("已选 $selectedCount 件", fontWeight = FontWeight.Bold)
            Button(
                enabled = selectedCount > 0,
                onClick = onDelete,
            ) {
                Icon(Icons.Filled.Delete, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("批量删除")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateWardrobeItemSheet(
    viewModel: WardrobeHomeViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    var draft by remember { mutableStateOf(WardrobeEditorDraft()) }
    var showNameError by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            coroutineScope.launch {
                val fileName = viewModel.importImage(uri)
                draft = draft.copy(imageFileNames = draft.imageFileNames + fileName)
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 720.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Text("手动创建", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                TextButton(
                    onClick = {
                        showNameError = draft.name.isBlank()
                        if (!showNameError && viewModel.saveDraft(draft)) {
                            onSaved()
                        }
                    },
                ) {
                    Text("保存")
                }
            }

            FormSection(title = "裙装信息") {
                Text("选择图片（最多9张，第一张为主图）", color = SoftGrayText)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    draft.imageFileNames.take(3).forEach { fileName ->
                        WardrobeImage(
                            imagePath = viewModel.imageFilePath(fileName),
                            modifier = Modifier.size(76.dp).clip(RoundedCornerShape(12.dp)),
                        )
                    }
                    OutlinedButton(
                        onClick = {
                            imagePicker.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("添加")
                    }
                }

                DraftTextField("裙装名称 *", draft.name, "请输入裙装名称") {
                    showNameError = false
                    draft = draft.copy(name = it)
                }
                if (showNameError) {
                    Text("裙装名称不能为空", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                DraftTextField("品牌名称", draft.brand, "请输入品牌名称") { draft = draft.copy(brand = it) }
                DraftTextField("类型（逗号分隔，如：JSK,OP,SK,小物）", draft.types, "例如：JSK,OP") { draft = draft.copy(types = it) }
                DraftTextField("颜色（逗号分隔，如：粉色,白色,蓝色）", draft.colors, "例如：粉色,白色") { draft = draft.copy(colors = it) }
                DraftTextField("尺码（逗号分隔，如：S,M,L）", draft.sizes, "例如：S,M,L") { draft = draft.copy(sizes = it) }
                DraftTextField("衣长（如：90cm,100cm）", draft.length, "例如：90cm") { draft = draft.copy(length = it) }
                DraftTextField("状态（如：全新,95新）", draft.condition, "例如：全新") { draft = draft.copy(condition = it) }
                DraftTextField("小物（逗号分隔，如：BNT,发箍KC,发带）", draft.accessories, "例如：BNT,发箍KC") { draft = draft.copy(accessories = it) }
            }

            FormSection(title = "价格信息") {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    DraftTextField("原价", draft.originalPrice, "0", Modifier.weight(1f)) { draft = draft.copy(originalPrice = it) }
                    DraftTextField("裙装总价", draft.price, "0", Modifier.weight(1f)) { draft = draft.copy(price = it) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    DraftTextField("定金", draft.deposit, "0", Modifier.weight(1f)) { draft = draft.copy(deposit = it) }
                    DraftTextField("尾款", draft.balance, "0", Modifier.weight(1f)) { draft = draft.copy(balance = it) }
                }
                DraftTextField("小物总价", draft.accessoriesPrice, "0") { draft = draft.copy(accessoriesPrice = it) }
                DraftTextField("库存数量", draft.stock, "1") { draft = draft.copy(stock = it) }
            }

            FormSection(title = "购买信息") {
                DraftTextField("购买日期", draft.purchaseDate, "YYYY-MM-DD") { draft = draft.copy(purchaseDate = it) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Column {
                        Text("加入心愿尾款", fontWeight = FontWeight.SemiBold)
                        Text("勾选后，该裙装将显示在心愿尾款中", color = SoftGrayText, style = MaterialTheme.typography.bodySmall)
                    }
                    Switch(
                        checked = draft.isDepositPlan,
                        onCheckedChange = { draft = draft.copy(isDepositPlan = it) },
                    )
                }
                if (draft.isDepositPlan) {
                    DraftTextField("定金日期", draft.depositDate, "YYYY-MM-DD") { draft = draft.copy(depositDate = it) }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        DraftTextField("尾款开始", draft.finalPaymentStartDate, "YYYY-MM-DD", Modifier.weight(1f)) {
                            draft = draft.copy(finalPaymentStartDate = it)
                        }
                        DraftTextField("尾款截止", draft.finalPaymentEndDate, "YYYY-MM-DD", Modifier.weight(1f)) {
                            draft = draft.copy(finalPaymentEndDate = it)
                        }
                    }
                }
                DraftTextField("备注", draft.note, "可记录购买渠道、搭配想法等") { draft = draft.copy(note = it) }
            }

            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
private fun FormSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = PinkSurface),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            content()
        }
    }
}

@Composable
private fun DraftTextField(
    label: String,
    value: String,
    placeholder: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onValueChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        label = { Text(label) },
        placeholder = { Text(placeholder) },
        singleLine = label != "备注",
        minLines = if (label == "备注") 3 else 1,
        shape = RoundedCornerShape(14.dp),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterSheet(
    current: WardrobeFilterState,
    onDismiss: () -> Unit,
    onApply: (WardrobeFilterState) -> Unit,
    onClear: () -> Unit,
) {
    var draft by remember(current) { mutableStateOf(current) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("筛选", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                TextButton(onClick = onClear) { Text("清除") }
            }
            DraftTextField("品牌", draft.brand, "例如：Baby") { draft = draft.copy(brand = it) }
            DraftTextField("类型", draft.type, "例如：JSK") { draft = draft.copy(type = it) }
            DraftTextField("颜色", draft.color, "例如：粉色") { draft = draft.copy(color = it) }
            DraftTextField("尺码", draft.size, "例如：M") { draft = draft.copy(size = it) }
            DraftTextField("状态", draft.condition, "例如：全新") { draft = draft.copy(condition = it) }
            DraftTextField("小物", draft.accessory, "例如：BNT") { draft = draft.copy(accessory = it) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilterChip(
                    selected = draft.depositOnly,
                    onClick = { draft = draft.copy(depositOnly = !draft.depositOnly) },
                    label = { Text("只看心愿尾款") },
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("取消") }
                Spacer(Modifier.width(8.dp))
                Button(onClick = { onApply(draft) }) {
                    Text("应用筛选")
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

private fun BigDecimal.moneyText(): String {
    return "¥" + setScale(2, RoundingMode.HALF_UP).toPlainString()
}

private fun decodeScaledBitmap(path: String, maxSize: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply {
        inJustDecodeBounds = true
    }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

    val largestSide = maxOf(bounds.outWidth, bounds.outHeight)
    var sampleSize = 1
    while (largestSide / sampleSize > maxSize) {
        sampleSize *= 2
    }

    val options = BitmapFactory.Options().apply {
        inSampleSize = sampleSize
    }
    return BitmapFactory.decodeFile(path, options)
}
