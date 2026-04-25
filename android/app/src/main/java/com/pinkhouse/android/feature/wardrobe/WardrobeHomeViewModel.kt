package com.pinkhouse.android.feature.wardrobe

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pinkhouse.android.core.datastore.UserPreferencesDataStore
import com.pinkhouse.android.core.media.WardrobeImageStore
import com.pinkhouse.android.core.media.WardrobeTestMedia
import com.pinkhouse.android.core.media.WardrobeTestMediaManager
import com.pinkhouse.android.core.notification.DepositReminderScheduler
import com.pinkhouse.android.domain.model.WardrobeAccessoryItem
import com.pinkhouse.android.domain.model.WardrobeItem
import com.pinkhouse.android.domain.model.WardrobeItemStatus
import com.pinkhouse.android.domain.repository.WardrobeRepository
import com.pinkhouse.android.domain.usecase.BatchSoftDeleteWardrobeItems
import java.math.BigDecimal
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class WardrobeHomeTab(val raw: String, val label: String) {
    Wardrobe("wardrobe", "少女衣橱"),
    DepositPlan("depositPlan", "心愿尾款");

    companion object {
        fun fromRaw(raw: String): WardrobeHomeTab = entries.firstOrNull { it.raw == raw } ?: Wardrobe
    }
}

enum class WardrobeSortOption(val raw: String, val label: String) {
    CreatedAtDesc("createdAtDesc", "添加时间从晚到早"),
    PriceAsc("priceAsc", "价格从低到高"),
    PriceDesc("priceDesc", "价格从高到低"),
    PurchaseDateAsc("purchaseDateAsc", "购买时间从早到晚"),
    PurchaseDateDesc("purchaseDateDesc", "购买时间从晚到早"),
    NameAsc("nameAsc", "名称从A到Z"),
    NameDesc("nameDesc", "名称从Z到A"),
    Custom("custom", "自定义顺序");

    companion object {
        fun fromRaw(raw: String): WardrobeSortOption = entries.firstOrNull { it.raw == raw } ?: CreatedAtDesc
    }
}

enum class WardrobeLayoutMode(val raw: String, val label: String, val gridColumns: Int?) {
    ListBrief("listBrief", "单行简略", null),
    ListDetailed("listDetailed", "单行详细", null),
    Grid2("grid2", "双列", 2),
    Grid3("grid3", "三列", 3),
    Grid6("grid6", "六列", 6);

    companion object {
        fun fromRaw(raw: String): WardrobeLayoutMode = entries.firstOrNull { it.raw == raw } ?: Grid2
    }
}

enum class DepositDisplayMode(val raw: String, val label: String) {
    Detail("detail", "详情"),
    Simple("simple", "简略");

    companion object {
        fun fromRaw(raw: String): DepositDisplayMode = entries.firstOrNull { it.raw == raw } ?: Detail
    }
}

data class WardrobeFilterState(
    val brand: String = "",
    val type: String = "",
    val color: String = "",
    val size: String = "",
    val length: String = "",
    val condition: String = "",
    val accessory: String = "",
    val tag: String = "",
    val depositOnly: Boolean = false,
) {
    val activeCount: Int
        get() = listOf(brand, type, color, size, length, condition, accessory, tag).count { it.isNotBlank() } +
            if (depositOnly) 1 else 0
}

data class WardrobeEditorDraft(
    val imageFileNames: List<String> = emptyList(),
    val name: String = "",
    val brand: String = "",
    val types: String = "",
    val colors: String = "",
    val sizes: String = "",
    val length: String = "",
    val condition: String = "全新",
    val accessories: String = "",
    val tags: String = "",
    val accessoryItemName: String = "",
    val accessoryItemPrice: String = "",
    val accessoryItemQuantity: String = "1",
    val originalPrice: String = "",
    val price: String = "",
    val deposit: String = "",
    val balance: String = "",
    val accessoriesPrice: String = "",
    val stock: String = "1",
    val purchaseDate: String = LocalDate.now().toString(),
    val depositDate: String = "",
    val isDepositPlan: Boolean = false,
    val finalPaymentStartDate: String = "",
    val finalPaymentEndDate: String = "",
    val note: String = "",
)

data class WardrobeStatistics(
    val totalPieces: Int = 0,
    val totalStyles: Int = 0,
    val wardrobeValue: BigDecimal = BigDecimal.ZERO,
    val totalValue: BigDecimal = BigDecimal.ZERO,
    val depositBalance: BigDecimal = BigDecimal.ZERO,
)

data class WardrobeHomeUiState(
    val homeTab: WardrobeHomeTab = WardrobeHomeTab.Wardrobe,
    val sortOption: WardrobeSortOption = WardrobeSortOption.CreatedAtDesc,
    val layoutMode: WardrobeLayoutMode = WardrobeLayoutMode.Grid2,
    val depositDisplayMode: DepositDisplayMode = DepositDisplayMode.Detail,
    val searchQuery: String = "",
    val isSearchVisible: Boolean = false,
    val filterState: WardrobeFilterState = WardrobeFilterState(),
    val allItems: List<WardrobeItem> = emptyList(),
    val visibleItems: List<WardrobeItem> = emptyList(),
    val statistics: WardrobeStatistics = WardrobeStatistics(),
    val visibleStatistics: WardrobeStatistics = WardrobeStatistics(),
    val isSelectionMode: Boolean = false,
    val selectedItemIds: Set<Long> = emptySet(),
    val message: String? = null,
    val selectedItem: WardrobeItem? = null,
    val trashedItems: List<WardrobeItem> = emptyList(),
    val depositMonthSummaries: List<DepositMonthSummary> = emptyList(),
    val depositSeriesSummaries: List<DepositSeriesSummary> = emptyList(),
    val depositReminderEnabled: Boolean = false,
    val depositReminderDaysBefore: String = "7,3,1",
    val depositReminderTime: String = "09:00",
    val scheduledReminderCount: Int = 0,
) {
    val allVisibleSelected: Boolean
        get() = visibleItems.isNotEmpty() && visibleItems.all { selectedItemIds.contains(it.id) }

    val hasActiveQuery: Boolean
        get() = searchQuery.isNotBlank() || filterState.activeCount > 0
}

private data class WardrobeRuntimeState(
    val searchQuery: String = "",
    val isSearchVisible: Boolean = false,
    val filterState: WardrobeFilterState = WardrobeFilterState(),
    val isSelectionMode: Boolean = false,
    val selectedItemIds: Set<Long> = emptySet(),
    val message: String? = null,
    val selectedItemId: Long? = null,
    val scheduledReminderCount: Int = 0,
)

@OptIn(ExperimentalCoroutinesApi::class)
class WardrobeHomeViewModel(
    private val wardrobeRepository: WardrobeRepository,
    private val batchSoftDeleteWardrobeItems: BatchSoftDeleteWardrobeItems,
    private val userPreferencesDataStore: UserPreferencesDataStore,
    private val wardrobeImageStore: WardrobeImageStore,
    private val wardrobeTestMediaManager: WardrobeTestMediaManager,
    private val depositReminderScheduler: DepositReminderScheduler,
) : ViewModel() {
    private val runtimeState = MutableStateFlow(WardrobeRuntimeState())

    private val items = runtimeState
        .map { it.searchQuery }
        .distinctUntilChanged()
        .flatMapLatest { wardrobeRepository.observeItems() }

    private val selectedItem = runtimeState
        .map { it.selectedItemId }
        .distinctUntilChanged()
        .flatMapLatest { id ->
            if (id == null) {
                kotlinx.coroutines.flow.flowOf(null)
            } else {
                wardrobeRepository.observeItem(id)
            }
        }

    private val trashedItems = wardrobeRepository.observeTrashedItems()

    val uiState = combine(
        items,
        userPreferencesDataStore.preferences,
        runtimeState,
        selectedItem,
        trashedItems,
    ) { sourceItems, preferences, runtime, selected, trashed ->
        val tab = WardrobeHomeTab.fromRaw(preferences.wardrobeHomeTab)
        val sort = WardrobeSortOption.fromRaw(preferences.wardrobeSortOption)
        val layout = WardrobeLayoutMode.fromRaw(preferences.wardrobeViewMode)
        val depositDisplay = DepositDisplayMode.fromRaw(preferences.depositDisplayMode)
        val searched = WardrobeBusinessLogic.searchItems(sourceItems, runtime.searchQuery)
        val filtered = WardrobeBusinessLogic.filterItems(searched, runtime.filterState)
            .let { list -> if (tab == WardrobeHomeTab.DepositPlan) list.filter { it.isDepositPlan } else list }
            .let { list -> WardrobeBusinessLogic.sortItems(list, sort) }
        WardrobeHomeUiState(
            homeTab = tab,
            sortOption = sort,
            layoutMode = layout,
            depositDisplayMode = depositDisplay,
            searchQuery = runtime.searchQuery,
            isSearchVisible = runtime.isSearchVisible,
            filterState = runtime.filterState,
            allItems = sourceItems,
            visibleItems = filtered,
            statistics = sourceItems.toStatistics(),
            visibleStatistics = filtered.toStatistics(),
            isSelectionMode = runtime.isSelectionMode,
            selectedItemIds = runtime.selectedItemIds.intersect(filtered.map { it.id }.toSet()),
            message = runtime.message,
            selectedItem = selected,
            trashedItems = trashed,
            depositMonthSummaries = WardrobeBusinessLogic.monthlyDepositSummaries(sourceItems),
            depositSeriesSummaries = WardrobeBusinessLogic.seriesDepositSummaries(sourceItems),
            depositReminderEnabled = preferences.depositReminderEnabled,
            depositReminderDaysBefore = preferences.depositReminderDaysBefore,
            depositReminderTime = preferences.depositReminderTime,
            scheduledReminderCount = runtime.scheduledReminderCount,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WardrobeHomeUiState(),
    )

    fun selectHomeTab(tab: WardrobeHomeTab) {
        viewModelScope.launch { userPreferencesDataStore.setWardrobeHomeTab(tab.raw) }
        runtimeState.update { it.copy(isSelectionMode = false, selectedItemIds = emptySet()) }
    }

    fun setSearchVisible(visible: Boolean) {
        runtimeState.update { it.copy(isSearchVisible = visible, searchQuery = if (visible) it.searchQuery else "") }
    }

    fun setSearchQuery(query: String) {
        runtimeState.update { it.copy(searchQuery = query) }
    }

    fun setSortOption(option: WardrobeSortOption) {
        viewModelScope.launch { userPreferencesDataStore.setWardrobeSortOption(option.raw) }
    }

    fun setLayoutMode(mode: WardrobeLayoutMode) {
        viewModelScope.launch { userPreferencesDataStore.setWardrobeViewMode(mode.raw) }
    }

    fun setDepositDisplayMode(mode: DepositDisplayMode) {
        viewModelScope.launch { userPreferencesDataStore.setDepositDisplayMode(mode.raw) }
    }

    fun setFilterState(filterState: WardrobeFilterState) {
        runtimeState.update { it.copy(filterState = filterState) }
    }

    fun clearFilters() {
        runtimeState.update { it.copy(filterState = WardrobeFilterState()) }
    }

    fun enterSelectionMode() {
        runtimeState.update { it.copy(isSelectionMode = true, selectedItemIds = emptySet()) }
    }

    fun exitSelectionMode() {
        runtimeState.update { it.copy(isSelectionMode = false, selectedItemIds = emptySet()) }
    }

    fun toggleItemSelection(id: Long) {
        runtimeState.update { state ->
            val selected = state.selectedItemIds.toMutableSet()
            if (!selected.add(id)) selected.remove(id)
            state.copy(selectedItemIds = selected)
        }
    }

    fun toggleSelectAll(visibleIds: List<Long>) {
        runtimeState.update { state ->
            val visible = visibleIds.toSet()
            val next = if (visible.isNotEmpty() && visible.all { state.selectedItemIds.contains(it) }) {
                state.selectedItemIds - visible
            } else {
                state.selectedItemIds + visible
            }
            state.copy(selectedItemIds = next)
        }
    }

    fun softDeleteSelected() {
        val ids = runtimeState.value.selectedItemIds
        viewModelScope.launch {
            batchSoftDeleteWardrobeItems(ids)
            runtimeState.update {
                it.copy(
                    isSelectionMode = false,
                    selectedItemIds = emptySet(),
                    message = "已移入回收站",
                )
            }
        }
    }

    fun selectItem(itemId: Long?) {
        runtimeState.update { it.copy(selectedItemId = itemId) }
    }

    fun softDeleteItem(id: Long) {
        viewModelScope.launch {
            wardrobeRepository.softDeleteItem(id)
            runtimeState.update { it.copy(selectedItemId = null, message = "已移入回收站") }
        }
    }

    fun restoreItems(ids: List<Long>) {
        viewModelScope.launch {
            wardrobeRepository.restoreItems(ids)
            runtimeState.update { it.copy(message = "已恢复 ${ids.size} 件衣物") }
        }
    }

    fun permanentlyDeleteItems(ids: List<Long>) {
        viewModelScope.launch {
            wardrobeRepository.permanentlyDeleteItems(ids)
            runtimeState.update { it.copy(message = "已彻底删除 ${ids.size} 件衣物") }
        }
    }

    fun saveReminderSettings(enabled: Boolean, daysBefore: String, time: String, items: List<WardrobeItem>) {
        viewModelScope.launch {
            userPreferencesDataStore.setDepositReminderEnabled(enabled)
            userPreferencesDataStore.setDepositReminderDaysBefore(daysBefore)
            userPreferencesDataStore.setDepositReminderTime(time)
            val days = daysBefore.toReminderDays()
            val reminderTime = time.toReminderTime()
            val scheduled = if (enabled) {
                depositReminderScheduler.scheduleDepositReminders(items, days, reminderTime)
            } else {
                depositReminderScheduler.cancelDepositReminders(items, days)
                0
            }
            runtimeState.update {
                it.copy(
                    scheduledReminderCount = scheduled,
                    message = if (enabled) "已安排 $scheduled 个本地提醒" else "已关闭尾款提醒",
                )
            }
        }
    }

    suspend fun importImage(uri: Uri): String {
        return wardrobeImageStore.import(uri)
    }

    fun imageFilePath(fileName: String): String {
        return wardrobeImageStore.fileFor(fileName).absolutePath
    }

    fun availableTestMedia(): List<WardrobeTestMedia> {
        return wardrobeTestMediaManager.availableMedia()
    }

    suspend fun importTestMedia(assetPath: String): String {
        return wardrobeTestMediaManager.importMedia(assetPath)
    }

    suspend fun importAllTestMedia(): List<String> {
        return wardrobeTestMediaManager.importAllMedia()
    }

    fun saveDraft(draft: WardrobeEditorDraft): Boolean {
        return saveDraft(draft, existing = null)
    }

    fun saveDraft(draft: WardrobeEditorDraft, existing: WardrobeItem?): Boolean {
        val trimmedName = draft.name.trim()
        if (trimmedName.isBlank()) {
            runtimeState.update { it.copy(message = "请先填写裙装名称") }
            return false
        }

        val item = WardrobeItem(
            id = existing?.id ?: 0,
            uuid = existing?.uuid.orEmpty(),
            name = trimmedName,
            category = draft.types.firstToken().ifBlank { "裙装" },
            brand = draft.brand.trim().ifBlank { null },
            tags = draft.tags.splitTokens(),
            color = draft.colors.firstToken().ifBlank { null },
            colors = draft.colors.trim(),
            sizes = draft.sizes.trim(),
            length = draft.length.trim(),
            condition = draft.condition.trim().ifBlank { "全新" },
            accessories = draft.accessories.trim(),
            accessoryItems = draft.toAccessoryItems(),
            imagePaths = draft.imageFileNames,
            sizeChartImagePaths = existing?.sizeChartImagePaths.orEmpty(),
            priceChartImagePaths = existing?.priceChartImagePaths.orEmpty(),
            originalPrice = draft.originalPrice.toMoney(),
            price = draft.price.toMoney(),
            deposit = draft.deposit.toMoney(),
            balance = draft.balance.toMoney(),
            accessoriesPrice = draft.accessoriesPrice.toMoney(),
            stock = draft.stock.toIntOrNull()?.coerceAtLeast(1) ?: 1,
            purchaseDate = draft.purchaseDate.toLocalDateOrNull() ?: LocalDate.now(),
            depositDate = draft.depositDate.toLocalDateOrNull(),
            isDepositPlan = draft.isDepositPlan,
            finalPaymentStartDate = draft.finalPaymentStartDate.toLocalDateOrNull(),
            finalPaymentEndDate = draft.finalPaymentEndDate.toLocalDateOrNull(),
            note = draft.note.trim(),
            sortIndex = existing?.sortIndex ?: System.currentTimeMillis(),
            status = if (draft.isDepositPlan) WardrobeItemStatus.Reserved else WardrobeItemStatus.Owned,
            createdAtEpochMillis = existing?.createdAtEpochMillis ?: 0,
            updatedAtEpochMillis = existing?.updatedAtEpochMillis ?: 0,
        )

        viewModelScope.launch {
            if (existing == null) {
                wardrobeRepository.addItem(item)
            } else {
                wardrobeRepository.updateItem(item)
            }
            runtimeState.update { it.copy(message = if (existing == null) "已保存到衣橱" else "已更新衣物") }
        }
        return true
    }

    fun consumeMessage() {
        runtimeState.update { it.copy(message = null) }
    }
}

internal fun WardrobeSortOption.comparator(): Comparator<WardrobeItem> {
    return when (this) {
        WardrobeSortOption.CreatedAtDesc -> compareByDescending { it.sortIndex }
        WardrobeSortOption.PriceAsc -> compareBy { it.inventoryTotalPrice }
        WardrobeSortOption.PriceDesc -> compareByDescending { it.inventoryTotalPrice }
        WardrobeSortOption.PurchaseDateAsc -> compareBy(nullsLast()) { it.purchaseDate }
        WardrobeSortOption.PurchaseDateDesc -> compareByDescending<WardrobeItem> { it.purchaseDate ?: LocalDate.MIN }
        WardrobeSortOption.NameAsc -> compareBy { it.name }
        WardrobeSortOption.NameDesc -> compareByDescending { it.name }
        WardrobeSortOption.Custom -> compareBy { it.sortIndex }
    }
}

private fun List<WardrobeItem>.toStatistics(): WardrobeStatistics {
    return WardrobeStatistics(
        totalPieces = sumOf { it.stock.coerceAtLeast(1) },
        totalStyles = size,
        wardrobeValue = filterNot { it.isDepositPlan }.fold(BigDecimal.ZERO) { acc, item ->
            acc + item.inventoryTotalPrice
        },
        totalValue = fold(BigDecimal.ZERO) { acc, item -> acc + item.inventoryTotalPrice },
        depositBalance = filter { it.isDepositPlan }.fold(BigDecimal.ZERO) { acc, item ->
            acc + item.totalBalance
        },
    )
}

private fun String.firstToken(): String {
    return replace("，", ",")
        .split(",")
        .firstOrNull()
        ?.trim()
        .orEmpty()
}

private fun String.splitTokens(): List<String> {
    return replace("，", ",")
        .replace("、", ",")
        .split(",")
        .map { it.trim() }
        .filter { it.isNotBlank() }
}

private fun WardrobeEditorDraft.toAccessoryItems(): List<WardrobeAccessoryItem> {
    val itemName = accessoryItemName.trim()
    if (itemName.isBlank()) return emptyList()
    return listOf(
        WardrobeAccessoryItem(
            name = itemName,
            price = accessoryItemPrice.toMoney(),
            quantity = accessoryItemQuantity.toIntOrNull()?.coerceAtLeast(1) ?: 1,
        ),
    )
}

private fun String.toMoney(): BigDecimal {
    return trim()
        .takeIf { it.isNotBlank() }
        ?.let { runCatching { BigDecimal(it) }.getOrDefault(BigDecimal.ZERO) }
        ?: BigDecimal.ZERO
}

private fun String.toLocalDateOrNull(): LocalDate? {
    return trim()
        .takeIf { it.isNotBlank() }
        ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
}

private fun String.toReminderDays(): List<Int> {
    return splitTokens()
        .mapNotNull { it.toIntOrNull() }
        .filter { it >= 0 }
        .ifEmpty { DepositReminderScheduler.DEFAULT_DAYS }
}

private fun String.toReminderTime(): java.time.LocalTime {
    return runCatching { java.time.LocalTime.parse(trim()) }
        .getOrDefault(java.time.LocalTime.of(9, 0))
}

fun WardrobeItem.toEditorDraft(): WardrobeEditorDraft {
    val firstAccessory = accessoryItems.firstOrNull()
    return WardrobeEditorDraft(
        imageFileNames = imagePaths,
        name = name,
        brand = brand.orEmpty(),
        types = category,
        colors = colors.ifBlank { color.orEmpty() },
        sizes = sizes,
        length = length,
        condition = condition,
        accessories = accessories,
        tags = tags.joinToString(","),
        accessoryItemName = firstAccessory?.name.orEmpty(),
        accessoryItemPrice = firstAccessory?.price?.stripTrailingZeros()?.toPlainString().orEmpty(),
        accessoryItemQuantity = firstAccessory?.quantity?.toString() ?: "1",
        originalPrice = originalPrice.stripTrailingZeros().toPlainString(),
        price = price?.stripTrailingZeros()?.toPlainString().orEmpty(),
        deposit = deposit.stripTrailingZeros().toPlainString(),
        balance = balance.stripTrailingZeros().toPlainString(),
        accessoriesPrice = accessoriesPrice.stripTrailingZeros().toPlainString(),
        stock = stock.toString(),
        purchaseDate = purchaseDate?.toString().orEmpty(),
        depositDate = depositDate?.toString().orEmpty(),
        isDepositPlan = isDepositPlan,
        finalPaymentStartDate = finalPaymentStartDate?.toString().orEmpty(),
        finalPaymentEndDate = finalPaymentEndDate?.toString().orEmpty(),
        note = note,
    )
}
