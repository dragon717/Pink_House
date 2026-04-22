if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WardrobePage_Params {
    items?: WardrobeItem[];
    depositItems?: WardrobeItem[];
    searchKeyword?: string;
    isLoading?: boolean;
    errorMessage?: string;
    selectedSegment?: string;
    showCount?: boolean;
    showDressValue?: boolean;
    showTotalValue?: boolean;
    isSelectionMode?: boolean;
    selectedItemIds?: string[];
    dragPreviewItem?: WardrobeItem | null;
    batchSeriesName?: string;
    batchImageUris?: string[];
    isBatchImporting?: boolean;
    depositViewMode?: string;
    selectedDepositYear?: number;
    selectedDepositMonth?: number;
    selectedSeriesKey?: string;
    isDepositSelectorExpanded?: boolean;
    showDepositTotal?: boolean;
    showDepositYearStats?: boolean;
    depositDisplayMode?: string;
    currentSort?: WardrobeSortOption;
    currentLayout?: WardrobeViewLayout;
    filterState?: WardrobeFilterState;
    showSheet?: boolean;
    activeSheet?: string;
    navPathStack?: NavPathStack;
    onOpenHouse?: (destination: string) => void;
}
import type common from "@ohos:app.ability.common";
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import { AppSymbol, AppSymbolName } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppSymbols";
import { GlassCard } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/GlassComponents";
import { WardrobeImageStore } from "@bundle:com.pinkhouse.harmony/entry/ets/core/media/WardrobeImageStore";
import { AppLogger } from "@bundle:com.pinkhouse.harmony/entry/ets/core/utils/AppLogger";
import { RdbWardrobeRepository } from "@bundle:com.pinkhouse.harmony/entry/ets/data/repository/RdbWardrobeRepository";
import { wardrobePreferences } from "@bundle:com.pinkhouse.harmony/entry/ets/data/preferences/WardrobePreferences";
import { totalBalance, totalDeposit, WardrobeCategory } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/model/WardrobeItem";
import type { NewWardrobeItem, WardrobeItem } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/model/WardrobeItem";
import { WardrobeSortOption, DefaultSortOption, DefaultViewLayout, createDefaultFilter } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/model/WardrobeListOptions";
import type { WardrobeViewLayout, WardrobeFilterState } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/model/WardrobeListOptions";
import { SeriesAnalyzer } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/service/SeriesAnalyzer";
import type { SeriesGroup } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/service/SeriesAnalyzer";
import { AddSampleWardrobeItemUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/AddSampleWardrobeItemUseCase";
import { BatchSoftDeleteWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/BatchSoftDeleteWardrobeItemsUseCase";
import { GetDepositPlansUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/GetDepositPlansUseCase";
import { GetWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/GetWardrobeItemsUseCase";
import { ReorderWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/ReorderWardrobeItemsUseCase";
import { SearchWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/SearchWardrobeItemsUseCase";
import { SoftDeleteWardrobeItemUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/SoftDeleteWardrobeItemUseCase";
import { ClothingEditPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/ClothingEditPage";
import type { ClothingDraft } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/ClothingEditPage";
import { WardrobeItemDetailPage, WardrobeDetailArgs } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/WardrobeItemDetailPage";
import { SortSheet } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/toolbar/SortSheet";
import { ViewLayoutSheet } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/toolbar/ViewLayoutSheet";
import { FilterSheet } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/toolbar/FilterSheet";
const DEPOSIT_MONTHS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
export class WardrobePage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__items = new ObservedPropertyObjectPU([], this, "items");
        this.__depositItems = new ObservedPropertyObjectPU([], this, "depositItems");
        this.__searchKeyword = new ObservedPropertySimplePU('', this, "searchKeyword");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.__selectedSegment = new SynchedPropertySimpleTwoWayPU(params.selectedSegment, this, "selectedSegment");
        this.__showCount = new ObservedPropertySimplePU(true, this, "showCount");
        this.__showDressValue = new ObservedPropertySimplePU(false, this, "showDressValue");
        this.__showTotalValue = new ObservedPropertySimplePU(false, this, "showTotalValue");
        this.__isSelectionMode = new ObservedPropertySimplePU(false, this, "isSelectionMode");
        this.__selectedItemIds = new ObservedPropertyObjectPU([], this, "selectedItemIds");
        this.__dragPreviewItem = new ObservedPropertyObjectPU(null, this, "dragPreviewItem");
        this.__batchSeriesName = new ObservedPropertySimplePU('', this, "batchSeriesName");
        this.__batchImageUris = new ObservedPropertyObjectPU([], this, "batchImageUris");
        this.__isBatchImporting = new ObservedPropertySimplePU(false, this, "isBatchImporting");
        this.__depositViewMode = new ObservedPropertySimplePU('monthly', this, "depositViewMode");
        this.__selectedDepositYear = new ObservedPropertySimplePU(new Date().getFullYear(), this, "selectedDepositYear");
        this.__selectedDepositMonth = new ObservedPropertySimplePU(0, this, "selectedDepositMonth");
        this.__selectedSeriesKey = new ObservedPropertySimplePU('', this, "selectedSeriesKey");
        this.__isDepositSelectorExpanded = new ObservedPropertySimplePU(false, this, "isDepositSelectorExpanded");
        this.__showDepositTotal = new ObservedPropertySimplePU(false, this, "showDepositTotal");
        this.__showDepositYearStats = new ObservedPropertySimplePU(false, this, "showDepositYearStats");
        this.__depositDisplayMode = new ObservedPropertySimplePU('detail', this, "depositDisplayMode");
        this.__currentSort = new ObservedPropertySimplePU(DefaultSortOption, this, "currentSort");
        this.__currentLayout = new ObservedPropertySimplePU(DefaultViewLayout, this, "currentLayout");
        this.__filterState = new ObservedPropertyObjectPU(createDefaultFilter(), this, "filterState");
        this.__showSheet = new ObservedPropertySimplePU(false, this, "showSheet");
        this.__activeSheet = new ObservedPropertySimplePU('', this, "activeSheet");
        this.navPathStack = new NavPathStack();
        this.onOpenHouse = () => { };
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WardrobePage_Params) {
        if (params.items !== undefined) {
            this.items = params.items;
        }
        if (params.depositItems !== undefined) {
            this.depositItems = params.depositItems;
        }
        if (params.searchKeyword !== undefined) {
            this.searchKeyword = params.searchKeyword;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
        if (params.showCount !== undefined) {
            this.showCount = params.showCount;
        }
        if (params.showDressValue !== undefined) {
            this.showDressValue = params.showDressValue;
        }
        if (params.showTotalValue !== undefined) {
            this.showTotalValue = params.showTotalValue;
        }
        if (params.isSelectionMode !== undefined) {
            this.isSelectionMode = params.isSelectionMode;
        }
        if (params.selectedItemIds !== undefined) {
            this.selectedItemIds = params.selectedItemIds;
        }
        if (params.dragPreviewItem !== undefined) {
            this.dragPreviewItem = params.dragPreviewItem;
        }
        if (params.batchSeriesName !== undefined) {
            this.batchSeriesName = params.batchSeriesName;
        }
        if (params.batchImageUris !== undefined) {
            this.batchImageUris = params.batchImageUris;
        }
        if (params.isBatchImporting !== undefined) {
            this.isBatchImporting = params.isBatchImporting;
        }
        if (params.depositViewMode !== undefined) {
            this.depositViewMode = params.depositViewMode;
        }
        if (params.selectedDepositYear !== undefined) {
            this.selectedDepositYear = params.selectedDepositYear;
        }
        if (params.selectedDepositMonth !== undefined) {
            this.selectedDepositMonth = params.selectedDepositMonth;
        }
        if (params.selectedSeriesKey !== undefined) {
            this.selectedSeriesKey = params.selectedSeriesKey;
        }
        if (params.isDepositSelectorExpanded !== undefined) {
            this.isDepositSelectorExpanded = params.isDepositSelectorExpanded;
        }
        if (params.showDepositTotal !== undefined) {
            this.showDepositTotal = params.showDepositTotal;
        }
        if (params.showDepositYearStats !== undefined) {
            this.showDepositYearStats = params.showDepositYearStats;
        }
        if (params.depositDisplayMode !== undefined) {
            this.depositDisplayMode = params.depositDisplayMode;
        }
        if (params.currentSort !== undefined) {
            this.currentSort = params.currentSort;
        }
        if (params.currentLayout !== undefined) {
            this.currentLayout = params.currentLayout;
        }
        if (params.filterState !== undefined) {
            this.filterState = params.filterState;
        }
        if (params.showSheet !== undefined) {
            this.showSheet = params.showSheet;
        }
        if (params.activeSheet !== undefined) {
            this.activeSheet = params.activeSheet;
        }
        if (params.navPathStack !== undefined) {
            this.navPathStack = params.navPathStack;
        }
        if (params.onOpenHouse !== undefined) {
            this.onOpenHouse = params.onOpenHouse;
        }
    }
    updateStateVars(params: WardrobePage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__items.purgeDependencyOnElmtId(rmElmtId);
        this.__depositItems.purgeDependencyOnElmtId(rmElmtId);
        this.__searchKeyword.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedSegment.purgeDependencyOnElmtId(rmElmtId);
        this.__showCount.purgeDependencyOnElmtId(rmElmtId);
        this.__showDressValue.purgeDependencyOnElmtId(rmElmtId);
        this.__showTotalValue.purgeDependencyOnElmtId(rmElmtId);
        this.__isSelectionMode.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedItemIds.purgeDependencyOnElmtId(rmElmtId);
        this.__dragPreviewItem.purgeDependencyOnElmtId(rmElmtId);
        this.__batchSeriesName.purgeDependencyOnElmtId(rmElmtId);
        this.__batchImageUris.purgeDependencyOnElmtId(rmElmtId);
        this.__isBatchImporting.purgeDependencyOnElmtId(rmElmtId);
        this.__depositViewMode.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedDepositYear.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedDepositMonth.purgeDependencyOnElmtId(rmElmtId);
        this.__selectedSeriesKey.purgeDependencyOnElmtId(rmElmtId);
        this.__isDepositSelectorExpanded.purgeDependencyOnElmtId(rmElmtId);
        this.__showDepositTotal.purgeDependencyOnElmtId(rmElmtId);
        this.__showDepositYearStats.purgeDependencyOnElmtId(rmElmtId);
        this.__depositDisplayMode.purgeDependencyOnElmtId(rmElmtId);
        this.__currentSort.purgeDependencyOnElmtId(rmElmtId);
        this.__currentLayout.purgeDependencyOnElmtId(rmElmtId);
        this.__filterState.purgeDependencyOnElmtId(rmElmtId);
        this.__showSheet.purgeDependencyOnElmtId(rmElmtId);
        this.__activeSheet.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__items.aboutToBeDeleted();
        this.__depositItems.aboutToBeDeleted();
        this.__searchKeyword.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        this.__selectedSegment.aboutToBeDeleted();
        this.__showCount.aboutToBeDeleted();
        this.__showDressValue.aboutToBeDeleted();
        this.__showTotalValue.aboutToBeDeleted();
        this.__isSelectionMode.aboutToBeDeleted();
        this.__selectedItemIds.aboutToBeDeleted();
        this.__dragPreviewItem.aboutToBeDeleted();
        this.__batchSeriesName.aboutToBeDeleted();
        this.__batchImageUris.aboutToBeDeleted();
        this.__isBatchImporting.aboutToBeDeleted();
        this.__depositViewMode.aboutToBeDeleted();
        this.__selectedDepositYear.aboutToBeDeleted();
        this.__selectedDepositMonth.aboutToBeDeleted();
        this.__selectedSeriesKey.aboutToBeDeleted();
        this.__isDepositSelectorExpanded.aboutToBeDeleted();
        this.__showDepositTotal.aboutToBeDeleted();
        this.__showDepositYearStats.aboutToBeDeleted();
        this.__depositDisplayMode.aboutToBeDeleted();
        this.__currentSort.aboutToBeDeleted();
        this.__currentLayout.aboutToBeDeleted();
        this.__filterState.aboutToBeDeleted();
        this.__showSheet.aboutToBeDeleted();
        this.__activeSheet.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __items: ObservedPropertyObjectPU<WardrobeItem[]>;
    get items() {
        return this.__items.get();
    }
    set items(newValue: WardrobeItem[]) {
        this.__items.set(newValue);
    }
    private __depositItems: ObservedPropertyObjectPU<WardrobeItem[]>;
    get depositItems() {
        return this.__depositItems.get();
    }
    set depositItems(newValue: WardrobeItem[]) {
        this.__depositItems.set(newValue);
    }
    private __searchKeyword: ObservedPropertySimplePU<string>;
    get searchKeyword() {
        return this.__searchKeyword.get();
    }
    set searchKeyword(newValue: string) {
        this.__searchKeyword.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __errorMessage: ObservedPropertySimplePU<string>;
    get errorMessage() {
        return this.__errorMessage.get();
    }
    set errorMessage(newValue: string) {
        this.__errorMessage.set(newValue);
    }
    private __selectedSegment: SynchedPropertySimpleTwoWayPU<string>;
    get selectedSegment() {
        return this.__selectedSegment.get();
    }
    set selectedSegment(newValue: string) {
        this.__selectedSegment.set(newValue);
    }
    private __showCount: ObservedPropertySimplePU<boolean>;
    get showCount() {
        return this.__showCount.get();
    }
    set showCount(newValue: boolean) {
        this.__showCount.set(newValue);
    }
    private __showDressValue: ObservedPropertySimplePU<boolean>;
    get showDressValue() {
        return this.__showDressValue.get();
    }
    set showDressValue(newValue: boolean) {
        this.__showDressValue.set(newValue);
    }
    private __showTotalValue: ObservedPropertySimplePU<boolean>;
    get showTotalValue() {
        return this.__showTotalValue.get();
    }
    set showTotalValue(newValue: boolean) {
        this.__showTotalValue.set(newValue);
    }
    private __isSelectionMode: ObservedPropertySimplePU<boolean>;
    get isSelectionMode() {
        return this.__isSelectionMode.get();
    }
    set isSelectionMode(newValue: boolean) {
        this.__isSelectionMode.set(newValue);
    }
    private __selectedItemIds: ObservedPropertyObjectPU<string[]>;
    get selectedItemIds() {
        return this.__selectedItemIds.get();
    }
    set selectedItemIds(newValue: string[]) {
        this.__selectedItemIds.set(newValue);
    }
    private __dragPreviewItem: ObservedPropertyObjectPU<WardrobeItem | null>;
    get dragPreviewItem() {
        return this.__dragPreviewItem.get();
    }
    set dragPreviewItem(newValue: WardrobeItem | null) {
        this.__dragPreviewItem.set(newValue);
    }
    // 批量导入 的临时草稿
    private __batchSeriesName: ObservedPropertySimplePU<string>;
    get batchSeriesName() {
        return this.__batchSeriesName.get();
    }
    set batchSeriesName(newValue: string) {
        this.__batchSeriesName.set(newValue);
    }
    private __batchImageUris: ObservedPropertyObjectPU<string[]>;
    get batchImageUris() {
        return this.__batchImageUris.get();
    }
    set batchImageUris(newValue: string[]) {
        this.__batchImageUris.set(newValue);
    }
    private __isBatchImporting: ObservedPropertySimplePU<boolean>;
    get isBatchImporting() {
        return this.__isBatchImporting.get();
    }
    set isBatchImporting(newValue: boolean) {
        this.__isBatchImporting.set(newValue);
    }
    private __depositViewMode: ObservedPropertySimplePU<string>;
    get depositViewMode() {
        return this.__depositViewMode.get();
    }
    set depositViewMode(newValue: string) {
        this.__depositViewMode.set(newValue);
    }
    private __selectedDepositYear: ObservedPropertySimplePU<number>;
    get selectedDepositYear() {
        return this.__selectedDepositYear.get();
    }
    set selectedDepositYear(newValue: number) {
        this.__selectedDepositYear.set(newValue);
    }
    private __selectedDepositMonth: ObservedPropertySimplePU<number>;
    get selectedDepositMonth() {
        return this.__selectedDepositMonth.get();
    }
    set selectedDepositMonth(newValue: number) {
        this.__selectedDepositMonth.set(newValue);
    }
    private __selectedSeriesKey: ObservedPropertySimplePU<string>;
    get selectedSeriesKey() {
        return this.__selectedSeriesKey.get();
    }
    set selectedSeriesKey(newValue: string) {
        this.__selectedSeriesKey.set(newValue);
    }
    private __isDepositSelectorExpanded: ObservedPropertySimplePU<boolean>;
    get isDepositSelectorExpanded() {
        return this.__isDepositSelectorExpanded.get();
    }
    set isDepositSelectorExpanded(newValue: boolean) {
        this.__isDepositSelectorExpanded.set(newValue);
    }
    private __showDepositTotal: ObservedPropertySimplePU<boolean>;
    get showDepositTotal() {
        return this.__showDepositTotal.get();
    }
    set showDepositTotal(newValue: boolean) {
        this.__showDepositTotal.set(newValue);
    }
    private __showDepositYearStats: ObservedPropertySimplePU<boolean>;
    get showDepositYearStats() {
        return this.__showDepositYearStats.get();
    }
    set showDepositYearStats(newValue: boolean) {
        this.__showDepositYearStats.set(newValue);
    }
    private __depositDisplayMode: ObservedPropertySimplePU<string>;
    get depositDisplayMode() {
        return this.__depositDisplayMode.get();
    }
    set depositDisplayMode(newValue: string) {
        this.__depositDisplayMode.set(newValue);
    }
    private __currentSort: ObservedPropertySimplePU<WardrobeSortOption>;
    get currentSort() {
        return this.__currentSort.get();
    }
    set currentSort(newValue: WardrobeSortOption) {
        this.__currentSort.set(newValue);
    }
    private __currentLayout: ObservedPropertySimplePU<WardrobeViewLayout>;
    get currentLayout() {
        return this.__currentLayout.get();
    }
    set currentLayout(newValue: WardrobeViewLayout) {
        this.__currentLayout.set(newValue);
    }
    private __filterState: ObservedPropertyObjectPU<WardrobeFilterState>;
    get filterState() {
        return this.__filterState.get();
    }
    set filterState(newValue: WardrobeFilterState) {
        this.__filterState.set(newValue);
    }
    private __showSheet: ObservedPropertySimplePU<boolean>;
    get showSheet() {
        return this.__showSheet.get();
    }
    set showSheet(newValue: boolean) {
        this.__showSheet.set(newValue);
    }
    private __activeSheet: ObservedPropertySimplePU<string>;
    get activeSheet() {
        return this.__activeSheet.get();
    }
    set activeSheet(newValue: string) {
        this.__activeSheet.set(newValue);
    }
    private navPathStack: NavPathStack;
    private onOpenHouse: (destination: string) => void;
    aboutToAppear(): void {
        this.loadItems();
        this.loadPreferences();
    }
    private async loadPreferences(): Promise<void> {
        try {
            const ctx = getContext(this) as common.Context;
            this.currentSort = await wardrobePreferences.getSortOption(ctx);
            this.currentLayout = await wardrobePreferences.getViewLayout(ctx);
        }
        catch (_e) {
            // use defaults
        }
    }
    private formatCurrency(value: number): string {
        return '¥' + Math.round(value).toString();
    }
    private computeDressValue(): number {
        let sum = 0;
        for (let i = 0; i < this.items.length; i++) {
            if (this.items[i].category.indexOf('裙') >= 0 || this.items[i].category.indexOf('Dress') >= 0) {
                sum += this.items[i].price;
            }
        }
        return sum > 0 ? sum : this.computeTotalValue();
    }
    private computeTotalValue(): number {
        let sum = 0;
        for (let i = 0; i < this.items.length; i++) {
            sum += this.items[i].price;
        }
        return sum;
    }
    private depositTotalBalance(): number {
        let sum = 0;
        for (let i = 0; i < this.depositItems.length; i++) {
            sum += totalBalance(this.depositItems[i]);
        }
        return sum;
    }
    private depositYearItems(): WardrobeItem[] {
        const output: WardrobeItem[] = [];
        for (let i = 0; i < this.depositItems.length; i++) {
            const item = this.depositItems[i];
            if (item.finalPaymentDate === null) {
                continue;
            }
            const year = new Date(item.finalPaymentDate).getFullYear();
            if (year === this.selectedDepositYear) {
                output.push(item);
            }
        }
        return output;
    }
    private recentDepositMonth(): number {
        const months: number[] = [];
        const nowMonth = new Date().getMonth() + 1;
        const yearItems = this.depositYearItems();
        for (let i = 0; i < yearItems.length; i++) {
            const item = yearItems[i];
            if (item.finalPaymentDate !== null) {
                months.push(new Date(item.finalPaymentDate).getMonth() + 1);
            }
        }
        months.sort((a: number, b: number) => a - b);
        for (let i = 0; i < months.length; i++) {
            if (months[i] >= nowMonth) {
                return months[i];
            }
        }
        if (months.length > 0) {
            return months[months.length - 1];
        }
        return nowMonth;
    }
    private monthStats(month: number): DepositStats {
        let count = 0;
        let amount = 0;
        const yearItems = this.depositYearItems();
        for (let i = 0; i < yearItems.length; i++) {
            const item = yearItems[i];
            if (item.finalPaymentDate === null) {
                continue;
            }
            if (new Date(item.finalPaymentDate).getMonth() + 1 === month) {
                count += item.stock;
                amount += totalBalance(item);
            }
        }
        return new DepositStats(count, amount);
    }
    private depositVisibleItems(): WardrobeItem[] {
        let result = this.depositYearItems();
        const keyword = this.searchKeyword.trim();
        if (keyword.length > 0) {
            result = result.filter((item: WardrobeItem) => {
                return item.name.indexOf(keyword) >= 0 ||
                    item.brandName.indexOf(keyword) >= 0 ||
                    item.types.indexOf(keyword) >= 0;
            });
        }
        if (this.depositViewMode === 'monthly') {
            const targetMonth = this.isDepositSelectorExpanded
                ? this.selectedDepositMonth
                : this.recentDepositMonth();
            if (targetMonth > 0) {
                result = result.filter((item: WardrobeItem) => {
                    return item.finalPaymentDate !== null &&
                        new Date(item.finalPaymentDate).getMonth() + 1 === targetMonth;
                });
            }
            return result;
        }
        if (!this.isDepositSelectorExpanded) {
            const oneMonthAgo = Date.now() - 30 * 24 * 60 * 60 * 1000;
            return result.filter((item: WardrobeItem) => item.createdAt >= oneMonthAgo);
        }
        if (this.selectedSeriesKey.length === 0) {
            return result;
        }
        const series = SeriesAnalyzer.group(result);
        let selectedIds: string[] = [];
        for (let i = 0; i < series.length; i++) {
            if (series[i].seriesKey === this.selectedSeriesKey) {
                selectedIds = series[i].itemIds;
                break;
            }
        }
        return result.filter((item: WardrobeItem) => selectedIds.indexOf(item.id) >= 0);
    }
    private visibleDepositStats(): DepositStats {
        const items = this.depositVisibleItems();
        let count = 0;
        let amount = 0;
        for (let i = 0; i < items.length; i++) {
            count += items[i].stock;
            amount += totalBalance(items[i]);
        }
        return new DepositStats(count, amount);
    }
    private depositSeriesGroups(): SeriesGroup[] {
        return SeriesAnalyzer.group(this.depositYearItems());
    }
    private formatDepositDate(value: number | null): string {
        if (value === null) {
            return '待定';
        }
        const date = new Date(value);
        return `${date.getMonth() + 1}月`;
    }
    private RoundButton(symbolName: string, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.width(40);
            Stack.height(40);
            Stack.onClick(onTap);
        }, Stack);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textPrimary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 242, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 20,
                            color: AppTheme.color.textPrimary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textPrimary
                    });
                }
            }, { name: "AppSymbol" });
        }
        Stack.pop();
    }
    private RoundButtonWithMenu(symbolName: string, items: MenuElement[], parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.width(40);
            Stack.height(40);
            Stack.onClick(() => {
                AppLogger.info(`[TopBar] menu button tapped: ${symbolName}, items=${items.length}`);
            });
            Stack.bindMenu(items);
        }, Stack);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textPrimary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 256, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 20,
                            color: AppTheme.color.textPrimary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textPrimary
                    });
                }
            }, { name: "AppSymbol" });
        }
        Stack.pop();
    }
    private ModeButton(key: string, symbolName: string, label: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width(58);
            Column.height(54);
            Column.justifyContent(FlexAlign.Center);
            Column.onClick(() => {
                this.selectedSegment = key;
                this.exitSelectionMode();
            });
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 24,
                        color: this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textTertiary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 273, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 24,
                            color: this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textTertiary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 24,
                        color: this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textTertiary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontWeight(this.selectedSegment === key ? FontWeight.Bold : FontWeight.Medium);
            Text.fontColor(this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textSecondary);
            Text.maxLines(1);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private openSheet(type: string): void {
        AppLogger.info(`[Sheet] openSheet: type=${type}, showSheet was=${this.showSheet}`);
        if (this.showSheet) {
            this.showSheet = false;
            setTimeout(() => {
                this.activeSheet = type;
                this.showSheet = true;
                AppLogger.info(`[Sheet] delayed open: activeSheet=${this.activeSheet}`);
            }, 100);
        }
        else {
            this.activeSheet = type;
            this.showSheet = true;
            AppLogger.info(`[Sheet] direct open: activeSheet=${this.activeSheet}`);
        }
    }
    private TopBar(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
            Row.padding({
                left: AppTheme.spacing.page,
                right: AppTheme.spacing.page,
                top: 8,
                bottom: 8
            });
            Row.backgroundColor(Color.Transparent);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isSelectionMode) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.SelectionTopBarContent.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.DefaultTopBarContent.bind(this)();
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    private DefaultTopBarContent(parent = null) {
        this.ModeButton.bind(this)('wardrobe', AppSymbolName.Wardrobe, '少女衣橱');
        this.ModeButton.bind(this)('deposit', AppSymbolName.Deposit, '心愿尾款');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.RoundButton.bind(this)(AppSymbolName.Sort, () => {
            AppLogger.info('[TopBar] sort button tapped');
            this.openSheet('sort');
        });
        this.RoundButton.bind(this)(AppSymbolName.Filter, () => {
            AppLogger.info('[TopBar] filter button tapped');
            this.openSheet('filter');
        });
        this.RoundButton.bind(this)(AppSymbolName.Grid, () => {
            AppLogger.info('[TopBar] layout button tapped');
            this.openSheet('layout');
        });
        this.RoundButtonWithMenu.bind(this)(AppSymbolName.More, [
            { value: '搜索', action: () => { AppLogger.info('[MoreMenu] 搜索 tapped'); } },
            {
                value: '编辑',
                action: () => {
                    AppLogger.info('[MoreMenu] 编辑 tapped');
                    this.enterSelectionMode(false);
                }
            },
            {
                value: '调整顺序',
                action: () => {
                    AppLogger.info('[MoreMenu] 调整顺序 tapped');
                    this.enterSelectionMode(true);
                }
            }
        ]);
        this.RoundButtonWithMenu.bind(this)(AppSymbolName.Add, [
            {
                value: '手动创建',
                action: () => {
                    AppLogger.info('[AddMenu] 手动创建 tapped → openSheet(create)');
                    this.openSheet('create');
                }
            },
            {
                value: '批量导入',
                action: () => {
                    AppLogger.info('[AddMenu] 批量导入 tapped → openSheet(batchImport)');
                    this.openSheet('batchImport');
                }
            }
        ]);
    }
    private SelectionTopBarContent(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('完成');
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 4, right: 12, top: 6, bottom: 6 });
            Text.onClick(() => { this.exitSelectionMode(); });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`已选 ${this.selectedItemIds.length} / ${this.items.length}`);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.isAllSelected() ? '取消全选' : '全选');
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 12, right: 4, top: 6, bottom: 6 });
            Text.onClick(() => { this.toggleSelectAll(); });
        }, Text);
        Text.pop();
    }
    private enterSelectionMode(forceCustomSort: boolean): void {
        if (forceCustomSort && this.currentSort !== WardrobeSortOption.Custom) {
            this.currentSort = WardrobeSortOption.Custom;
            this.persistSortOption();
            this.loadItems();
        }
        this.isSelectionMode = true;
        this.selectedItemIds = [];
    }
    private exitSelectionMode(): void {
        this.isSelectionMode = false;
        this.selectedItemIds = [];
    }
    private isAllSelected(): boolean {
        return this.items.length > 0 && this.selectedItemIds.length === this.items.length;
    }
    private isItemSelected(id: string): boolean {
        return this.selectedItemIds.indexOf(id) >= 0;
    }
    private toggleItemSelection(id: string): void {
        const idx = this.selectedItemIds.indexOf(id);
        if (idx >= 0) {
            const next = this.selectedItemIds.slice();
            next.splice(idx, 1);
            this.selectedItemIds = next;
        }
        else {
            this.selectedItemIds = this.selectedItemIds.concat([id]);
        }
    }
    private toggleSelectAll(): void {
        if (this.isAllSelected()) {
            this.selectedItemIds = [];
        }
        else {
            const ids: string[] = [];
            for (let i = 0; i < this.items.length; i++) {
                ids.push(this.items[i].id);
            }
            this.selectedItemIds = ids;
        }
    }
    private async batchDeleteSelected(): Promise<void> {
        if (this.selectedItemIds.length === 0) {
            return;
        }
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new BatchSoftDeleteWardrobeItemsUseCase(repository);
            await useCase.execute(this.selectedItemIds);
            this.exitSelectionMode();
            await this.loadItems();
        }
        catch (error) {
            this.handleError('batch delete wardrobe items failed', error);
        }
    }
    private async persistCustomOrder(orderedIds: string[]): Promise<void> {
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new ReorderWardrobeItemsUseCase(repository);
            await useCase.execute(orderedIds);
            AppLogger.info(`[Reorder] persisted ${orderedIds.length} ids`);
        }
        catch (error) {
            this.handleError('reorder wardrobe items failed', error);
        }
    }
    // ────────── 手动创建 Sheet ──────────
    private async saveClothingDraft(draft: ClothingDraft): Promise<void> {
        const name = draft.draftName.trim();
        AppLogger.info(`[Create] save draft tapped, name="${name}", category=${draft.draftCategory}, image=${draft.draftImageUri}`);
        if (name.length === 0) {
            AppLogger.warn('[Create] save aborted: empty name');
            return;
        }
        const noteParts: string[] = [];
        if (draft.draftAccessories.trim().length > 0) {
            noteParts.push(`小物：${draft.draftAccessories.trim()}`);
        }
        if (draft.draftNote.trim().length > 0) {
            noteParts.push(draft.draftNote.trim());
        }
        const item: NewWardrobeItem = {
            name: name,
            category: draft.draftCategory.length > 0 ? draft.draftCategory : WardrobeCategory.Dress,
            imageUri: draft.draftImageUri,
            price: draft.draftPrice,
            brandName: draft.draftBrand,
            types: draft.draftTypes,
            colors: draft.draftColors,
            sizes: draft.draftSizes,
            length: draft.draftLength,
            condition: draft.draftCondition,
            note: noteParts.join('\n'),
            originalPrice: draft.draftOriginalPrice,
            deposit: draft.draftDeposit,
            balance: draft.draftBalance,
            accessoriesPrice: draft.draftAccessoriesPrice,
            stock: draft.draftStock,
            purchasedAt: draft.draftPurchasedAt,
            depositDate: draft.draftDepositDate > 0 ? draft.draftDepositDate : null,
            isDepositPlan: draft.draftIsDepositPlan,
            finalPaymentDate: draft.draftFinalPaymentDate > 0 ? draft.draftFinalPaymentDate : null,
            finalPaymentEndDate: draft.draftFinalPaymentEndDate > 0 ? draft.draftFinalPaymentEndDate : null
        };
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const saved = await repository.addItem(item);
            AppLogger.info(`[Create] saved id=${saved.id}, image=${saved.imageUri}`);
            this.showSheet = false;
            await this.loadItems();
        }
        catch (error) {
            this.handleError('save manual clothing draft failed', error);
        }
    }
    // ────────── 批量导入 Sheet ──────────
    private async pickMultipleImages(): Promise<void> {
        AppLogger.info('[BatchImport] add images tapped');
        try {
            const pickedUris = await WardrobeImageStore.pickImages(20);
            AppLogger.info(`[BatchImport] picker returned=${pickedUris.length}`);
            this.batchImageUris = this.batchImageUris.concat(pickedUris);
            AppLogger.info(`[Picker] multi total now=${this.batchImageUris.length}`);
        }
        catch (error) {
            AppLogger.error(`[BatchImport] picker failed: ${JSON.stringify(error)}`);
        }
    }
    private removeBatchImage(index: number): void {
        AppLogger.info(`[BatchImport] remove index=${index}`);
        const next = this.batchImageUris.slice();
        next.splice(index, 1);
        this.batchImageUris = next;
    }
    private async confirmBatchImport(): Promise<void> {
        AppLogger.info(`[BatchImport] confirm tapped, count=${this.batchImageUris.length}, series="${this.batchSeriesName}"`);
        if (this.batchImageUris.length === 0 || this.isBatchImporting) {
            return;
        }
        const seriesName = this.batchSeriesName.trim().length > 0 ? this.batchSeriesName.trim() : '导入';
        this.isBatchImporting = true;
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const ctx = getContext(this) as common.Context;
            let successCount = 0;
            const failedUris: string[] = [];
            for (let i = 0; i < this.batchImageUris.length; i++) {
                try {
                    const storedUri = await WardrobeImageStore.persistPickedImage(ctx, this.batchImageUris[i]);
                    await repository.addItem({
                        name: `${seriesName} ${i + 1}`,
                        category: WardrobeCategory.Dress,
                        imageUri: storedUri,
                        purchasedAt: Date.now()
                    });
                    successCount++;
                }
                catch (error) {
                    failedUris.push(this.batchImageUris[i]);
                    AppLogger.error(`[BatchImport] item ${i} failed: ${JSON.stringify(error)}`);
                }
            }
            AppLogger.info(`[BatchImport] saved ${successCount}/${this.batchImageUris.length}`);
            this.batchImageUris = failedUris;
            if (failedUris.length === 0) {
                this.batchSeriesName = '';
                this.showSheet = false;
            }
            else {
                this.errorMessage = `批量导入成功 ${successCount} 张，失败 ${failedUris.length} 张`;
            }
            await this.loadItems();
        }
        catch (error) {
            this.handleError('batch import failed', error);
        }
        finally {
            this.isBatchImporting = false;
        }
    }
    private BatchImportSheet(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.padding(20);
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('取消');
            Text.fontSize(AppTheme.font.body);
            Text.fontColor(AppTheme.color.primary);
            Text.onClick(() => {
                AppLogger.info('[BatchImport] cancel tapped');
                this.batchImageUris = [];
                this.batchSeriesName = '';
                this.showSheet = false;
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('批量导入');
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('完成');
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.batchImageUris.length > 0 && !this.isBatchImporting ? AppTheme.color.primary : AppTheme.color.textTertiary);
            Text.onClick(() => { this.confirmBatchImport(); });
        }, Text);
        Text.pop();
        Row.pop();
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('基础信息');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                TextInput.create({ placeholder: '系列名称', text: this.batchSeriesName });
                                TextInput.height(46);
                                TextInput.fontSize(AppTheme.font.body);
                                TextInput.backgroundColor(AppTheme.color.surfaceTint);
                                TextInput.borderRadius(AppTheme.radius.chip);
                                TextInput.onChange((v: string) => { this.batchSeriesName = v; });
                            }, TextInput);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('每张图片将作为一个独立的裙装条目。裙装名称将设置为“系列名称 + 序号”。');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontColor(AppTheme.color.textSecondary);
                                Text.lineHeight(18);
                            }, Text);
                            Text.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 629, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 16,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('基础信息');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    TextInput.create({ placeholder: '系列名称', text: this.batchSeriesName });
                                    TextInput.height(46);
                                    TextInput.fontSize(AppTheme.font.body);
                                    TextInput.backgroundColor(AppTheme.color.surfaceTint);
                                    TextInput.borderRadius(AppTheme.radius.chip);
                                    TextInput.onChange((v: string) => { this.batchSeriesName = v; });
                                }, TextInput);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('每张图片将作为一个独立的裙装条目。裙装名称将设置为“系列名称 + 序号”。');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                    Text.lineHeight(18);
                                }, Text);
                                Text.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 12 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(`选择图片 (${this.batchImageUris.length} 张)`);
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Blank.create();
                                Blank.layoutWeight(1);
                            }, Blank);
                            Blank.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('添加图片');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.primary);
                                Text.padding({ left: 12, right: 12, top: 8, bottom: 8 });
                                Text.backgroundColor(AppTheme.color.primaryPale);
                                Text.borderRadius(AppTheme.radius.pill);
                                Text.onClick(() => { this.pickMultipleImages(); });
                            }, Text);
                            Text.pop();
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                If.create();
                                if (this.batchImageUris.length > 0) {
                                    this.ifElseBranchUpdateFunction(0, () => {
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Grid.create();
                                            Grid.columnsTemplate('1fr 1fr 1fr');
                                            Grid.columnsGap(6);
                                            Grid.rowsGap(6);
                                            Grid.width('100%');
                                        }, Grid);
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            ForEach.create();
                                            const forEachItemGenFunction = (_item, index?: number) => {
                                                const uri = _item;
                                                {
                                                    const itemCreation2 = (elmtId, isInitialRender) => {
                                                        GridItem.create(() => { }, false);
                                                    };
                                                    const observedDeepRender = () => {
                                                        this.observeComponentCreation2(itemCreation2, GridItem);
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            Stack.create({ alignContent: Alignment.TopEnd });
                                                        }, Stack);
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            Image.create(uri);
                                                            Image.width('100%');
                                                            Image.aspectRatio(1);
                                                            Image.borderRadius(AppTheme.radius.card);
                                                            Image.objectFit(ImageFit.Cover);
                                                        }, Image);
                                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                            Text.create('×');
                                                            Text.fontSize(14);
                                                            Text.fontColor(Color.White);
                                                            Text.width(22);
                                                            Text.height(22);
                                                            Text.textAlign(TextAlign.Center);
                                                            Text.backgroundColor('rgba(0,0,0,0.55)');
                                                            Text.borderRadius(11);
                                                            Text.margin({ top: 4, right: 4 });
                                                            Text.onClick(() => { this.removeBatchImage(index ?? 0); });
                                                        }, Text);
                                                        Text.pop();
                                                        Stack.pop();
                                                        GridItem.pop();
                                                    };
                                                    observedDeepRender();
                                                }
                                            };
                                            this.forEachUpdateFunction(elmtId, this.batchImageUris, forEachItemGenFunction, (uri: string, index?: number) => `${index}-${uri}`, true, true);
                                        }, ForEach);
                                        ForEach.pop();
                                        Grid.pop();
                                    });
                                }
                                else {
                                    this.ifElseBranchUpdateFunction(1, () => {
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create('+ 添加图片');
                                            Text.fontSize(AppTheme.font.body);
                                            Text.fontWeight(FontWeight.Bold);
                                            Text.fontColor(AppTheme.color.primary);
                                            Text.width('100%');
                                            Text.height(110);
                                            Text.textAlign(TextAlign.Center);
                                            Text.backgroundColor(AppTheme.color.primaryPale);
                                            Text.borderRadius(AppTheme.radius.card);
                                            Text.border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border });
                                            Text.onClick(() => { this.pickMultipleImages(); });
                                        }, Text);
                                        Text.pop();
                                    });
                                }
                            }, If);
                            If.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 652, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 16,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 12 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                }, Row);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(`选择图片 (${this.batchImageUris.length} 张)`);
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Blank.create();
                                    Blank.layoutWeight(1);
                                }, Blank);
                                Blank.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('添加图片');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.primary);
                                    Text.padding({ left: 12, right: 12, top: 8, bottom: 8 });
                                    Text.backgroundColor(AppTheme.color.primaryPale);
                                    Text.borderRadius(AppTheme.radius.pill);
                                    Text.onClick(() => { this.pickMultipleImages(); });
                                }, Text);
                                Text.pop();
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    If.create();
                                    if (this.batchImageUris.length > 0) {
                                        this.ifElseBranchUpdateFunction(0, () => {
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Grid.create();
                                                Grid.columnsTemplate('1fr 1fr 1fr');
                                                Grid.columnsGap(6);
                                                Grid.rowsGap(6);
                                                Grid.width('100%');
                                            }, Grid);
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                ForEach.create();
                                                const forEachItemGenFunction = (_item, index?: number) => {
                                                    const uri = _item;
                                                    {
                                                        const itemCreation2 = (elmtId, isInitialRender) => {
                                                            GridItem.create(() => { }, false);
                                                        };
                                                        const observedDeepRender = () => {
                                                            this.observeComponentCreation2(itemCreation2, GridItem);
                                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                Stack.create({ alignContent: Alignment.TopEnd });
                                                            }, Stack);
                                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                Image.create(uri);
                                                                Image.width('100%');
                                                                Image.aspectRatio(1);
                                                                Image.borderRadius(AppTheme.radius.card);
                                                                Image.objectFit(ImageFit.Cover);
                                                            }, Image);
                                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                                Text.create('×');
                                                                Text.fontSize(14);
                                                                Text.fontColor(Color.White);
                                                                Text.width(22);
                                                                Text.height(22);
                                                                Text.textAlign(TextAlign.Center);
                                                                Text.backgroundColor('rgba(0,0,0,0.55)');
                                                                Text.borderRadius(11);
                                                                Text.margin({ top: 4, right: 4 });
                                                                Text.onClick(() => { this.removeBatchImage(index ?? 0); });
                                                            }, Text);
                                                            Text.pop();
                                                            Stack.pop();
                                                            GridItem.pop();
                                                        };
                                                        observedDeepRender();
                                                    }
                                                };
                                                this.forEachUpdateFunction(elmtId, this.batchImageUris, forEachItemGenFunction, (uri: string, index?: number) => `${index}-${uri}`, true, true);
                                            }, ForEach);
                                            ForEach.pop();
                                            Grid.pop();
                                        });
                                    }
                                    else {
                                        this.ifElseBranchUpdateFunction(1, () => {
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Text.create('+ 添加图片');
                                                Text.fontSize(AppTheme.font.body);
                                                Text.fontWeight(FontWeight.Bold);
                                                Text.fontColor(AppTheme.color.primary);
                                                Text.width('100%');
                                                Text.height(110);
                                                Text.textAlign(TextAlign.Center);
                                                Text.backgroundColor(AppTheme.color.primaryPale);
                                                Text.borderRadius(AppTheme.radius.card);
                                                Text.border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border });
                                                Text.onClick(() => { this.pickMultipleImages(); });
                                            }, Text);
                                            Text.pop();
                                        });
                                    }
                                }, If);
                                If.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.isBatchImporting ? '正在导入...' : `确认导入 ${this.batchImageUris.length}`);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textOnPrimary);
            Text.width('100%');
            Text.height(46);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(this.batchImageUris.length > 0 && !this.isBatchImporting ? AppTheme.color.primary : AppTheme.color.textTertiary);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => { this.confirmBatchImport(); });
        }, Text);
        Text.pop();
        Column.pop();
    }
    private VisibilityButton(visible: boolean, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(visible ? '眼' : '隐');
            Text.fontSize(10);
            Text.fontColor(AppTheme.color.textTertiary);
            Text.width(22);
            Text.height(18);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(AppTheme.color.surfaceTint);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(onTap);
        }, Text);
        Text.pop();
    }
    private StatCol(title: string, value: string, visible: boolean, onToggle: () => void, valueColor: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Center);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 5 });
            Row.height(18);
            Row.justifyContent(FlexAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(AppTheme.font.caption);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.VisibilityButton.bind(this)(visible, onToggle);
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(visible ? value : '****');
            Text.fontSize(AppTheme.font.titleLarge);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(valueColor);
            Text.height(32);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private StatsRow(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.StatCol.bind(this)('总件数/款', `${this.items.length}/${this.items.length}`, this.showCount, () => { this.showCount = !this.showCount; }, AppTheme.color.textPrimary);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.vertical(true);
            Divider.strokeWidth(1);
            Divider.color(AppTheme.color.border);
            Divider.height(48);
        }, Divider);
        this.StatCol.bind(this)('裙装价值', this.formatCurrency(this.computeDressValue()), this.showDressValue, () => { this.showDressValue = !this.showDressValue; }, AppTheme.color.accentWarm);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.vertical(true);
            Divider.strokeWidth(1);
            Divider.color(AppTheme.color.border);
            Divider.height(48);
        }, Divider);
        this.StatCol.bind(this)('总价值', this.formatCurrency(this.computeTotalValue()), this.showTotalValue, () => { this.showTotalValue = !this.showTotalValue; }, AppTheme.color.textPrimary);
        Row.pop();
    }
    private QuickTile(symbolName: string, label: string, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.layoutWeight(1);
            Column.height(92);
            Column.justifyContent(FlexAlign.Center);
            Column.alignItems(HorizontalAlign.Center);
            Column.linearGradient({
                angle: 135,
                colors: [
                    [AppTheme.color.primaryPale, 0.0],
                    ['rgba(255, 255, 255, 0.50)', 1.0]
                ]
            });
            Column.borderRadius(AppTheme.radius.tile);
            Column.onClick(onTap);
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 34,
                        color: AppTheme.color.primary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 813, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 34,
                            color: AppTheme.color.primary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 34,
                        color: AppTheme.color.primary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private SummaryPanel(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 14 });
                                Column.width('100%');
                            }, Column);
                            this.StatsRow.bind(this)();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 12 });
                                Row.width('100%');
                            }, Row);
                            this.QuickTile.bind(this)(AppSymbolName.Spark, '今日穿搭色', () => { });
                            this.QuickTile.bind(this)(AppSymbolName.Outfit, '穿搭手帐', () => {
                                this.onOpenHouse('ootd');
                            });
                            this.QuickTile.bind(this)(AppSymbolName.Stats, '详细统计', () => { });
                            Row.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 840, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 14,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 14 });
                                    Column.width('100%');
                                }, Column);
                                this.StatsRow.bind(this)();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create({ space: 12 });
                                    Row.width('100%');
                                }, Row);
                                this.QuickTile.bind(this)(AppSymbolName.Spark, '今日穿搭色', () => { });
                                this.QuickTile.bind(this)(AppSymbolName.Outfit, '穿搭手帐', () => {
                                    this.onOpenHouse('ootd');
                                });
                                this.QuickTile.bind(this)(AppSymbolName.Stats, '详细统计', () => { });
                                Row.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private SearchField(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '搜索名称、品牌、标签...', text: this.searchKeyword });
            TextInput.height(46);
            TextInput.fontSize(AppTheme.font.body);
            TextInput.placeholderColor(AppTheme.color.textTertiary);
            TextInput.fontColor(AppTheme.color.textPrimary);
            TextInput.backgroundColor(AppTheme.color.overlayGlassStrong);
            TextInput.backgroundBlurStyle(BlurStyle.Thin);
            TextInput.borderRadius(AppTheme.radius.pill);
            TextInput.layoutWeight(1);
            TextInput.onChange((value: string) => {
                this.searchKeyword = value;
                this.searchItems();
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('示例');
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textOnPrimary);
            Text.padding({ left: 16, right: 16, top: 13, bottom: 13 });
            Text.backgroundColor(AppTheme.color.primary);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => {
                this.addSampleItem();
            });
        }, Text);
        Text.pop();
        Row.pop();
    }
    private ContentArea(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.selectedSegment === 'deposit') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.DepositPanel.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.ItemGrid.bind(this)();
                });
            }
        }, If);
        If.pop();
    }
    private DepositPanel(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 12 });
            Column.width('100%');
        }, Column);
        this.TotalDepositCard.bind(this)();
        this.DepositDisplayModeToggle.bind(this)();
        this.DepositModeTabs.bind(this)();
        this.DepositSelector.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.LoadingState.bind(this)();
                });
            }
            else if (this.depositVisibleItems().length === 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.DepositEmptyState.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                If.create();
                                if (this.depositDisplayMode === 'simple') {
                                    this.ifElseBranchUpdateFunction(0, () => {
                                        this.SimpleDepositRow.bind(this)(item);
                                    });
                                }
                                else {
                                    this.ifElseBranchUpdateFunction(1, () => {
                                        this.DepositRow.bind(this)(item);
                                    });
                                }
                            }, If);
                            If.pop();
                        };
                        this.forEachUpdateFunction(elmtId, this.depositVisibleItems(), forEachItemGenFunction, (item: WardrobeItem) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    private DepositDisplayModeToggle(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 6 });
            Row.padding({ left: 10, right: 10, top: 5, bottom: 5 });
            Row.backgroundColor(AppTheme.color.overlayGlassStrong);
            Row.borderRadius(AppTheme.radius.pill);
            Row.border({ width: 1, color: AppTheme.color.border });
            Row.onClick(() => {
                this.depositDisplayMode = this.depositDisplayMode === 'detail' ? 'simple' : 'detail';
            });
        }, Row);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: this.depositDisplayMode === 'detail' ? AppSymbolName.Grid : AppSymbolName.Sort,
                        iconSize: 16,
                        color: AppTheme.color.textSecondary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 927, col: 9 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: this.depositDisplayMode === 'detail' ? AppSymbolName.Grid : AppSymbolName.Sort,
                            iconSize: 16,
                            color: AppTheme.color.textSecondary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: this.depositDisplayMode === 'detail' ? AppSymbolName.Grid : AppSymbolName.Sort,
                        iconSize: 16,
                        color: AppTheme.color.textSecondary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.depositDisplayMode === 'detail' ? '详情' : '简略');
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Row.pop();
        Row.pop();
    }
    private TotalDepositCard(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 0, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 0 });
                                Column.width('100%');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 0 });
                                Row.width('100%');
                                Row.padding({ top: 12, bottom: 8 });
                            }, Row);
                            this.DepositShortcut.bind(this)('梦裙日历', AppSymbolName.Calendar, () => {
                                this.onOpenHouse('calendar');
                            });
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Divider.create();
                                Divider.vertical(true);
                                Divider.strokeWidth(1);
                                Divider.color(AppTheme.color.border);
                                Divider.height(34);
                            }, Divider);
                            this.DepositShortcut.bind(this)('马上来财', AppSymbolName.Wealth, () => {
                                this.onOpenHouse('wealth');
                            });
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Divider.create();
                                Divider.vertical(true);
                                Divider.strokeWidth(1);
                                Divider.color(AppTheme.color.border);
                                Divider.height(34);
                            }, Divider);
                            this.DepositShortcut.bind(this)('尾款提醒', AppSymbolName.Reminder, () => { });
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Divider.create();
                                Divider.strokeWidth(1);
                                Divider.color(AppTheme.color.border);
                                Divider.margin({ left: 18, right: 18 });
                            }, Divider);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                                Row.padding({ left: 18, right: 18, top: 12, bottom: this.showDepositTotal ? 4 : 14 });
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('总待付尾款');
                                Text.fontSize(AppTheme.font.body);
                                Text.fontWeight(FontWeight.Medium);
                                Text.fontColor(AppTheme.color.textSecondary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Blank.create();
                            }, Blank);
                            Blank.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.showDepositTotal ? '隐藏' : '显示');
                                Text.fontSize(AppTheme.font.tiny);
                                Text.fontColor(AppTheme.color.primary);
                                Text.padding({ left: 11, right: 11, top: 6, bottom: 6 });
                                Text.backgroundColor(AppTheme.color.primaryPale);
                                Text.borderRadius(AppTheme.radius.pill);
                                Text.onClick(() => {
                                    if (!this.showDepositTotal) {
                                        AlertDialog.show({
                                            title: '真的要解锁"钱包瘦身"副本吗？',
                                            message: '⚠️ 前方尾款大军已集结！\n温馨提示：看完请抱紧你的钱包，深呼吸是没用的，不如默念"美貌无价"！\n(｡•́ω•̀｡)',
                                            primaryButton: {
                                                value: '取消',
                                                action: () => { }
                                            },
                                            secondaryButton: {
                                                value: '我准备好了！',
                                                action: () => {
                                                    this.showDepositTotal = true;
                                                }
                                            }
                                        });
                                    }
                                    else {
                                        this.showDepositTotal = false;
                                    }
                                });
                            }, Text);
                            Text.pop();
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                If.create();
                                if (this.showDepositTotal) {
                                    this.ifElseBranchUpdateFunction(0, () => {
                                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                                            Text.create(this.formatCurrency(this.depositTotalBalance()));
                                            Text.fontSize(AppTheme.font.displayMedium);
                                            Text.fontWeight(FontWeight.Bold);
                                            Text.fontColor(AppTheme.color.primary);
                                            Text.width('100%');
                                            Text.textAlign(TextAlign.Center);
                                            Text.padding({ bottom: 16 });
                                        }, Text);
                                        Text.pop();
                                    });
                                }
                                else {
                                    this.ifElseBranchUpdateFunction(1, () => {
                                    });
                                }
                            }, If);
                            If.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 949, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 0,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 0 });
                                    Column.width('100%');
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create({ space: 0 });
                                    Row.width('100%');
                                    Row.padding({ top: 12, bottom: 8 });
                                }, Row);
                                this.DepositShortcut.bind(this)('梦裙日历', AppSymbolName.Calendar, () => {
                                    this.onOpenHouse('calendar');
                                });
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Divider.create();
                                    Divider.vertical(true);
                                    Divider.strokeWidth(1);
                                    Divider.color(AppTheme.color.border);
                                    Divider.height(34);
                                }, Divider);
                                this.DepositShortcut.bind(this)('马上来财', AppSymbolName.Wealth, () => {
                                    this.onOpenHouse('wealth');
                                });
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Divider.create();
                                    Divider.vertical(true);
                                    Divider.strokeWidth(1);
                                    Divider.color(AppTheme.color.border);
                                    Divider.height(34);
                                }, Divider);
                                this.DepositShortcut.bind(this)('尾款提醒', AppSymbolName.Reminder, () => { });
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Divider.create();
                                    Divider.strokeWidth(1);
                                    Divider.color(AppTheme.color.border);
                                    Divider.margin({ left: 18, right: 18 });
                                }, Divider);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                    Row.padding({ left: 18, right: 18, top: 12, bottom: this.showDepositTotal ? 4 : 14 });
                                }, Row);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('总待付尾款');
                                    Text.fontSize(AppTheme.font.body);
                                    Text.fontWeight(FontWeight.Medium);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Blank.create();
                                }, Blank);
                                Blank.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.showDepositTotal ? '隐藏' : '显示');
                                    Text.fontSize(AppTheme.font.tiny);
                                    Text.fontColor(AppTheme.color.primary);
                                    Text.padding({ left: 11, right: 11, top: 6, bottom: 6 });
                                    Text.backgroundColor(AppTheme.color.primaryPale);
                                    Text.borderRadius(AppTheme.radius.pill);
                                    Text.onClick(() => {
                                        if (!this.showDepositTotal) {
                                            AlertDialog.show({
                                                title: '真的要解锁"钱包瘦身"副本吗？',
                                                message: '⚠️ 前方尾款大军已集结！\n温馨提示：看完请抱紧你的钱包，深呼吸是没用的，不如默念"美貌无价"！\n(｡•́ω•̀｡)',
                                                primaryButton: {
                                                    value: '取消',
                                                    action: () => { }
                                                },
                                                secondaryButton: {
                                                    value: '我准备好了！',
                                                    action: () => {
                                                        this.showDepositTotal = true;
                                                    }
                                                }
                                            });
                                        }
                                        else {
                                            this.showDepositTotal = false;
                                        }
                                    });
                                }, Text);
                                Text.pop();
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    If.create();
                                    if (this.showDepositTotal) {
                                        this.ifElseBranchUpdateFunction(0, () => {
                                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                                Text.create(this.formatCurrency(this.depositTotalBalance()));
                                                Text.fontSize(AppTheme.font.displayMedium);
                                                Text.fontWeight(FontWeight.Bold);
                                                Text.fontColor(AppTheme.color.primary);
                                                Text.width('100%');
                                                Text.textAlign(TextAlign.Center);
                                                Text.padding({ bottom: 16 });
                                            }, Text);
                                            Text.pop();
                                        });
                                    }
                                    else {
                                        this.ifElseBranchUpdateFunction(1, () => {
                                        });
                                    }
                                }, If);
                                If.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 0, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private DepositShortcut(title: string, symbolName: string, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.layoutWeight(1);
            Column.height(58);
            Column.justifyContent(FlexAlign.Center);
            Column.onClick(onTap);
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 23,
                        color: AppTheme.color.primary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1020, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 23,
                            color: AppTheme.color.primary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 23,
                        color: AppTheme.color.primary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private DepositModeTabs(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 0 });
            Row.width('100%');
            Row.padding(4);
            Row.backgroundColor(AppTheme.color.overlayGlass);
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.borderRadius(AppTheme.radius.pill);
            Row.border({ width: 1, color: AppTheme.color.border });
        }, Row);
        this.DepositModeButton.bind(this)('monthly', '按月视图');
        this.DepositModeButton.bind(this)('series', '按系列视图');
        Row.pop();
    }
    private DepositModeButton(key: string, label: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(this.depositViewMode === key ? FontWeight.Bold : FontWeight.Medium);
            Text.fontColor(this.depositViewMode === key ? AppTheme.color.textPrimary : AppTheme.color.textSecondary);
            Text.layoutWeight(1);
            Text.height(44);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(this.depositViewMode === key ? AppTheme.color.surfaceGlass : Color.Transparent);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => {
                this.depositViewMode = key;
                this.selectedDepositMonth = 0;
                this.selectedSeriesKey = '';
                this.isDepositSelectorExpanded = key === 'series';
            });
        }, Text);
        Text.pop();
    }
    private DepositSelector(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.onClick(() => {
                this.isDepositSelectorExpanded = !this.isDepositSelectorExpanded;
            });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.depositViewMode === 'monthly'
                ? (this.isDepositSelectorExpanded ? '年度预估尾款 (点我折叠)' : '年度预估尾款 (点我展开)')
                : (this.isDepositSelectorExpanded ? '按系列预估尾款 (点我折叠)' : '按系列预估尾款 (点我展开)'));
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: this.isDepositSelectorExpanded ? AppSymbolName.Close : AppSymbolName.More,
                        iconSize: 18,
                        color: AppTheme.color.textTertiary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1080, col: 9 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: this.isDepositSelectorExpanded ? AppSymbolName.Close : AppSymbolName.More,
                            iconSize: 18,
                            color: AppTheme.color.textTertiary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: this.isDepositSelectorExpanded ? AppSymbolName.Close : AppSymbolName.More,
                        iconSize: 18,
                        color: AppTheme.color.textTertiary
                    });
                }
            }, { name: "AppSymbol" });
        }
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isDepositSelectorExpanded) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.DepositYearSwitcher.bind(this)();
                    this.DepositYearStats.bind(this)();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        If.create();
                        if (this.depositViewMode === 'monthly') {
                            this.ifElseBranchUpdateFunction(0, () => {
                                this.DepositMonthGrid.bind(this)();
                            });
                        }
                        else {
                            this.ifElseBranchUpdateFunction(1, () => {
                                this.DepositSeriesGrid.bind(this)();
                            });
                        }
                    }, If);
                    If.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.DepositRecentStats.bind(this)();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    private DepositYearSwitcher(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.height(48);
            Row.padding({ left: 8, right: 8 });
            Row.backgroundColor(AppTheme.color.overlayGlassStrong);
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.borderRadius(AppTheme.radius.card);
            Row.border({ width: 1, color: AppTheme.color.border });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.fontSize(26);
            Text.fontColor(AppTheme.color.textSecondary);
            Text.width(42);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => {
                this.selectedDepositYear -= 1;
                this.selectedDepositMonth = 0;
                this.selectedSeriesKey = '';
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.selectedDepositYear}年`);
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
            Text.layoutWeight(1);
            Text.textAlign(TextAlign.Center);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('›');
            Text.fontSize(26);
            Text.fontColor(AppTheme.color.textSecondary);
            Text.width(42);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => {
                this.selectedDepositYear += 1;
                this.selectedDepositMonth = 0;
                this.selectedSeriesKey = '';
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.showDepositYearStats ? '眼' : '隐');
            Text.fontSize(10);
            Text.fontColor(AppTheme.color.primary);
            Text.width(28);
            Text.height(26);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(AppTheme.color.primaryPale);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => {
                this.showDepositYearStats = !this.showDepositYearStats;
            });
        }, Text);
        Text.pop();
        Row.pop();
    }
    private DepositYearStats(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.card,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                            }, Row);
                            this.DepositStatColumn.bind(this)('待付件数', this.showDepositYearStats ? `${this.visibleDepositStats().count}` : '**', AppTheme.color.textPrimary);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Divider.create();
                                Divider.vertical(true);
                                Divider.strokeWidth(1);
                                Divider.color(AppTheme.color.border);
                                Divider.height(32);
                            }, Divider);
                            this.DepositStatColumn.bind(this)('待付尾款', this.showDepositYearStats ? this.formatCurrency(this.visibleDepositStats().amount) : '****', AppTheme.color.primary);
                            Row.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1158, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 14,
                            cornerRadius: AppTheme.radius.card,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                }, Row);
                                this.DepositStatColumn.bind(this)('待付件数', this.showDepositYearStats ? `${this.visibleDepositStats().count}` : '**', AppTheme.color.textPrimary);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Divider.create();
                                    Divider.vertical(true);
                                    Divider.strokeWidth(1);
                                    Divider.color(AppTheme.color.border);
                                    Divider.height(32);
                                }, Divider);
                                this.DepositStatColumn.bind(this)('待付尾款', this.showDepositYearStats ? this.formatCurrency(this.visibleDepositStats().amount) : '****', AppTheme.color.primary);
                                Row.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.card
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private DepositMonthGrid(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Grid.create();
            Grid.columnsTemplate('1fr 1fr 1fr 1fr');
            Grid.columnsGap(8);
            Grid.rowsGap(8);
            Grid.width('100%');
        }, Grid);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const month = _item;
                {
                    const itemCreation2 = (elmtId, isInitialRender) => {
                        GridItem.create(() => { }, false);
                    };
                    const observedDeepRender = () => {
                        this.observeComponentCreation2(itemCreation2, GridItem);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Column.create({ space: 4 });
                            Column.width('100%');
                            Column.height(58);
                            Column.justifyContent(FlexAlign.Center);
                            Column.backgroundColor(this.selectedDepositMonth === month ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong);
                            Column.backgroundBlurStyle(BlurStyle.Thin);
                            Column.borderRadius(AppTheme.radius.card);
                            Column.border({ width: 1, color: this.selectedDepositMonth === month ? Color.Transparent : AppTheme.color.border });
                            Column.onClick(() => {
                                this.selectedDepositMonth = this.selectedDepositMonth === month ? 0 : month;
                            });
                        }, Column);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Row.create({ space: 4 });
                            Row.justifyContent(FlexAlign.Center);
                        }, Row);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(`${month}月`);
                            Text.fontSize(AppTheme.font.caption);
                            Text.fontWeight(this.selectedDepositMonth === month ? FontWeight.Bold : FontWeight.Medium);
                            Text.fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary);
                        }, Text);
                        Text.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            If.create();
                            if (this.monthStats(month).count > 0) {
                                this.ifElseBranchUpdateFunction(0, () => {
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(`${this.monthStats(month).count}`);
                                        Text.fontSize(9);
                                        Text.fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.textSecondary);
                                        Text.padding({ left: 5, right: 5, top: 2, bottom: 2 });
                                        Text.backgroundColor(this.selectedDepositMonth === month ? 'rgba(255,255,255,0.24)' : AppTheme.color.surfaceTint);
                                        Text.borderRadius(AppTheme.radius.pill);
                                    }, Text);
                                    Text.pop();
                                });
                            }
                            else {
                                this.ifElseBranchUpdateFunction(1, () => {
                                });
                            }
                        }, If);
                        If.pop();
                        Row.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(this.monthStats(month).count > 0 ? this.formatCurrency(this.monthStats(month).amount) : '-');
                            Text.fontSize(AppTheme.font.tiny);
                            Text.fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.accentWarm);
                            Text.maxLines(1);
                        }, Text);
                        Text.pop();
                        Column.pop();
                        GridItem.pop();
                    };
                    observedDeepRender();
                }
            };
            this.forEachUpdateFunction(elmtId, DEPOSIT_MONTHS, forEachItemGenFunction, (month: number) => month.toString(), false, false);
        }, ForEach);
        ForEach.pop();
        Grid.pop();
    }
    private DepositSeriesGrid(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.depositSeriesGroups().length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('暂无系列数据');
                        Text.fontSize(AppTheme.font.caption);
                        Text.fontColor(AppTheme.color.textSecondary);
                        Text.width('100%');
                        Text.textAlign(TextAlign.Center);
                        Text.padding(18);
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Grid.create();
                        Grid.columnsTemplate('1fr 1fr');
                        Grid.columnsGap(8);
                        Grid.rowsGap(8);
                        Grid.width('100%');
                    }, Grid);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const group = _item;
                            {
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    GridItem.create(() => { }, false);
                                };
                                const observedDeepRender = () => {
                                    this.observeComponentCreation2(itemCreation2, GridItem);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 5 });
                                        Column.width('100%');
                                        Column.padding(10);
                                        Column.backgroundColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong);
                                        Column.backgroundBlurStyle(BlurStyle.Thin);
                                        Column.borderRadius(AppTheme.radius.card);
                                        Column.border({ width: 1, color: this.selectedSeriesKey === group.seriesKey ? Color.Transparent : AppTheme.color.border });
                                        Column.onClick(() => {
                                            this.selectedSeriesKey = this.selectedSeriesKey === group.seriesKey ? '' : group.seriesKey;
                                        });
                                    }, Column);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Row.create();
                                        Row.width('100%');
                                    }, Row);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(group.seriesKey);
                                        Text.fontSize(AppTheme.font.caption);
                                        Text.fontWeight(this.selectedSeriesKey === group.seriesKey ? FontWeight.Bold : FontWeight.Medium);
                                        Text.fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary);
                                        Text.maxLines(1);
                                        Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Blank.create();
                                    }, Blank);
                                    Blank.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(`${group.count}`);
                                        Text.fontSize(9);
                                        Text.fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.textSecondary);
                                    }, Text);
                                    Text.pop();
                                    Row.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(this.formatCurrency(group.totalBalance));
                                        Text.fontSize(AppTheme.font.tiny);
                                        Text.fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.accentWarm);
                                        Text.width('100%');
                                    }, Text);
                                    Text.pop();
                                    Column.pop();
                                    GridItem.pop();
                                };
                                observedDeepRender();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.depositSeriesGroups(), forEachItemGenFunction, (group: SeriesGroup) => group.seriesKey, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Grid.pop();
                });
            }
        }, If);
        If.pop();
    }
    private DepositRecentStats(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.card,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 12 });
                                Column.width('100%');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                            }, Row);
                            {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    if (isInitialRender) {
                                        let componentCall = new AppSymbol(this, {
                                            name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                            iconSize: 18,
                                            color: AppTheme.color.primary
                                        }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1278, col: 11 });
                                        ViewPU.create(componentCall);
                                        let paramsLambda = () => {
                                            return {
                                                name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                                iconSize: 18,
                                                color: AppTheme.color.primary
                                            };
                                        };
                                        componentCall.paramsGenerator_ = paramsLambda;
                                    }
                                    else {
                                        this.updateStateVarsOfChildByElmtId(elmtId, {
                                            name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                            iconSize: 18,
                                            color: AppTheme.color.primary
                                        });
                                    }
                                }, { name: "AppSymbol" });
                            }
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.depositViewMode === 'monthly' ? '最近月统计' : '最近添加');
                                Text.fontSize(AppTheme.font.body);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Blank.create();
                            }, Blank);
                            Blank.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.depositViewMode === 'monthly' ? `${this.recentDepositMonth()}月` : '一个月内');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textOnPrimary);
                                Text.padding({ left: 12, right: 12, top: 5, bottom: 5 });
                                Text.backgroundColor(AppTheme.color.primaryStrong);
                                Text.borderRadius(AppTheme.radius.pill);
                            }, Text);
                            Text.pop();
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                            }, Row);
                            this.DepositStatColumn.bind(this)('待付件数', `${this.visibleDepositStats().count}`, AppTheme.color.textPrimary);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Divider.create();
                                Divider.vertical(true);
                                Divider.strokeWidth(1);
                                Divider.color(AppTheme.color.border);
                                Divider.height(32);
                            }, Divider);
                            this.DepositStatColumn.bind(this)('待付尾款', this.formatCurrency(this.visibleDepositStats().amount), AppTheme.color.primary);
                            Row.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1275, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 14,
                            cornerRadius: AppTheme.radius.card,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 12 });
                                    Column.width('100%');
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                }, Row);
                                {
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        if (isInitialRender) {
                                            let componentCall = new AppSymbol(this, {
                                                name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                                iconSize: 18,
                                                color: AppTheme.color.primary
                                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1278, col: 11 });
                                            ViewPU.create(componentCall);
                                            let paramsLambda = () => {
                                                return {
                                                    name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                                    iconSize: 18,
                                                    color: AppTheme.color.primary
                                                };
                                            };
                                            componentCall.paramsGenerator_ = paramsLambda;
                                        }
                                        else {
                                            this.updateStateVarsOfChildByElmtId(elmtId, {
                                                name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
                                                iconSize: 18,
                                                color: AppTheme.color.primary
                                            });
                                        }
                                    }, { name: "AppSymbol" });
                                }
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.depositViewMode === 'monthly' ? '最近月统计' : '最近添加');
                                    Text.fontSize(AppTheme.font.body);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Blank.create();
                                }, Blank);
                                Blank.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.depositViewMode === 'monthly' ? `${this.recentDepositMonth()}月` : '一个月内');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textOnPrimary);
                                    Text.padding({ left: 12, right: 12, top: 5, bottom: 5 });
                                    Text.backgroundColor(AppTheme.color.primaryStrong);
                                    Text.borderRadius(AppTheme.radius.pill);
                                }, Text);
                                Text.pop();
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                }, Row);
                                this.DepositStatColumn.bind(this)('待付件数', `${this.visibleDepositStats().count}`, AppTheme.color.textPrimary);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Divider.create();
                                    Divider.vertical(true);
                                    Divider.strokeWidth(1);
                                    Divider.color(AppTheme.color.border);
                                    Divider.height(32);
                                }, Divider);
                                this.DepositStatColumn.bind(this)('待付尾款', this.formatCurrency(this.visibleDepositStats().amount), AppTheme.color.primary);
                                Row.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.card
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private DepositStatColumn(title: string, value: string, valueColor: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Center);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(AppTheme.font.caption);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(value);
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(valueColor);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private DepositEmptyState(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('暂无心愿尾款');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('添加带尾款时间的心愿裙装后，会在这里按月或系列汇总。');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontColor(AppTheme.color.textSecondary);
                            }, Text);
                            Text.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1326, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 24,
                            cornerRadius: AppTheme.radius.card,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('暂无心愿尾款');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('添加带尾款时间的心愿裙装后，会在这里按月或系列汇总。');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                }, Text);
                                Text.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private DepositRow(item: WardrobeItem, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.width('100%');
            Row.padding(14);
            Row.backgroundColor(AppTheme.color.overlayGlassStrong);
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.borderRadius(AppTheme.radius.card);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.width(54);
            Stack.height(54);
            Stack.backgroundColor(AppTheme.color.primaryPale);
            Stack.borderRadius(AppTheme.radius.tile);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.category.length > 0 ? item.category.substring(0, 1) : '衣');
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Stack.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.name);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`尾款: ${this.formatDepositDate(item.finalPaymentDate)}`);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 6, right: 6, top: 3, bottom: 3 });
            Text.backgroundColor(AppTheme.color.primaryPale);
            Text.borderRadius(AppTheme.radius.chip);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.brandName.length > 0 ? item.brandName : item.category);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.textSecondary);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 2 });
            Column.alignItems(HorizontalAlign.End);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('定金 ' + this.formatCurrency(totalDeposit(item)));
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.textTertiary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('尾款 ' + this.formatCurrency(totalBalance(item)));
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
    }
    private SimpleDepositRow(item: WardrobeItem, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.width('100%');
            Row.padding({ left: 14, right: 14, top: 10, bottom: 10 });
            Row.backgroundColor(AppTheme.color.overlayGlassStrong);
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.borderRadius(AppTheme.radius.card);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.name);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.textPrimary);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.formatDepositDate(item.finalPaymentDate));
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.formatCurrency(totalBalance(item)));
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Row.pop();
    }
    private ItemGrid(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.LoadingState.bind(this)();
                });
            }
            else if (this.errorMessage.length > 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.ErrorState.bind(this)();
                });
            }
            else if (this.items.length === 0) {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.EmptyState.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(3, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Grid.create();
                        Grid.columnsTemplate('1fr 1fr 1fr');
                        Grid.columnsGap(10);
                        Grid.rowsGap(18);
                        Grid.width('100%');
                        Grid.editMode(this.isSelectionMode && this.currentSort === WardrobeSortOption.Custom);
                        Grid.supportAnimation(true);
                        Grid.onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
                            AppLogger.info(`[Reorder] drag start index=${itemIndex}`);
                            this.dragPreviewItem = this.items[itemIndex];
                            return { builder: () => {
                                    this.DragPreview.call(this);
                                } };
                        });
                        Grid.onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
                            AppLogger.info(`[Reorder] drop from=${itemIndex} to=${insertIndex} ok=${isSuccess}`);
                            this.dragPreviewItem = null;
                            if (!isSuccess || itemIndex === insertIndex || insertIndex < 0) {
                                return;
                            }
                            this.handleReorderDrop(itemIndex, insertIndex);
                        });
                    }, Grid);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = (_item, index?: number) => {
                            const item = _item;
                            {
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    GridItem.create(() => { }, false);
                                };
                                const observedDeepRender = () => {
                                    this.observeComponentCreation2(itemCreation2, GridItem);
                                    this.ItemCard.bind(this)(item);
                                    GridItem.pop();
                                };
                                observedDeepRender();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.items, forEachItemGenFunction, (item: WardrobeItem) => item.id, true, false);
                    }, ForEach);
                    ForEach.pop();
                    Grid.pop();
                });
            }
        }, If);
        If.pop();
    }
    private DragPreview(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.shadow({ radius: 18, color: AppTheme.color.shadowSoft, offsetX: 0, offsetY: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.dragPreviewItem !== null && this.dragPreviewItem.imageUri.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Image.create(this.dragPreviewItem.imageUri);
                        Image.width(96);
                        Image.height(96);
                        Image.objectFit(ImageFit.Cover);
                        Image.borderRadius(AppTheme.radius.card);
                    }, Image);
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.dragPreviewItem !== null && this.dragPreviewItem.category.length > 0
                            ? this.dragPreviewItem.category.substring(0, 1)
                            : '衣');
                        Text.fontSize(28);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(AppTheme.color.primary);
                        Text.width(96);
                        Text.height(96);
                        Text.textAlign(TextAlign.Center);
                        Text.backgroundColor(AppTheme.color.primaryPale);
                        Text.borderRadius(AppTheme.radius.card);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    private handleReorderDrop(fromIdx: number, toIdx: number): void {
        const next = this.items.slice();
        if (fromIdx < 0 || fromIdx >= next.length) {
            return;
        }
        const moved = next.splice(fromIdx, 1)[0];
        const clamped = Math.max(0, Math.min(toIdx, next.length));
        next.splice(clamped, 0, moved);
        this.items = next;
        const orderedIds: string[] = [];
        for (let i = 0; i < next.length; i++) {
            orderedIds.push(next[i].id);
        }
        this.persistCustomOrder(orderedIds);
    }
    private ItemCard(item: WardrobeItem, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.width('100%');
            Column.padding(6);
            Column.backgroundColor(AppTheme.color.overlayGlass);
            Column.backgroundBlurStyle(BlurStyle.Thin);
            Column.borderRadius(AppTheme.radius.card);
            Column.border({
                width: this.isSelectionMode && this.isItemSelected(item.id) ? 2 : 1,
                color: this.isSelectionMode && this.isItemSelected(item.id)
                    ? AppTheme.color.primary
                    : AppTheme.color.border
            });
            Column.shadow({
                radius: 14,
                color: AppTheme.color.shadowSoft,
                offsetX: 0,
                offsetY: 6
            });
            Column.onClick(() => {
                if (this.isSelectionMode) {
                    AppLogger.info(`[ItemCard] selection toggle id=${item.id}`);
                    this.toggleItemSelection(item.id);
                }
                else {
                    AppLogger.info(`[ItemCard] open detail id=${item.id}, name=${item.name}`);
                    this.navPathStack.pushPathByName('wardrobeItemDetail', new WardrobeDetailArgs(item.name, item.category, item.price));
                }
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.TopEnd });
            Stack.width('100%');
            Stack.borderRadius(AppTheme.radius.card);
            Stack.clip(true);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 主视觉：优先显示图片，缺图时回退到分类首字
            if (item.imageUri.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Image.create(item.imageUri);
                        Image.width('100%');
                        Image.height(112);
                        Image.objectFit(ImageFit.Cover);
                        Image.alt({ "id": 16777224, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
                    }, Image);
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Stack.create();
                        Stack.width('100%');
                        Stack.height(112);
                        Stack.linearGradient({
                            angle: 150,
                            colors: [
                                [AppTheme.color.primaryPale, 0.0],
                                [AppTheme.color.surface, 0.45],
                                [AppTheme.color.primarySoft, 1.0]
                            ]
                        });
                    }, Stack);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(item.category.length > 0 ? item.category.substring(0, 1) : '衣');
                        Text.fontSize(32);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(AppTheme.color.primary);
                    }, Text);
                    Text.pop();
                    Stack.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 编辑模式：右上角勾选圈；非编辑模式：保留尾款小角标
            if (this.isSelectionMode) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.isItemSelected(item.id) ? '✓' : '');
                        Text.fontSize(14);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(Color.White);
                        Text.width(24);
                        Text.height(24);
                        Text.textAlign(TextAlign.Center);
                        Text.backgroundColor(this.isItemSelected(item.id)
                            ? AppTheme.color.primary
                            : 'rgba(255,255,255,0.65)');
                        Text.borderRadius(12);
                        Text.border({
                            width: 1.5,
                            color: this.isItemSelected(item.id) ? AppTheme.color.primary : AppTheme.color.border
                        });
                        Text.margin({ top: 8, right: 8 });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('心愿尾款');
                        Text.fontSize(AppTheme.font.tiny);
                        Text.fontColor(AppTheme.color.textOnPrimary);
                        Text.padding({ left: 10, right: 10, top: 5, bottom: 5 });
                        Text.backgroundColor('rgba(50, 35, 43, 0.68)');
                        Text.borderRadius(AppTheme.radius.chip);
                        Text.margin({ top: 10, right: 10 });
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Stack.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 5 });
            Column.alignItems(HorizontalAlign.Start);
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.name);
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`定金 ¥${Math.round(item.price * 0.4)}  尾款 ¥${Math.round(item.price * 0.6)}`);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.primary);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        Column.pop();
        Column.pop();
    }
    private LoadingState(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
            Column.padding(40);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            LoadingProgress.create();
            LoadingProgress.width(32);
            LoadingProgress.height(32);
            LoadingProgress.color(AppTheme.color.primary);
        }, LoadingProgress);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('正在读取衣橱...');
            Text.fontSize(AppTheme.font.caption);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private EmptyState(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('衣橱还空着呢～');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.searchKeyword.length > 0
                                    ? '没有找到匹配的衣物，换个关键词试试。'
                                    : '点右上角「+」手动创建，或批量导入相册图片来点亮你的第一件梦裙。');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontColor(AppTheme.color.textSecondary);
                            }, Text);
                            Text.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1630, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 24,
                            cornerRadius: AppTheme.radius.card,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('衣橱还空着呢～');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.searchKeyword.length > 0
                                        ? '没有找到匹配的衣物，换个关键词试试。'
                                        : '点右上角「+」手动创建，或批量导入相册图片来点亮你的第一件梦裙。');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                }, Text);
                                Text.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private ErrorState(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('衣橱读取失败');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.errorMessage);
                                Text.fontSize(AppTheme.font.tiny);
                                Text.fontColor(AppTheme.color.textSecondary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('重试');
                                Text.fontSize(AppTheme.font.caption);
                                Text.fontColor(AppTheme.color.textOnPrimary);
                                Text.padding({ left: 18, right: 18, top: 9, bottom: 9 });
                                Text.backgroundColor(AppTheme.color.primary);
                                Text.borderRadius(AppTheme.radius.pill);
                                Text.onClick(() => {
                                    this.loadItems();
                                });
                            }, Text);
                            Text.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1649, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 24,
                            cornerRadius: AppTheme.radius.card,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('衣橱读取失败');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.errorMessage);
                                    Text.fontSize(AppTheme.font.tiny);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('重试');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.fontColor(AppTheme.color.textOnPrimary);
                                    Text.padding({ left: 18, right: 18, top: 9, bottom: 9 });
                                    Text.backgroundColor(AppTheme.color.primary);
                                    Text.borderRadius(AppTheme.radius.pill);
                                    Text.onClick(() => {
                                        this.loadItems();
                                    });
                                }, Text);
                                Text.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 24, cornerRadius: AppTheme.radius.card
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private SheetContent(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.onAppear(() => {
                AppLogger.info(`[Sheet] onAppear: activeSheet=${this.activeSheet}`);
            });
            Column.onDisAppear(() => {
                AppLogger.info(`[Sheet] onDisAppear: activeSheet=${this.activeSheet}, showSheet=${this.showSheet}`);
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.activeSheet === 'sort') {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new SortSheet(this, {
                                    currentSort: this.__currentSort,
                                    onClose: () => {
                                        AppLogger.info('[Sheet] sort onClose');
                                        this.showSheet = false;
                                        this.persistSortOption();
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1677, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        currentSort: this.currentSort,
                                        onClose: () => {
                                            AppLogger.info('[Sheet] sort onClose');
                                            this.showSheet = false;
                                            this.persistSortOption();
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "SortSheet" });
                    }
                });
            }
            else if (this.activeSheet === 'layout') {
                this.ifElseBranchUpdateFunction(1, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new ViewLayoutSheet(this, {
                                    currentLayout: this.__currentLayout,
                                    onClose: () => {
                                        AppLogger.info('[Sheet] layout onClose');
                                        this.showSheet = false;
                                        this.persistViewLayout();
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1686, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        currentLayout: this.currentLayout,
                                        onClose: () => {
                                            AppLogger.info('[Sheet] layout onClose');
                                            this.showSheet = false;
                                            this.persistViewLayout();
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "ViewLayoutSheet" });
                    }
                });
            }
            else if (this.activeSheet === 'filter') {
                this.ifElseBranchUpdateFunction(2, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new FilterSheet(this, {
                                    filterState: this.__filterState,
                                    candidateTypes: this.collectUniqueValues('types'),
                                    candidateColors: this.collectUniqueValues('colors'),
                                    candidateSizes: this.collectUniqueValues('sizes'),
                                    candidateLengths: this.collectUniqueValues('length'),
                                    candidateConditions: this.collectUniqueValues('condition'),
                                    onClose: () => {
                                        AppLogger.info('[Sheet] filter onClose');
                                        this.showSheet = false;
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1695, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        filterState: this.filterState,
                                        candidateTypes: this.collectUniqueValues('types'),
                                        candidateColors: this.collectUniqueValues('colors'),
                                        candidateSizes: this.collectUniqueValues('sizes'),
                                        candidateLengths: this.collectUniqueValues('length'),
                                        candidateConditions: this.collectUniqueValues('condition'),
                                        onClose: () => {
                                            AppLogger.info('[Sheet] filter onClose');
                                            this.showSheet = false;
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {
                                    candidateTypes: this.collectUniqueValues('types'),
                                    candidateColors: this.collectUniqueValues('colors'),
                                    candidateSizes: this.collectUniqueValues('sizes'),
                                    candidateLengths: this.collectUniqueValues('length'),
                                    candidateConditions: this.collectUniqueValues('condition')
                                });
                            }
                        }, { name: "FilterSheet" });
                    }
                });
            }
            else if (this.activeSheet === 'create') {
                this.ifElseBranchUpdateFunction(3, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new ClothingEditPage(this, {
                                    onSave: (draft: ClothingDraft) => {
                                        this.saveClothingDraft(draft);
                                    },
                                    onCancel: () => {
                                        AppLogger.info('[Create] cancel tapped');
                                        this.showSheet = false;
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1708, col: 9 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        onSave: (draft: ClothingDraft) => {
                                            this.saveClothingDraft(draft);
                                        },
                                        onCancel: () => {
                                            AppLogger.info('[Create] cancel tapped');
                                            this.showSheet = false;
                                        }
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "ClothingEditPage" });
                    }
                });
            }
            else if (this.activeSheet === 'batchImport') {
                this.ifElseBranchUpdateFunction(4, () => {
                    this.BatchImportSheet.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(5, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('loading...');
                        Text.fontSize(AppTheme.font.body);
                        Text.fontColor(AppTheme.color.textTertiary);
                        Text.padding(40);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    private collectUniqueValues(field: string): string[] {
        const values: string[] = [];
        for (let i = 0; i < this.items.length; i++) {
            const item = this.items[i];
            let raw = '';
            if (field === 'types') {
                raw = item.types;
            }
            else if (field === 'colors') {
                raw = item.colors;
            }
            else if (field === 'sizes') {
                raw = item.sizes;
            }
            else if (field === 'length') {
                raw = item.length;
            }
            else if (field === 'condition') {
                raw = item.condition;
            }
            if (raw.length > 0 && values.indexOf(raw) < 0) {
                values.push(raw);
            }
        }
        return values;
    }
    private persistSortOption(): void {
        wardrobePreferences.setSortOption(getContext(this) as common.Context, this.currentSort);
    }
    private persistViewLayout(): void {
        wardrobePreferences.setViewLayout(getContext(this) as common.Context, this.currentLayout);
    }
    pageMap(name: string, param: object, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (name === 'wardrobeItemDetail') {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new WardrobeItemDetailPage(this, { args: param as WardrobeDetailArgs }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wardrobe/WardrobePage.ets", line: 1769, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        args: param as WardrobeDetailArgs
                                    };
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {
                                    args: param as WardrobeDetailArgs
                                });
                            }
                        }, { name: "WardrobeItemDetailPage" });
                    }
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
    }
    private SelectionBottomBar(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 16 });
            Row.width('100%');
            Row.padding({ left: 16, right: 16, top: 10, bottom: 14 });
            Row.backgroundColor(AppTheme.color.surface);
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.border({ width: { top: 1 }, color: AppTheme.color.border });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`批量删除 (${this.selectedItemIds.length})`);
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.selectedItemIds.length > 0 ? AppTheme.color.textOnPrimary : AppTheme.color.textTertiary);
            Text.layoutWeight(1);
            Text.height(46);
            Text.textAlign(TextAlign.Center);
            Text.backgroundColor(this.selectedItemIds.length > 0 ? AppTheme.color.primary : AppTheme.color.overlayGlassStrong);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => {
                AppLogger.info(`[Selection] batch delete tapped, count=${this.selectedItemIds.length}`);
                if (this.selectedItemIds.length === 0) {
                    return;
                }
                AlertDialog.show({
                    title: '确认删除所选衣物？',
                    message: `将移出衣橱 ${this.selectedItemIds.length} 件，可在回收站恢复。`,
                    primaryButton: { value: '取消', action: () => { } },
                    secondaryButton: {
                        value: '删除',
                        fontColor: AppTheme.color.primary,
                        action: () => { this.batchDeleteSelected(); }
                    }
                });
            });
        }, Text);
        Text.pop();
        Row.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Navigation.create(this.navPathStack, { moduleName: "entry", pagePath: "entry/src/main/ets/feature/wardrobe/WardrobePage", isUserCreateStack: true });
            Navigation.hideTitleBar(true);
            Navigation.mode(NavigationMode.Stack);
            Navigation.navDestination({ builder: this.pageMap.bind(this) });
            Navigation.bindSheet({ value: this.showSheet, changeEvent: newValue => { this.showSheet = newValue; } }, { builder: () => {
                    this.SheetContent.call(this);
                } }, {
                height: (this.activeSheet === 'filter' || this.activeSheet === 'batchImport') ? SheetSize.MEDIUM :
                    (this.activeSheet === 'create') ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
                dragBar: true,
                backgroundColor: AppTheme.color.backgroundLight,
                onDisappear: () => {
                    AppLogger.info(`[Sheet] bindSheet onDisappear: activeSheet=${this.activeSheet}`);
                    this.showSheet = false;
                }
            });
        }, Navigation);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Bottom });
            Stack.width('100%');
            Stack.height('100%');
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.TopBar.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.layoutWeight(1);
            Scroll.scrollBar(BarState.Off);
            Scroll.backgroundColor(Color.Transparent);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({
                left: AppTheme.spacing.page,
                right: AppTheme.spacing.page,
                top: 10,
                bottom: this.isSelectionMode ? 96 : 126
            });
        }, Column);
        this.SummaryPanel.bind(this)();
        this.ContentArea.bind(this)();
        Column.pop();
        Scroll.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isSelectionMode) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.SelectionBottomBar.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Stack.pop();
        Navigation.pop();
    }
    private async loadItems(): Promise<void> {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new GetWardrobeItemsUseCase(repository);
            this.items = await useCase.execute();
            await this.loadDepositItems(repository);
            this.searchKeyword = '';
        }
        catch (error) {
            this.handleError('load wardrobe items failed', error);
        }
        finally {
            this.isLoading = false;
        }
    }
    private async searchItems(): Promise<void> {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new SearchWardrobeItemsUseCase(repository);
            this.items = await useCase.execute(this.searchKeyword);
            await this.loadDepositItems(repository);
        }
        catch (error) {
            this.handleError('search wardrobe items failed', error);
        }
        finally {
            this.isLoading = false;
        }
    }
    private async addSampleItem(): Promise<void> {
        this.errorMessage = '';
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new AddSampleWardrobeItemUseCase(repository);
            await useCase.execute();
            await this.searchItems();
        }
        catch (error) {
            this.handleError('add sample wardrobe item failed', error);
        }
    }
    private async softDeleteItem(id: string): Promise<void> {
        this.errorMessage = '';
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new SoftDeleteWardrobeItemUseCase(repository);
            await useCase.execute(id);
            await this.searchItems();
        }
        catch (error) {
            this.handleError('soft delete wardrobe item failed', error);
        }
    }
    private handleError(message: string, error: Object): void {
        AppLogger.error(`${message}: ${JSON.stringify(error)}`);
        this.errorMessage = message;
    }
    private async loadDepositItems(repository: RdbWardrobeRepository): Promise<void> {
        const depositUseCase = new GetDepositPlansUseCase(repository);
        this.depositItems = await depositUseCase.executeAll();
        if (this.depositItems.length > 0 && this.selectedDepositMonth === 0) {
            this.selectedDepositMonth = this.recentDepositMonth();
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
class DepositStats {
    count: number;
    amount: number;
    constructor(count: number, amount: number) {
        this.count = count;
        this.amount = amount;
    }
}
