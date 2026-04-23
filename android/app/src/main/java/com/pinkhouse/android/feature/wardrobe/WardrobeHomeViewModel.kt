package com.pinkhouse.android.feature.wardrobe

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pinkhouse.android.core.datastore.UserPreferencesDataStore
import com.pinkhouse.android.core.media.WardrobeImageStore
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
    val condition: String = "",
    val accessory: String = "",
    val depositOnly: Boolean = false,
) {
    val activeCount: Int
        get() = listOf(brand, type, color, size, condition, accessory).count { it.isNotBlank() } +
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
    val isSelectionMode: Boolean = false,
    val selectedItemIds: Set<Long> = emptySet(),
    val message: String? = null,
) {
    val allVisibleSelected: Boolean
        get() = visibleItems.isNotEmpty() && visibleItems.all { selectedItemIds.contains(it.id) }
}

private data class WardrobeRuntimeState(
    val searchQuery: String = "",
    val isSearchVisible: Boolean = false,
    val filterState: WardrobeFilterState = WardrobeFilterState(),
    val isSelectionMode: Boolean = false,
    val selectedItemIds: Set<Long> = emptySet(),
    val message: String? = null,
)

@OptIn(ExperimentalCoroutinesApi::class)
class WardrobeHomeViewModel(
    private val wardrobeRepository: WardrobeRepository,
    private val batchSoftDeleteWardrobeItems: BatchSoftDeleteWardrobeItems,
    private val userPreferencesDataStore: UserPreferencesDataStore,
    private val wardrobeImageStore: WardrobeImageStore,
) : ViewModel() {
    private val runtimeState = MutableStateFlow(WardrobeRuntimeState())

    private val items = runtimeState
        .map { it.searchQuery }
        .distinctUntilChanged()
        .flatMapLatest { query -> wardrobeRepository.observeItems(query) }

    val uiState = combine(
        items,
        userPreferencesDataStore.preferences,
        runtimeState,
    ) { sourceItems, preferences, runtime ->
        val tab = WardrobeHomeTab.fromRaw(preferences.wardrobeHomeTab)
        val sort = WardrobeSortOption.fromRaw(preferences.wardrobeSortOption)
        val layout = WardrobeLayoutMode.fromRaw(preferences.wardrobeViewMode)
        val depositDisplay = DepositDisplayMode.fromRaw(preferences.depositDisplayMode)
        val filtered = sourceItems
            .filter { item -> item.matches(runtime.filterState) }
            .let { list -> if (tab == WardrobeHomeTab.DepositPlan) list.filter { it.isDepositPlan } else list }
            .sortedWith(sort.comparator())
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
            isSelectionMode = runtime.isSelectionMode,
            selectedItemIds = runtime.selectedItemIds.intersect(filtered.map { it.id }.toSet()),
            message = runtime.message,
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

    suspend fun importImage(uri: Uri): String {
        return wardrobeImageStore.import(uri)
    }

    fun imageFilePath(fileName: String): String {
        return wardrobeImageStore.fileFor(fileName).absolutePath
    }

    fun saveDraft(draft: WardrobeEditorDraft): Boolean {
        val trimmedName = draft.name.trim()
        if (trimmedName.isBlank()) {
            runtimeState.update { it.copy(message = "请先填写裙装名称") }
            return false
        }

        val item = WardrobeItem(
            id = 0,
            name = trimmedName,
            category = draft.types.firstToken().ifBlank { "裙装" },
            brand = draft.brand.trim().ifBlank { null },
            color = draft.colors.firstToken().ifBlank { null },
            colors = draft.colors.trim(),
            sizes = draft.sizes.trim(),
            length = draft.length.trim(),
            condition = draft.condition.trim().ifBlank { "全新" },
            accessories = draft.accessories.trim(),
            imagePaths = draft.imageFileNames,
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
            sortIndex = System.currentTimeMillis(),
            status = if (draft.isDepositPlan) WardrobeItemStatus.Reserved else WardrobeItemStatus.Owned,
        )

        viewModelScope.launch {
            wardrobeRepository.addItem(item)
            runtimeState.update { it.copy(message = "已保存到衣橱") }
        }
        return true
    }

    fun consumeMessage() {
        runtimeState.update { it.copy(message = null) }
    }
}

private fun WardrobeItem.matches(filter: WardrobeFilterState): Boolean {
    return matchesText(brand.orEmpty(), filter.brand) &&
        matchesText(category, filter.type) &&
        matchesText(colors.ifBlank { color.orEmpty() }, filter.color) &&
        matchesText(sizes, filter.size) &&
        matchesText(condition, filter.condition) &&
        matchesText(accessories, filter.accessory) &&
        (!filter.depositOnly || isDepositPlan)
}

private fun matchesText(value: String, query: String): Boolean {
    return query.isBlank() || value.contains(query.trim(), ignoreCase = true)
}

private fun WardrobeSortOption.comparator(): Comparator<WardrobeItem> {
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
