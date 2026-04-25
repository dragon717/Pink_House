package com.pinkhouse.android.feature.wardrobe

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Save
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
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.pinkhouse.android.core.di.AppContainer
import com.pinkhouse.android.core.ui.PinkFullHeightSheet
import com.pinkhouse.android.core.ui.PinkSheetHeader
import com.pinkhouse.android.domain.model.WardrobeItem
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.foundation.Image as ComposeImage

private val PinkBackground = Color(0xFFF8E2E7)
private val PinkSurface = Color(0xFFFFF8FA)
private val PinkPrimary = Color(0xFFD98AA8)
private val PinkAccent = Color(0xFFFF7BA6)
private val SoftGrayText = Color(0xFF756B70)

@Composable
fun WardrobeRoute(
    appContainer: AppContainer,
    requestedHomeTab: WardrobeHomeTab? = null,
    onRequestedHomeTabConsumed: () -> Unit = {},
) {
    val factory = remember(appContainer) {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return WardrobeHomeViewModel(
                    wardrobeRepository = appContainer.wardrobeRepositoryForViewModel,
                    batchSoftDeleteWardrobeItems = appContainer.batchSoftDeleteWardrobeItems,
                    userPreferencesDataStore = appContainer.userPreferencesDataStore,
                    wardrobeImageStore = appContainer.wardrobeImageStore,
                    wardrobeTestMediaManager = appContainer.wardrobeTestMediaManager,
                    depositReminderScheduler = appContainer.depositReminderScheduler,
                ) as T
            }
        }
    }
    val viewModel: WardrobeHomeViewModel = viewModel(factory = factory)
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val coroutineScope = rememberCoroutineScope()

    var showCreateSheet by rememberSaveable { mutableStateOf(false) }
    var showFilterSheet by rememberSaveable { mutableStateOf(false) }
    var showRecycleBinSheet by rememberSaveable { mutableStateOf(false) }
    var showDepositReminderSheet by rememberSaveable { mutableStateOf(false) }
    var showBatchImportSheet by rememberSaveable { mutableStateOf(false) }
    var showStatisticsSheet by rememberSaveable { mutableStateOf(false) }
    var showDeleteDialog by rememberSaveable { mutableStateOf(false) }
    var pendingHardDeleteIds by rememberSaveable { mutableStateOf<List<Long>>(emptyList()) }
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

    LaunchedEffect(requestedHomeTab) {
        if (requestedHomeTab != null) {
            viewModel.selectHomeTab(requestedHomeTab)
            onRequestedHomeTabConsumed()
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
                onRecycleBinClick = { showRecycleBinSheet = true },
                onDepositReminderClick = { showDepositReminderSheet = true },
                onAddManualClick = { showCreateSheet = true },
                onBatchImportClick = { showBatchImportSheet = true },
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
                    filterState = uiState.filterState,
                    recentSearches = uiState.recentSearches,
                    shortcuts = remember(uiState.allItems) { WardrobeBusinessLogic.queryShortcuts(uiState.allItems) },
                    onQueryChange = viewModel::setSearchQuery,
                    onSearchSubmitted = viewModel::submitSearchQuery,
                    onShortcutSelected = { shortcut -> viewModel.submitSearchQuery(shortcut.query) },
                    onRecentSelected = viewModel::submitSearchQuery,
                    onClose = { viewModel.setSearchVisible(false) },
                )
            }

            if (uiState.homeTab == WardrobeHomeTab.Wardrobe) {
                WardrobeStatisticsCard(
                    uiState = uiState,
                    onStatisticsClick = { showStatisticsSheet = true },
                )
                WardrobeContent(
                    uiState = uiState,
                    viewModel = viewModel,
                    onCreateClick = { showCreateSheet = true },
                    onItemClick = { item ->
                        if (uiState.isSelectionMode) {
                            viewModel.toggleItemSelection(item.id)
                        } else {
                            viewModel.selectItem(item.id)
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
        WardrobeItemEditorSheet(
            viewModel = viewModel,
            existing = null,
            onDismiss = { showCreateSheet = false },
            onSaved = {
                showCreateSheet = false
            },
        )
    }

    uiState.selectedItem?.let { item ->
        WardrobeItemDetailSheet(
            item = item,
            viewModel = viewModel,
            onDismiss = { viewModel.selectItem(null) },
            onSoftDelete = { viewModel.softDeleteItem(item.id) },
        )
    }

    if (showFilterSheet) {
        FilterSheet(
            uiState = uiState,
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

    if (showBatchImportSheet) {
        BatchImportSheet(
            viewModel = viewModel,
            onDismiss = { showBatchImportSheet = false },
        )
    }

    if (showRecycleBinSheet) {
        RecycleBinSheet(
            items = uiState.trashedItems,
            onDismiss = { showRecycleBinSheet = false },
            onRestore = viewModel::restoreItems,
            onHardDelete = { ids -> pendingHardDeleteIds = ids },
        )
    }

    if (showDepositReminderSheet) {
        DepositReminderSheet(
            uiState = uiState,
            onDismiss = { showDepositReminderSheet = false },
            onSave = viewModel::saveReminderSettings,
        )
    }

    if (showStatisticsSheet) {
        WardrobeDetailedStatisticsSheet(
            uiState = uiState,
            onDismiss = { showStatisticsSheet = false },
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

    if (pendingHardDeleteIds.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = { pendingHardDeleteIds = emptyList() },
            title = { Text("彻底删除") },
            text = { Text("确定彻底删除 ${pendingHardDeleteIds.size} 件衣物吗？此操作不会进入回收站。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.permanentlyDeleteItems(pendingHardDeleteIds)
                        pendingHardDeleteIds = emptyList()
                    },
                ) {
                    Text("彻底删除")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingHardDeleteIds = emptyList() }) {
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
    onRecycleBinClick: () -> Unit,
    onDepositReminderClick: () -> Unit,
    onAddManualClick: () -> Unit,
    onBatchImportClick: () -> Unit,
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
                        onDepositReminderClick()
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
                        DropdownMenuItem(
                            text = { Text("回收站") },
                            leadingIcon = { Icon(Icons.Filled.Restore, contentDescription = null) },
                            onClick = {
                                onRecycleBinClick()
                                onShowMoreMenuChange(false)
                            },
                        )
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
                                onBatchImportClick()
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
    filterState: WardrobeFilterState,
    recentSearches: List<String>,
    shortcuts: List<WardrobeQueryShortcut>,
    onQueryChange: (String) -> Unit,
    onSearchSubmitted: (String) -> Unit,
    onShortcutSelected: (WardrobeQueryShortcut) -> Unit,
    onRecentSelected: (String) -> Unit,
    onClose: () -> Unit,
) {
    SoftGlassPanel {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SoftSearchInput(
                query = query,
                onQueryChange = onQueryChange,
                onSearchSubmitted = onSearchSubmitted,
                onClose = onClose,
            )
            Text(
                text = "查询小抄：字段:关键词、无品牌/无标签/无小物、尾款、价格区间 100-300。",
                style = MaterialTheme.typography.labelSmall,
                color = SoftGrayText,
            )
            if (recentSearches.isNotEmpty()) {
                SearchPillRow(title = "最近搜索") {
                    items(recentSearches, key = { "recent-$it" }) { recent ->
                        SoftSearchPill(label = recent, selected = recent == query, onClick = { onRecentSelected(recent) })
                    }
                }
            }
            SearchPillRow(title = "快捷查询") {
                items(shortcuts, key = { it.query }) { shortcut ->
                    SoftSearchPill(
                        label = shortcut.label,
                        selected = shortcut.query == query,
                        onClick = { onShortcutSelected(shortcut) },
                    )
                }
            }
            if (filterState.activeCount > 0) {
                Text(
                    text = "已叠加 ${filterState.activeCount} 项筛选；统计卡会按搜索 + 筛选共同更新。",
                    style = MaterialTheme.typography.labelMedium,
                    color = PinkPrimary,
                )
            }
        }
    }
}

@Composable
private fun SoftGlassPanel(content: @Composable () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, Color.White.copy(alpha = 0.72f), RoundedCornerShape(30.dp)),
        shape = RoundedCornerShape(30.dp),
        color = Color.White.copy(alpha = 0.68f),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
        content = content,
    )
}

@Composable
private fun SoftSearchInput(
    query: String,
    onQueryChange: (String) -> Unit,
    onSearchSubmitted: (String) -> Unit,
    onClose: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.76f), RoundedCornerShape(28.dp))
            .border(1.dp, Color.White.copy(alpha = 0.92f), RoundedCornerShape(28.dp))
            .padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, tint = SoftGrayText)
        BasicTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.weight(1f),
            singleLine = true,
            textStyle = MaterialTheme.typography.titleMedium.copy(color = SoftGrayText),
            cursorBrush = SolidColor(PinkAccent),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onSearchSubmitted(query) }),
            decorationBox = { innerTextField ->
                if (query.isBlank()) {
                    Text(
                        text = "搜索名称、品牌、标签、类型、颜色...",
                        color = SoftGrayText.copy(alpha = 0.72f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                innerTextField()
            },
        )
        Surface(
            modifier = Modifier
                .size(42.dp)
                .clickable(onClick = onClose),
            shape = CircleShape,
            color = PinkBackground.copy(alpha = 0.72f),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, contentDescription = "关闭搜索", tint = SoftGrayText)
            }
        }
    }
}

@Composable
private fun SearchPillRow(
    title: String,
    content: LazyListScope.() -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = PinkPrimary, fontWeight = FontWeight.SemiBold)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
private fun SoftSearchPill(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    Surface(
        modifier = Modifier
            .clip(shape)
            .clickable(onClick = onClick),
        shape = shape,
        color = if (selected) PinkPrimary.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.58f),
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            if (selected) PinkPrimary.copy(alpha = 0.46f) else Color.White.copy(alpha = 0.86f),
        ),
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp),
            text = label,
            color = if (selected) PinkPrimary else SoftGrayText,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun WardrobeStatisticsCard(
    uiState: WardrobeHomeUiState,
    onStatisticsClick: () -> Unit,
) {
    val statistics = if (uiState.hasActiveQuery) uiState.visibleStatistics else uiState.statistics
    SoftGlassPanel {
        Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = if (uiState.hasActiveQuery) "当前结果统计" else "衣橱总览",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = PinkPrimary,
                    )
                    Text(
                        text = if (uiState.hasActiveQuery) {
                            "命中 ${uiState.visibleItems.size}/${uiState.allItems.size} 款 · 筛选 ${uiState.filterState.activeCount} 项"
                        } else {
                            "全量数据 · 搜索和筛选后会联动更新"
                        },
                        style = MaterialTheme.typography.labelMedium,
                        color = SoftGrayText,
                    )
                }
                if (uiState.hasActiveQuery && uiState.searchQuery.isNotBlank()) {
                    SoftSearchPill(label = uiState.searchQuery, selected = true, onClick = {})
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SoftStatTile("总件数/款", "${statistics.totalPieces}/${statistics.totalStyles}")
                SoftStatTile("裙装价值", statistics.wardrobeValue.moneyText(), accent = true)
                SoftStatTile("总价值", statistics.totalValue.moneyText())
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FeaturePill(Icons.Filled.CheckCircle, "今日穿搭色", PinkPrimary)
                FeaturePill(Icons.Filled.Menu, "穿搭手帐", PinkPrimary)
                FeaturePill(Icons.Filled.BarChart, "详细统计", SoftGrayText, onClick = onStatisticsClick)
            }
        }
    }
}

@Composable
private fun RowScope.SoftStatTile(
    title: String,
    value: String,
    accent: Boolean = false,
) {
    Surface(
        modifier = Modifier.weight(1f),
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.52f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.8f)),
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(title, style = MaterialTheme.typography.labelMedium, color = SoftGrayText)
            Text(
                value,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = if (accent) PinkAccent else SoftGrayText,
            )
        }
    }
}

@Composable
private fun RowScope.FeaturePill(
    icon: ImageVector,
    label: String,
    tint: Color,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(18.dp)
    Surface(
        modifier = Modifier
            .weight(1f)
            .clip(shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = shape,
        color = Color.White.copy(alpha = 0.48f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.74f)),
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
private fun WardrobeDetailedStatisticsSheet(
    uiState: WardrobeHomeUiState,
    onDismiss: () -> Unit,
) {
    val statistics = if (uiState.hasActiveQuery) uiState.visibleStatistics else uiState.statistics
    val scopeLabel = if (uiState.hasActiveQuery) "当前搜索/筛选结果" else "全量衣橱"
    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "详细统计",
            leading = {
                TextButton(onClick = onDismiss) { Text("关闭") }
            },
            trailing = {
                Text(scopeLabel, color = SoftGrayText, style = MaterialTheme.typography.labelMedium)
            },
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(PinkBackground.copy(alpha = 0.38f)),
            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                SoftGlassPanel {
                    Column(
                        modifier = Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("统计口径：$scopeLabel", color = SoftGrayText, style = MaterialTheme.typography.bodyMedium)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            SoftStatTile("总件数/款", "${statistics.totalPieces}/${statistics.totalStyles}")
                            SoftStatTile("总价值", statistics.totalValue.moneyText())
                            SoftStatTile("尾款", statistics.depositBalance.moneyText(), accent = true)
                        }
                    }
                }
            }
            item { StatisticsBreakdownSection("按品牌", uiState.statisticsBreakdown.byBrand) }
            item { StatisticsBreakdownSection("按类型", uiState.statisticsBreakdown.byType) }
            item { StatisticsBreakdownSection("按颜色", uiState.statisticsBreakdown.byColor) }
            item { StatisticsBreakdownSection("按状态", uiState.statisticsBreakdown.byCondition) }
            item { StatisticsBreakdownSection("按尾款状态", uiState.statisticsBreakdown.byDepositState) }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun StatisticsBreakdownSection(
    title: String,
    rows: List<WardrobeStatisticBucket>,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(26.dp)),
        shape = RoundedCornerShape(26.dp),
        color = Color.White.copy(alpha = 0.66f),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = PinkPrimary)
            if (rows.isEmpty()) {
                Text("暂无可统计数据", color = SoftGrayText, style = MaterialTheme.typography.bodyMedium)
            } else {
                rows.forEach { row ->
                    StatisticsBreakdownRow(row)
                }
            }
        }
    }
}

@Composable
private fun StatisticsBreakdownRow(row: WardrobeStatisticBucket) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = Color.White.copy(alpha = 0.48f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.72f)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(row.label, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    text = "${row.totalPieces} 件 / ${row.totalStyles} 款",
                    color = SoftGrayText,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(row.totalValue.moneyText(), fontWeight = FontWeight.Bold, color = SoftGrayText)
                if (row.depositBalance > BigDecimal.ZERO) {
                    Text("尾款 ${row.depositBalance.moneyText()}", color = PinkAccent, style = MaterialTheme.typography.bodySmall)
                }
            }
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
            contentPadding = PaddingValues(bottom = if (uiState.isSelectionMode) 96.dp else 92.dp),
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
            contentPadding = PaddingValues(bottom = if (uiState.isSelectionMode) 96.dp else 92.dp),
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
                contentPadding = PaddingValues(bottom = 92.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Text(
                        text = if (uiState.depositDisplayMode == DepositDisplayMode.Detail) "最近月统计" else "按系列统计",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                if (uiState.depositDisplayMode == DepositDisplayMode.Detail) {
                    items(uiState.depositMonthSummaries, key = { it.month.toString() }) { summary ->
                        DepositSummaryRow(title = "${summary.month}", subtitle = "${summary.itemCount} 件待付", amount = summary.totalBalance)
                    }
                } else {
                    items(uiState.depositSeriesSummaries, key = { it.series }) { summary ->
                        DepositSummaryRow(title = summary.series, subtitle = "${summary.itemCount} 件待付", amount = summary.totalBalance)
                    }
                }
                item {
                    Text("待付明细", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                }
                items(uiState.visibleItems, key = { "deposit-${it.id}" }) { item ->
                    DepositItemRow(item = item)
                }
            }
        }
    }
}

@Composable
private fun DepositSummaryRow(title: String, subtitle: String, amount: BigDecimal) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.9f)),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(title, fontWeight = FontWeight.Bold)
                Text(subtitle, color = SoftGrayText, style = MaterialTheme.typography.bodySmall)
            }
            Text(amount.moneyText(), color = PinkAccent, fontWeight = FontWeight.Bold)
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
    val shape = RoundedCornerShape(28.dp)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(onClick = onClick),
        shape = shape,
        color = Color.White.copy(alpha = 0.66f),
        border = androidx.compose.foundation.BorderStroke(
            if (selected) 2.dp else 1.dp,
            if (selected) PinkAccent.copy(alpha = 0.72f) else Color.White.copy(alpha = 0.78f),
        ),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Column(modifier = Modifier.padding(if (compact) 7.dp else 9.dp)) {
            Box {
                WardrobeImage(
                    imagePath = imagePath,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1f)
                        .border(1.dp, Color.White.copy(alpha = 0.86f), RoundedCornerShape(22.dp))
                        .clip(RoundedCornerShape(22.dp)),
                )
                if (item.isDepositPlan) {
                    SoftDepositBadge(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(8.dp),
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
                Column(modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(
                        text = item.name,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = SoftGrayText,
                    )
                    SoftPricePill(item.inventoryTotalPrice.moneyText())
                }
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
    val shape = RoundedCornerShape(26.dp)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .clickable(onClick = onClick),
        shape = shape,
        color = Color.White.copy(alpha = 0.66f),
        border = androidx.compose.foundation.BorderStroke(
            if (selected) 2.dp else 1.dp,
            if (selected) PinkAccent.copy(alpha = 0.72f) else Color.White.copy(alpha = 0.78f),
        ),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
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
                        .border(1.dp, Color.White.copy(alpha = 0.86f), RoundedCornerShape(20.dp))
                        .clip(RoundedCornerShape(20.dp)),
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
                Text(item.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, color = SoftGrayText)
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
            SoftPricePill(item.inventoryTotalPrice.moneyText())
        }
    }
}

@Composable
private fun SoftDepositBadge(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(14.dp),
        color = PinkAccent.copy(alpha = 0.78f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.84f)),
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            text = "心愿尾款",
            color = Color.White,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun SoftPricePill(text: String) {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = PinkBackground.copy(alpha = 0.48f),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White.copy(alpha = 0.72f)),
    ) {
        Text(
            modifier = Modifier.padding(horizontal = 9.dp, vertical = 4.dp),
            text = text,
            color = SoftGrayText,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
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
                    colors = listOf(Color.White.copy(alpha = 0.64f), PinkBackground.copy(alpha = 0.58f)),
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

@Composable
private fun WardrobeItemEditorSheet(
    viewModel: WardrobeHomeViewModel,
    existing: WardrobeItem?,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    var draft by remember(existing?.id) { mutableStateOf(existing?.toEditorDraft() ?: WardrobeEditorDraft()) }
    var showNameError by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val availableTestMedia = remember(viewModel) { viewModel.availableTestMedia() }
    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            coroutineScope.launch {
                val fileName = viewModel.importImage(uri)
                draft = draft.copy(imageFileNames = draft.imageFileNames + fileName)
            }
        }
    }

    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = if (existing == null) "手动创建" else "编辑衣物",
            leading = {
                TextButton(onClick = onDismiss) { Text("取消") }
            },
            trailing = {
                TextButton(
                    onClick = {
                        showNameError = draft.name.isBlank()
                        if (!showNameError && viewModel.saveDraft(draft, existing)) {
                            onSaved()
                        }
                    },
                ) {
                    Text("保存")
                }
            },
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                FormSection(title = "裙装信息") {
                    Text("选择图片（最多9张，第一张为主图）", color = SoftGrayText)
                    if (draft.imageFileNames.isNotEmpty()) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            items(draft.imageFileNames.take(6), key = { it }) { fileName ->
                                WardrobeImage(
                                    imagePath = viewModel.imageFilePath(fileName),
                                    modifier = Modifier
                                        .size(84.dp)
                                        .clip(RoundedCornerShape(12.dp)),
                                )
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(
                            onClick = {
                                imagePicker.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                                )
                            },
                        ) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Spacer(Modifier.width(4.dp))
                            Text("相册")
                        }
                        if (availableTestMedia.isNotEmpty()) {
                            OutlinedButton(
                                onClick = {
                                    coroutineScope.launch {
                                        val fileName = viewModel.importTestMedia(availableTestMedia.first().assetPath)
                                        draft = draft.copy(imageFileNames = draft.imageFileNames + fileName)
                                    }
                                },
                            ) {
                                Icon(Icons.Filled.Image, contentDescription = null)
                                Spacer(Modifier.width(4.dp))
                                Text("测试图片")
                            }
                        }
                    }
                    if (availableTestMedia.isNotEmpty()) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(availableTestMedia, key = { it.assetPath }) { media ->
                                AssistChip(
                                    onClick = {
                                        coroutineScope.launch {
                                            val fileName = viewModel.importTestMedia(media.assetPath)
                                            draft = draft.copy(imageFileNames = draft.imageFileNames + fileName)
                                        }
                                    },
                                    label = { Text(media.displayName) },
                                )
                            }
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
                    DraftTextField("标签（逗号分隔，如：茶会,通勤）", draft.tags, "例如：茶会,通勤") { draft = draft.copy(tags = it) }
                    DraftTextField("小物（逗号分隔，如：BNT,发箍KC,发带）", draft.accessories, "例如：BNT,发箍KC") { draft = draft.copy(accessories = it) }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        DraftTextField("小物明细", draft.accessoryItemName, "例如：KC", Modifier.weight(1f)) {
                            draft = draft.copy(accessoryItemName = it)
                        }
                        DraftTextField("明细价", draft.accessoryItemPrice, "0", Modifier.weight(1f)) {
                            draft = draft.copy(accessoryItemPrice = it)
                        }
                        DraftTextField("数量", draft.accessoryItemQuantity, "1", Modifier.weight(0.7f)) {
                            draft = draft.copy(accessoryItemQuantity = it)
                        }
                    }
                }
            }
            item {
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
            }
            item {
                FormSection(title = "购买信息") {
                    DatePickerField("购买日期", draft.purchaseDate) { draft = draft.copy(purchaseDate = it) }
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
                        DatePickerField("定金日期", draft.depositDate) { draft = draft.copy(depositDate = it) }
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            DatePickerField("尾款开始", draft.finalPaymentStartDate, Modifier.weight(1f)) {
                                draft = draft.copy(finalPaymentStartDate = it)
                            }
                            DatePickerField("尾款截止", draft.finalPaymentEndDate, Modifier.weight(1f)) {
                                draft = draft.copy(finalPaymentEndDate = it)
                            }
                        }
                    }
                    DraftTextField("备注", draft.note, "可记录购买渠道、搭配想法等") { draft = draft.copy(note = it) }
                }
            }
            item { Spacer(Modifier.height(20.dp)) }
        }
    }
}

@Composable
private fun WardrobeItemDetailSheet(
    item: WardrobeItem,
    viewModel: WardrobeHomeViewModel,
    onDismiss: () -> Unit,
    onSoftDelete: () -> Unit,
) {
    val selectedItem = item
    var showEditSheet by rememberSaveable(item.id) { mutableStateOf(false) }
    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "衣物详情",
            leading = {
                TextButton(onClick = onDismiss) { Text("关闭") }
            },
            trailing = {
                TextButton(onClick = { showEditSheet = true }) {
                    Icon(Icons.Filled.Edit, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("编辑")
                }
            },
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                WardrobeImage(
                    imagePath = selectedItem.imagePaths.firstOrNull()?.let(viewModel::imageFilePath),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                        .clip(RoundedCornerShape(22.dp)),
                )
            }
            item { Text(selectedItem.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold) }
            item { DetailLine("品牌", selectedItem.brand.orEmpty().ifBlank { "未填写" }) }
            item { DetailLine("类型", selectedItem.category) }
            item { DetailLine("颜色", selectedItem.colors.ifBlank { selectedItem.color.orEmpty() }.ifBlank { "未填写" }) }
            item { DetailLine("尺码/衣长", listOf(selectedItem.sizes, selectedItem.length).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "未填写" }) }
            item { DetailLine("成色", selectedItem.condition) }
            item { DetailLine("标签", selectedItem.tags.joinToString("，").ifBlank { "未填写" }) }
            item { DetailLine("小物", selectedItem.accessories.ifBlank { "未填写" }) }
            if (selectedItem.accessoryItems.isNotEmpty()) {
                items(selectedItem.accessoryItems) { accessory ->
                    DetailLine("小物明细", "${accessory.name} x${accessory.quantity} · ${accessory.totalPrice.moneyText()}")
                }
            }
            item { DetailLine("总价", selectedItem.inventoryTotalPrice.moneyText()) }
            item { DetailLine("库存", selectedItem.stock.toString()) }
            if (selectedItem.isDepositPlan) {
                item { DetailLine("心愿尾款", "定金 ${selectedItem.totalDeposit.moneyText()} · 尾款 ${selectedItem.totalBalance.moneyText()}") }
                item { DetailLine("尾款日期", listOfNotNull(selectedItem.finalPaymentStartDate, selectedItem.finalPaymentEndDate).joinToString(" ~ ").ifBlank { "未填写" }) }
            }
            item { DetailLine("备注", selectedItem.note.ifBlank { "未填写" }) }
            item {
                OutlinedButton(onClick = onSoftDelete, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.Delete, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("移入回收站")
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }

    if (showEditSheet) {
        WardrobeItemEditorSheet(
            viewModel = viewModel,
            existing = item,
            onDismiss = { showEditSheet = false },
            onSaved = { showEditSheet = false },
        )
    }
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = SoftGrayText)
        Text(
            value,
            modifier = Modifier.weight(1f).padding(start = 16.dp),
            fontWeight = FontWeight.SemiBold,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
        )
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
private fun DatePickerField(
    label: String,
    value: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    onValueChange: (String) -> Unit,
) {
    var showPicker by remember { mutableStateOf(false) }
    val interactionSource = remember { MutableInteractionSource() }

    LaunchedEffect(interactionSource) {
        interactionSource.interactions.collect { interaction ->
            if (interaction is PressInteraction.Press) {
                showPicker = true
            }
        }
    }

    OutlinedTextField(
        value = value,
        onValueChange = {},
        modifier = modifier,
        label = { Text(label) },
        placeholder = { Text("YYYY-MM-DD") },
        readOnly = true,
        singleLine = true,
        interactionSource = interactionSource,
        trailingIcon = {
            IconButton(onClick = { showPicker = true }) {
                Icon(Icons.Filled.CalendarMonth, contentDescription = "选择日期")
            }
        },
        shape = RoundedCornerShape(14.dp),
    )

    if (showPicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = runCatching {
                LocalDate.parse(value).toEpochDay() * 86400000L
            }.getOrNull(),
        )
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        datePickerState.selectedDateMillis?.let { millis ->
                            val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                            onValueChange(date.toString())
                        }
                        showPicker = false
                    },
                ) { Text("确定") }
            },
            dismissButton = {
                TextButton(onClick = { showPicker = false }) { Text("取消") }
            },
        ) {
            DatePicker(state = datePickerState)
        }
    }
}

@Composable
private fun FilterSheet(
    uiState: WardrobeHomeUiState,
    current: WardrobeFilterState,
    onDismiss: () -> Unit,
    onApply: (WardrobeFilterState) -> Unit,
    onClear: () -> Unit,
) {
    var draft by remember(current) { mutableStateOf(current) }
    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "筛选",
            leading = { },
            trailing = {
                TextButton(onClick = onClear) { Text("清除") }
            },
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentPadding = PaddingValues(start = 22.dp, end = 22.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item { DraftTextField("品牌", draft.brand, "例如：Baby") { draft = draft.copy(brand = it) } }
            item { DraftTextField("类型", draft.type, "例如：JSK") { draft = draft.copy(type = it) } }
            item { DraftTextField("颜色", draft.color, "例如：粉色") { draft = draft.copy(color = it) } }
            item { DraftTextField("尺码", draft.size, "例如：M") { draft = draft.copy(size = it) } }
            item { DraftTextField("衣长", draft.length, "例如：90cm") { draft = draft.copy(length = it) } }
            item { DraftTextField("状态", draft.condition, "例如：全新") { draft = draft.copy(condition = it) } }
            item { DraftTextField("小物", draft.accessory, "例如：BNT") { draft = draft.copy(accessory = it) } }
            item { DraftTextField("标签", draft.tag, "例如：茶会") { draft = draft.copy(tag = it) } }
            item { Text("可输入：无标签、无品牌、无类型、无颜色、无尺码、无衣长、无成色、无小物", color = SoftGrayText, style = MaterialTheme.typography.bodySmall) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("无品牌", "无标签", "无小物").forEach { token ->
                        AssistChip(onClick = {
                            draft = when (token) {
                                "无品牌" -> draft.copy(brand = token)
                                "无标签" -> draft.copy(tag = token)
                                else -> draft.copy(accessory = token)
                            }
                        }, label = { Text(token) })
                    }
                }
            }
            if (uiState.allItems.isNotEmpty()) {
                item { Text("当前可筛选 ${uiState.allItems.size} 件衣物", color = SoftGrayText, style = MaterialTheme.typography.bodySmall) }
            }
            item {
                FilterChip(
                    selected = draft.depositOnly,
                    onClick = { draft = draft.copy(depositOnly = !draft.depositOnly) },
                    label = { Text("只看心愿尾款") },
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 22.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onDismiss) { Text("取消") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = { onApply(draft) }) { Text("应用筛选") }
        }
    }
}

@Composable
private fun BatchImportSheet(
    viewModel: WardrobeHomeViewModel,
    onDismiss: () -> Unit,
) {
    var seriesName by rememberSaveable { mutableStateOf("") }
    var imageFileNames by rememberSaveable { mutableStateOf(emptyList<String>()) }
    val coroutineScope = rememberCoroutineScope()
    val availableTestMedia = remember(viewModel) { viewModel.availableTestMedia() }
    val multiPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(30)) { uris ->
        if (uris.isNotEmpty()) {
            coroutineScope.launch {
                imageFileNames = imageFileNames + uris.map { uri -> viewModel.importImage(uri) }
            }
        }
    }

    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "批量导入",
            leading = {
                TextButton(onClick = onDismiss) { Text("取消") }
            },
            trailing = {
                TextButton(
                    enabled = imageFileNames.isNotEmpty(),
                    onClick = {
                        imageFileNames.forEachIndexed { index, fileName ->
                            viewModel.saveDraft(
                                WardrobeEditorDraft(
                                    imageFileNames = listOf(fileName),
                                    name = listOf(seriesName.ifBlank { "未命名裙装" }, (index + 1).toString()).joinToString(" "),
                                    types = "裙装",
                                    purchaseDate = LocalDate.now().toString(),
                                ),
                            )
                        }
                        onDismiss()
                    },
                ) { Text("导入") }
            },
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(horizontal = 22.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            DraftTextField("系列名/批量前缀", seriesName, "例如：梦幻下午茶") { seriesName = it }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    onClick = {
                        multiPicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Filled.Image, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("相册多选")
                }
                if (availableTestMedia.isNotEmpty()) {
                    OutlinedButton(
                        onClick = {
                            coroutineScope.launch {
                                val newNames = availableTestMedia.map { media ->
                                    viewModel.importTestMedia(media.assetPath)
                                }
                                imageFileNames = imageFileNames + newNames
                            }
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Filled.Image, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("全部测试图")
                    }
                }
            }
            if (imageFileNames.isEmpty()) {
                EmptyState(
                    title = "还没有选择图片",
                    description = "会使用 Android Photo Picker，多选后先复制到 App 私有目录再建衣物。",
                    onCreateClick = {
                        multiPicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    },
                )
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 24.dp),
                ) {
                    items(imageFileNames, key = { it }) { fileName ->
                        Box {
                            WardrobeImage(
                                imagePath = viewModel.imageFilePath(fileName),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(1f)
                                    .clip(RoundedCornerShape(14.dp)),
                            )
                            IconButton(
                                onClick = { imageFileNames = imageFileNames - fileName },
                                modifier = Modifier.align(Alignment.TopEnd),
                            ) {
                                Icon(Icons.Filled.Close, contentDescription = "移除", tint = PinkAccent)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecycleBinSheet(
    items: List<WardrobeItem>,
    onDismiss: () -> Unit,
    onRestore: (List<Long>) -> Unit,
    onHardDelete: (List<Long>) -> Unit,
) {
    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "回收站",
            leading = { },
            trailing = {
                TextButton(onClick = onDismiss) { Text("完成") }
            },
        )
        if (items.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 22.dp),
                contentAlignment = Alignment.Center,
            ) {
                EmptyState(
                    title = "回收站为空",
                    description = "批量删除和详情删除会先进入这里，之后可恢复或彻底删除。",
                    onCreateClick = onDismiss,
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 22.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = { onRestore(items.map { it.id }) }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.Restore, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("全部恢复")
                    }
                    OutlinedButton(onClick = { onHardDelete(items.map { it.id }) }, modifier = Modifier.weight(1f)) {
                        Icon(Icons.Filled.Delete, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("全部删除")
                    }
                }
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(items, key = { it.id }) { recycledItem ->
                        Card(shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = PinkSurface)) {
                            Row(
                                modifier = Modifier.padding(12.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(recycledItem.name, fontWeight = FontWeight.Bold)
                                    Text(
                                        "删除时间 ${recycledItem.trashedAtEpochMillis ?: "-"}",
                                        color = SoftGrayText,
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                }
                                TextButton(onClick = { onRestore(listOf(recycledItem.id)) }) { Text("恢复") }
                                TextButton(onClick = { onHardDelete(listOf(recycledItem.id)) }) { Text("删除") }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DepositReminderSheet(
    uiState: WardrobeHomeUiState,
    onDismiss: () -> Unit,
    onSave: (Boolean, String, String, List<WardrobeItem>) -> Unit,
) {
    var enabled by rememberSaveable(uiState.depositReminderEnabled) { mutableStateOf(uiState.depositReminderEnabled) }
    var daysBefore by rememberSaveable(uiState.depositReminderDaysBefore) { mutableStateOf(uiState.depositReminderDaysBefore) }
    var reminderTime by rememberSaveable(uiState.depositReminderTime) { mutableStateOf(uiState.depositReminderTime) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

    PinkFullHeightSheet(onDismissRequest = onDismiss) {
        PinkSheetHeader(
            title = "尾款提醒",
            leading = { },
            trailing = {
                TextButton(onClick = onDismiss) { Text("关闭") }
            },
        )
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("本地通知", fontWeight = FontWeight.Bold)
                        Text("只在本机安排 AlarmManager 通知，不接云端推送。", color = SoftGrayText, style = MaterialTheme.typography.bodySmall)
                    }
                    Switch(checked = enabled, onCheckedChange = { enabled = it })
                }
            }
            item { DraftTextField("提前天数", daysBefore, "例如：7,3,1") { daysBefore = it } }
            item { DraftTextField("提醒时间", reminderTime, "HH:mm") { reminderTime = it } }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                item {
                    OutlinedButton(
                        onClick = { permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Filled.Notifications, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("允许通知权限")
                    }
                }
            }
            item { Text("当前有 ${uiState.allItems.count { it.isDepositPlan }} 个心愿尾款项目，最近已安排 ${uiState.scheduledReminderCount} 个提醒。", color = SoftGrayText) }
            if (uiState.depositMonthSummaries.isNotEmpty()) {
                item { Text("最近月统计", fontWeight = FontWeight.Bold) }
                items(uiState.depositMonthSummaries.take(6)) { summary ->
                    DetailLine("${summary.month}", "${summary.itemCount} 件 · ${summary.totalBalance.moneyText()}")
                }
            }
            item {
                Button(
                    onClick = {
                        onSave(enabled, daysBefore, reminderTime, uiState.allItems)
                        onDismiss()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Save, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("保存提醒设置")
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
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
