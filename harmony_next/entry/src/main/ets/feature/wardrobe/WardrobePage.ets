import common from '@ohos.app.ability.common';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';
import { WardrobeImageStore } from '../../core/media/WardrobeImageStore';
import { AppLogger } from '../../core/utils/AppLogger';
import { RdbWardrobeRepository } from '../../data/repository/RdbWardrobeRepository';
import { wardrobePreferences } from '../../data/preferences/WardrobePreferences';
import { NewWardrobeItem, totalBalance, totalDeposit, WardrobeCategory, WardrobeItem } from '../../domain/model/WardrobeItem';
import {
  WardrobeSortOption,
  WardrobeViewLayout,
  WardrobeFilterState,
  DefaultSortOption,
  DefaultViewLayout,
  createDefaultFilter,
  isFilterActive,
  countActiveFilters,
  viewLayoutColumnCount,
  isListMode
} from '../../domain/model/WardrobeListOptions';
import { SeriesAnalyzer, SeriesGroup } from '../../domain/service/SeriesAnalyzer';
import { AddSampleWardrobeItemUseCase } from '../../domain/usecase/AddSampleWardrobeItemUseCase';
import { BatchSoftDeleteWardrobeItemsUseCase } from '../../domain/usecase/BatchSoftDeleteWardrobeItemsUseCase';
import { GetDepositPlansUseCase } from '../../domain/usecase/GetDepositPlansUseCase';
import { GetWardrobeItemsUseCase } from '../../domain/usecase/GetWardrobeItemsUseCase';
import { ReorderWardrobeItemsUseCase } from '../../domain/usecase/ReorderWardrobeItemsUseCase';
import { SearchWardrobeItemsUseCase } from '../../domain/usecase/SearchWardrobeItemsUseCase';
import { SoftDeleteWardrobeItemUseCase } from '../../domain/usecase/SoftDeleteWardrobeItemUseCase';
import { ClothingDraft, ClothingEditPage } from './ClothingEditPage';
import { WardrobeItemDetailPage, WardrobeDetailArgs } from './WardrobeItemDetailPage';
import { SortSheet } from './toolbar/SortSheet';
import { ViewLayoutSheet } from './toolbar/ViewLayoutSheet';
import { FilterSheet } from './toolbar/FilterSheet';

const DEPOSIT_MONTHS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

@Component
export struct WardrobePage {
  @State private items: WardrobeItem[] = [];
  @State private depositItems: WardrobeItem[] = [];
  @State private searchKeyword: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @Link selectedSegment: string;
  @State private showCount: boolean = true;
  @State private showDressValue: boolean = false;
  @State private showTotalValue: boolean = false;
  @State private isSelectionMode: boolean = false;
  @State private selectedItemIds: string[] = [];
  @State private dragPreviewItem: WardrobeItem | null = null;

  // 批量导入 的临时草稿
  @State private batchSeriesName: string = '';
  @State private batchImageUris: string[] = [];
  @State private isBatchImporting: boolean = false;
  @State private depositViewMode: string = 'monthly';
  @State private selectedDepositYear: number = new Date().getFullYear();
  @State private selectedDepositMonth: number = 0;
  @State private selectedSeriesKey: string = '';
  @State private isDepositSelectorExpanded: boolean = false;
  @State private showDepositTotal: boolean = false;
  @State private showDepositYearStats: boolean = false;
  @State private depositDisplayMode: string = 'detail';
  @State private currentSort: WardrobeSortOption = DefaultSortOption;
  @State private currentLayout: WardrobeViewLayout = DefaultViewLayout;
  @State private filterState: WardrobeFilterState = createDefaultFilter();
  @State private showSheet: boolean = false;
  @State private activeSheet: string = '';

  private navPathStack: NavPathStack = new NavPathStack();
  onOpenHouse: (destination: string) => void = () => {};

  aboutToAppear(): void {
    this.loadItems();
    this.loadPreferences();
  }

  private async loadPreferences(): Promise<void> {
    try {
      const ctx = getContext(this) as common.Context;
      this.currentSort = await wardrobePreferences.getSortOption(ctx);
      this.currentLayout = await wardrobePreferences.getViewLayout(ctx);
    } catch (_e) {
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

  @Builder
  private RoundButton(symbolName: string, onTap: () => void) {
    Stack() {
      AppSymbol({
        name: symbolName,
        iconSize: 20,
        color: AppTheme.color.textPrimary
      })
    }
    .width(40)
    .height(40)
    .onClick(onTap)
  }

  @Builder
  private RoundButtonWithMenu(symbolName: string, items: MenuElement[]) {
    Stack() {
      AppSymbol({
        name: symbolName,
        iconSize: 20,
        color: AppTheme.color.textPrimary
      })
    }
    .width(40)
    .height(40)
    .onClick(() => {
      AppLogger.info(`[TopBar] menu button tapped: ${symbolName}, items=${items.length}`);
    })
    .bindMenu(items)
  }

  @Builder
  private ModeButton(key: string, symbolName: string, label: string) {
    Column({ space: 8 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 24,
        color: this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textTertiary
      })
      Text(label)
        .fontSize(AppTheme.font.tiny)
        .fontWeight(this.selectedSegment === key ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selectedSegment === key ? AppTheme.color.primary : AppTheme.color.textSecondary)
        .maxLines(1)
    }
    .width(58)
    .height(54)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectedSegment = key;
      this.exitSelectionMode();
    })
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
    } else {
      this.activeSheet = type;
      this.showSheet = true;
      AppLogger.info(`[Sheet] direct open: activeSheet=${this.activeSheet}`);
    }
  }

  @Builder
  private TopBar() {
    Row() {
      if (this.isSelectionMode) {
        this.SelectionTopBarContent();
      } else {
        this.DefaultTopBarContent();
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: AppTheme.spacing.page,
      right: AppTheme.spacing.page,
      top: 8,
      bottom: 8
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private DefaultTopBarContent() {
    this.ModeButton('wardrobe', AppSymbolName.Wardrobe, '少女衣橱');
    this.ModeButton('deposit', AppSymbolName.Deposit, '心愿尾款');

    Blank().layoutWeight(1)

    this.RoundButton(AppSymbolName.Sort, () => {
      AppLogger.info('[TopBar] sort button tapped');
      this.openSheet('sort');
    });
    this.RoundButton(AppSymbolName.Filter, () => {
      AppLogger.info('[TopBar] filter button tapped');
      this.openSheet('filter');
    });
    this.RoundButton(AppSymbolName.Grid, () => {
      AppLogger.info('[TopBar] layout button tapped');
      this.openSheet('layout');
    });
    this.RoundButtonWithMenu(AppSymbolName.More, [
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
    this.RoundButtonWithMenu(AppSymbolName.Add, [
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

  @Builder
  private SelectionTopBarContent() {
    Text('完成')
      .fontSize(AppTheme.font.body)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.color.primary)
      .padding({ left: 4, right: 12, top: 6, bottom: 6 })
      .onClick(() => { this.exitSelectionMode(); })

    Blank().layoutWeight(1)

    Text(`已选 ${this.selectedItemIds.length} / ${this.items.length}`)
      .fontSize(AppTheme.font.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.color.textPrimary)

    Blank().layoutWeight(1)

    Text(this.isAllSelected() ? '取消全选' : '全选')
      .fontSize(AppTheme.font.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.color.primary)
      .padding({ left: 12, right: 4, top: 6, bottom: 6 })
      .onClick(() => { this.toggleSelectAll(); })
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
    } else {
      this.selectedItemIds = this.selectedItemIds.concat([id]);
    }
  }

  private toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.selectedItemIds = [];
    } else {
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
    } catch (error) {
      this.handleError('batch delete wardrobe items failed', error);
    }
  }

  private async persistCustomOrder(orderedIds: string[]): Promise<void> {
    try {
      const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
      const useCase = new ReorderWardrobeItemsUseCase(repository);
      await useCase.execute(orderedIds);
      AppLogger.info(`[Reorder] persisted ${orderedIds.length} ids`);
    } catch (error) {
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
    } catch (error) {
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
    } catch (error) {
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
        } catch (error) {
          failedUris.push(this.batchImageUris[i]);
          AppLogger.error(`[BatchImport] item ${i} failed: ${JSON.stringify(error)}`);
        }
      }
      AppLogger.info(`[BatchImport] saved ${successCount}/${this.batchImageUris.length}`);
      this.batchImageUris = failedUris;
      if (failedUris.length === 0) {
        this.batchSeriesName = '';
        this.showSheet = false;
      } else {
        this.errorMessage = `批量导入成功 ${successCount} 张，失败 ${failedUris.length} 张`;
      }
      await this.loadItems();
    } catch (error) {
      this.handleError('batch import failed', error);
    } finally {
      this.isBatchImporting = false;
    }
  }

  @Builder
  private BatchImportSheet() {
    Column({ space: 16 }) {
      Row() {
        Text('取消')
          .fontSize(AppTheme.font.body)
          .fontColor(AppTheme.color.primary)
          .onClick(() => {
            AppLogger.info('[BatchImport] cancel tapped');
            this.batchImageUris = [];
            this.batchSeriesName = '';
            this.showSheet = false;
          })

        Blank().layoutWeight(1)

        Text('批量导入')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)

        Blank().layoutWeight(1)

        Text('完成')
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.batchImageUris.length > 0 && !this.isBatchImporting ? AppTheme.color.primary : AppTheme.color.textTertiary)
          .onClick(() => { this.confirmBatchImport(); })
      }
      .width('100%')

      GlassCard({ innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge }) {
        Column({ space: 10 }) {
          Text('基础信息')
            .fontSize(AppTheme.font.titleMedium)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textPrimary)

          TextInput({ placeholder: '系列名称', text: this.batchSeriesName })
            .height(46)
            .fontSize(AppTheme.font.body)
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.chip)
            .onChange((v: string) => { this.batchSeriesName = v; })

          Text('每张图片将作为一个独立的裙装条目。裙装名称将设置为“系列名称 + 序号”。')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)
            .lineHeight(18)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      GlassCard({ innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge }) {
        Column({ space: 12 }) {
          Row() {
            Text(`选择图片 (${this.batchImageUris.length} 张)`)
              .fontSize(AppTheme.font.titleMedium)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.textPrimary)
            Blank().layoutWeight(1)
            Text('添加图片')
              .fontSize(AppTheme.font.caption)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.primary)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(AppTheme.color.primaryPale)
              .borderRadius(AppTheme.radius.pill)
              .onClick(() => { this.pickMultipleImages(); })
          }
          .width('100%')

          if (this.batchImageUris.length > 0) {
            Grid() {
              ForEach(this.batchImageUris, (uri: string, index?: number) => {
                GridItem() {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(uri)
                      .width('100%')
                      .aspectRatio(1)
                      .borderRadius(AppTheme.radius.card)
                      .objectFit(ImageFit.Cover)
                    Text('×')
                      .fontSize(14)
                      .fontColor(Color.White)
                      .width(22)
                      .height(22)
                      .textAlign(TextAlign.Center)
                      .backgroundColor('rgba(0,0,0,0.55)')
                      .borderRadius(11)
                      .margin({ top: 4, right: 4 })
                      .onClick(() => { this.removeBatchImage(index ?? 0); })
                  }
                }
              }, (uri: string, index?: number) => `${index}-${uri}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(6)
            .rowsGap(6)
            .width('100%')
          } else {
            Text('+ 添加图片')
              .fontSize(AppTheme.font.body)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.primary)
              .width('100%')
              .height(110)
              .textAlign(TextAlign.Center)
              .backgroundColor(AppTheme.color.primaryPale)
              .borderRadius(AppTheme.radius.card)
              .border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border })
              .onClick(() => { this.pickMultipleImages(); })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Text(this.isBatchImporting ? '正在导入...' : `确认导入 ${this.batchImageUris.length}`)
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
        .width('100%')
        .height(46)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.batchImageUris.length > 0 && !this.isBatchImporting ? AppTheme.color.primary : AppTheme.color.textTertiary)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => { this.confirmBatchImport(); })
    }
    .padding(20)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VisibilityButton(visible: boolean, onTap: () => void) {
    Text(visible ? '眼' : '隐')
      .fontSize(10)
      .fontColor(AppTheme.color.textTertiary)
      .width(22)
      .height(18)
      .textAlign(TextAlign.Center)
      .backgroundColor(AppTheme.color.surfaceTint)
      .borderRadius(AppTheme.radius.pill)
      .onClick(onTap)
  }

  @Builder
  private StatCol(title: string, value: string, visible: boolean, onToggle: () => void, valueColor: string) {
    Column({ space: 4 }) {
      Row({ space: 5 }) {
        Text(title)
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
        this.VisibilityButton(visible, onToggle);
      }
      .height(18)
      .justifyContent(FlexAlign.Center)

      Text(visible ? value : '****')
        .fontSize(AppTheme.font.titleLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(valueColor)
        .height(32)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private StatsRow() {
    Row() {
      this.StatCol(
        '总件数/款',
        `${this.items.length}/${this.items.length}`,
        this.showCount,
        () => { this.showCount = !this.showCount; },
        AppTheme.color.textPrimary
      );

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppTheme.color.border)
        .height(48)

      this.StatCol(
        '裙装价值',
        this.formatCurrency(this.computeDressValue()),
        this.showDressValue,
        () => { this.showDressValue = !this.showDressValue; },
        AppTheme.color.accentWarm
      );

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppTheme.color.border)
        .height(48)

      this.StatCol(
        '总价值',
        this.formatCurrency(this.computeTotalValue()),
        this.showTotalValue,
        () => { this.showTotalValue = !this.showTotalValue; },
        AppTheme.color.textPrimary
      );
    }
    .width('100%')
  }

  @Builder
  private QuickTile(symbolName: string, label: string, onTap: () => void) {
    Column({ space: 10 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 34,
        color: AppTheme.color.primary
      })
      Text(label)
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.primary)
    }
    .layoutWeight(1)
    .height(92)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .linearGradient({
      angle: 135,
      colors: [
        [AppTheme.color.primaryPale, 0.0],
        ['rgba(255, 255, 255, 0.50)', 1.0]
      ]
    })
    .borderRadius(AppTheme.radius.tile)
    .onClick(onTap)
  }

  @Builder
  private SummaryPanel() {
    GlassCard({ innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        this.StatsRow();

        Row({ space: 12 }) {
          this.QuickTile(AppSymbolName.Spark, '今日穿搭色', () => {});
          this.QuickTile(AppSymbolName.Outfit, '穿搭手帐', () => {
            this.onOpenHouse('ootd');
          });
          this.QuickTile(AppSymbolName.Stats, '详细统计', () => {});
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private SearchField() {
    Row({ space: 10 }) {
      TextInput({ placeholder: '搜索名称、品牌、标签...', text: this.searchKeyword })
        .height(46)
        .fontSize(AppTheme.font.body)
        .placeholderColor(AppTheme.color.textTertiary)
        .fontColor(AppTheme.color.textPrimary)
        .backgroundColor(AppTheme.color.overlayGlassStrong)
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(AppTheme.radius.pill)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchKeyword = value;
          this.searchItems();
        })

      Text('示例')
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
        .padding({ left: 16, right: 16, top: 13, bottom: 13 })
        .backgroundColor(AppTheme.color.primary)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.addSampleItem();
        })
    }
    .width('100%')
  }

  @Builder
  private ContentArea() {
    if (this.selectedSegment === 'deposit') {
      this.DepositPanel();
    } else {
      this.ItemGrid();
    }
  }

  @Builder
  private DepositPanel() {
    Column({ space: 12 }) {
      this.TotalDepositCard();
      this.DepositDisplayModeToggle();
      this.DepositModeTabs();
      this.DepositSelector();

      if (this.isLoading) {
        this.LoadingState();
      } else if (this.depositVisibleItems().length === 0) {
        this.DepositEmptyState();
      } else {
        ForEach(this.depositVisibleItems(), (item: WardrobeItem) => {
          if (this.depositDisplayMode === 'simple') {
            this.SimpleDepositRow(item);
          } else {
            this.DepositRow(item);
          }
        }, (item: WardrobeItem) => item.id)
      }
    }
    .width('100%')
  }

  @Builder
  private DepositDisplayModeToggle() {
    Row() {
      Blank().layoutWeight(1)
      Row({ space: 6 }) {
        AppSymbol({
          name: this.depositDisplayMode === 'detail' ? AppSymbolName.Grid : AppSymbolName.Sort,
          iconSize: 16,
          color: AppTheme.color.textSecondary
        })
        Text(this.depositDisplayMode === 'detail' ? '详情' : '简略')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textSecondary)
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(AppTheme.color.overlayGlassStrong)
      .borderRadius(AppTheme.radius.pill)
      .border({ width: 1, color: AppTheme.color.border })
      .onClick(() => {
        this.depositDisplayMode = this.depositDisplayMode === 'detail' ? 'simple' : 'detail';
      })
    }
    .width('100%')
  }

  @Builder
  private TotalDepositCard() {
    GlassCard({ innerPadding: 0, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 0 }) {
        Row({ space: 0 }) {
          this.DepositShortcut('梦裙日历', AppSymbolName.Calendar, () => {
            this.onOpenHouse('calendar');
          });
          Divider().vertical(true).strokeWidth(1).color(AppTheme.color.border).height(34);
          this.DepositShortcut('马上来财', AppSymbolName.Wealth, () => {
            this.onOpenHouse('wealth');
          });
          Divider().vertical(true).strokeWidth(1).color(AppTheme.color.border).height(34);
          this.DepositShortcut('尾款提醒', AppSymbolName.Reminder, () => {});
        }
        .width('100%')
        .padding({ top: 12, bottom: 8 })

        Divider().strokeWidth(1).color(AppTheme.color.border).margin({ left: 18, right: 18 });

        Row() {
          Text('总待付尾款')
            .fontSize(AppTheme.font.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.color.textSecondary)
          Blank()
          Text(this.showDepositTotal ? '隐藏' : '显示')
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.primary)
            .padding({ left: 11, right: 11, top: 6, bottom: 6 })
            .backgroundColor(AppTheme.color.primaryPale)
            .borderRadius(AppTheme.radius.pill)
            .onClick(() => {
              if (!this.showDepositTotal) {
                AlertDialog.show({
                  title: '真的要解锁"钱包瘦身"副本吗？',
                  message: '⚠️ 前方尾款大军已集结！\n温馨提示：看完请抱紧你的钱包，深呼吸是没用的，不如默念"美貌无价"！\n(｡•́ω•̀｡)',
                  primaryButton: {
                    value: '取消',
                    action: () => {}
                  },
                  secondaryButton: {
                    value: '我准备好了！',
                    action: () => {
                      this.showDepositTotal = true;
                    }
                  }
                });
              } else {
                this.showDepositTotal = false;
              }
            })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12, bottom: this.showDepositTotal ? 4 : 14 })

        if (this.showDepositTotal) {
          Text(this.formatCurrency(this.depositTotalBalance()))
            .fontSize(AppTheme.font.displayMedium)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.primary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ bottom: 16 })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private DepositShortcut(title: string, symbolName: string, onTap: () => void) {
    Column({ space: 6 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 23,
        color: AppTheme.color.primary
      })
      Text(title)
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.primary)
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .onClick(onTap)
  }

  @Builder
  private DepositModeTabs() {
    Row({ space: 0 }) {
      this.DepositModeButton('monthly', '按月视图');
      this.DepositModeButton('series', '按系列视图');
    }
    .width('100%')
    .padding(4)
    .backgroundColor(AppTheme.color.overlayGlass)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.pill)
    .border({ width: 1, color: AppTheme.color.border })
  }

  @Builder
  private DepositModeButton(key: string, label: string) {
    Text(label)
      .fontSize(AppTheme.font.body)
      .fontWeight(this.depositViewMode === key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.depositViewMode === key ? AppTheme.color.textPrimary : AppTheme.color.textSecondary)
      .layoutWeight(1)
      .height(44)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.depositViewMode === key ? AppTheme.color.surfaceGlass : Color.Transparent)
      .borderRadius(AppTheme.radius.pill)
      .onClick(() => {
        this.depositViewMode = key;
        this.selectedDepositMonth = 0;
        this.selectedSeriesKey = '';
        this.isDepositSelectorExpanded = key === 'series';
      })
  }

  @Builder
  private DepositSelector() {
    Column({ space: 14 }) {
      Row() {
        Text(this.depositViewMode === 'monthly'
          ? (this.isDepositSelectorExpanded ? '年度预估尾款 (点我折叠)' : '年度预估尾款 (点我展开)')
          : (this.isDepositSelectorExpanded ? '按系列预估尾款 (点我折叠)' : '按系列预估尾款 (点我展开)'))
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.textSecondary)
        Blank()
        AppSymbol({
          name: this.isDepositSelectorExpanded ? AppSymbolName.Close : AppSymbolName.More,
          iconSize: 18,
          color: AppTheme.color.textTertiary
        })
      }
      .width('100%')
      .onClick(() => {
        this.isDepositSelectorExpanded = !this.isDepositSelectorExpanded;
      })

      if (this.isDepositSelectorExpanded) {
        this.DepositYearSwitcher();
        this.DepositYearStats();
        if (this.depositViewMode === 'monthly') {
          this.DepositMonthGrid();
        } else {
          this.DepositSeriesGrid();
        }
      } else {
        this.DepositRecentStats();
      }
    }
    .width('100%')
  }

  @Builder
  private DepositYearSwitcher() {
    Row() {
      Text('‹')
        .fontSize(26)
        .fontColor(AppTheme.color.textSecondary)
        .width(42)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.selectedDepositYear -= 1;
          this.selectedDepositMonth = 0;
          this.selectedSeriesKey = '';
        })
      Text(`${this.selectedDepositYear}年`)
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('›')
        .fontSize(26)
        .fontColor(AppTheme.color.textSecondary)
        .width(42)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.selectedDepositYear += 1;
          this.selectedDepositMonth = 0;
          this.selectedSeriesKey = '';
        })
      Text(this.showDepositYearStats ? '眼' : '隐')
        .fontSize(10)
        .fontColor(AppTheme.color.primary)
        .width(28)
        .height(26)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppTheme.color.primaryPale)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.showDepositYearStats = !this.showDepositYearStats;
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }

  @Builder
  private DepositYearStats() {
    GlassCard({ innerPadding: 14, cornerRadius: AppTheme.radius.card }) {
      Row() {
        this.DepositStatColumn(
          '待付件数',
          this.showDepositYearStats ? `${this.visibleDepositStats().count}` : '**',
          AppTheme.color.textPrimary
        );
        Divider().vertical(true).strokeWidth(1).color(AppTheme.color.border).height(32);
        this.DepositStatColumn(
          '待付尾款',
          this.showDepositYearStats ? this.formatCurrency(this.visibleDepositStats().amount) : '****',
          AppTheme.color.primary
        );
      }
      .width('100%')
    }
  }

  @Builder
  private DepositMonthGrid() {
    Grid() {
      ForEach(DEPOSIT_MONTHS, (month: number) => {
        GridItem() {
          Column({ space: 4 }) {
            Row({ space: 4 }) {
              Text(`${month}月`)
                .fontSize(AppTheme.font.caption)
                .fontWeight(this.selectedDepositMonth === month ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
              if (this.monthStats(month).count > 0) {
                Text(`${this.monthStats(month).count}`)
                  .fontSize(9)
                  .fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.textSecondary)
                  .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                  .backgroundColor(this.selectedDepositMonth === month ? 'rgba(255,255,255,0.24)' : AppTheme.color.surfaceTint)
                  .borderRadius(AppTheme.radius.pill)
              }
            }
            .justifyContent(FlexAlign.Center)

            Text(this.monthStats(month).count > 0 ? this.formatCurrency(this.monthStats(month).amount) : '-')
              .fontSize(AppTheme.font.tiny)
              .fontColor(this.selectedDepositMonth === month ? AppTheme.color.textOnPrimary : AppTheme.color.accentWarm)
              .maxLines(1)
          }
          .width('100%')
          .height(58)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.selectedDepositMonth === month ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong)
          .backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius(AppTheme.radius.card)
          .border({ width: 1, color: this.selectedDepositMonth === month ? Color.Transparent : AppTheme.color.border })
          .onClick(() => {
            this.selectedDepositMonth = this.selectedDepositMonth === month ? 0 : month;
          })
        }
      }, (month: number) => month.toString())
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .width('100%')
  }

  @Builder
  private DepositSeriesGrid() {
    if (this.depositSeriesGroups().length === 0) {
      Text('暂无系列数据')
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(18)
    } else {
      Grid() {
        ForEach(this.depositSeriesGroups(), (group: SeriesGroup) => {
          GridItem() {
            Column({ space: 5 }) {
              Row() {
                Text(group.seriesKey)
                  .fontSize(AppTheme.font.caption)
                  .fontWeight(this.selectedSeriesKey === group.seriesKey ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Blank()
                Text(`${group.count}`)
                  .fontSize(9)
                  .fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.textSecondary)
              }
              .width('100%')
              Text(this.formatCurrency(group.totalBalance))
                .fontSize(AppTheme.font.tiny)
                .fontColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.textOnPrimary : AppTheme.color.accentWarm)
                .width('100%')
            }
            .width('100%')
            .padding(10)
            .backgroundColor(this.selectedSeriesKey === group.seriesKey ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong)
            .backgroundBlurStyle(BlurStyle.Thin)
            .borderRadius(AppTheme.radius.card)
            .border({ width: 1, color: this.selectedSeriesKey === group.seriesKey ? Color.Transparent : AppTheme.color.border })
            .onClick(() => {
              this.selectedSeriesKey = this.selectedSeriesKey === group.seriesKey ? '' : group.seriesKey;
            })
          }
        }, (group: SeriesGroup) => group.seriesKey)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .width('100%')
    }
  }

  @Builder
  private DepositRecentStats() {
    GlassCard({ innerPadding: 14, cornerRadius: AppTheme.radius.card }) {
      Column({ space: 12 }) {
        Row() {
          AppSymbol({
            name: this.depositViewMode === 'monthly' ? AppSymbolName.Calendar : AppSymbolName.Series,
            iconSize: 18,
            color: AppTheme.color.primary
          })
          Text(this.depositViewMode === 'monthly' ? '最近月统计' : '最近添加')
            .fontSize(AppTheme.font.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textPrimary)
          Blank()
          Text(this.depositViewMode === 'monthly' ? `${this.recentDepositMonth()}月` : '一个月内')
            .fontSize(AppTheme.font.caption)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textOnPrimary)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .backgroundColor(AppTheme.color.primaryStrong)
            .borderRadius(AppTheme.radius.pill)
        }
        .width('100%')

        Row() {
          this.DepositStatColumn('待付件数', `${this.visibleDepositStats().count}`, AppTheme.color.textPrimary);
          Divider().vertical(true).strokeWidth(1).color(AppTheme.color.border).height(32);
          this.DepositStatColumn('待付尾款', this.formatCurrency(this.visibleDepositStats().amount), AppTheme.color.primary);
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private DepositStatColumn(title: string, value: string, valueColor: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
      Text(value)
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(valueColor)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private DepositEmptyState() {
    GlassCard({ innerPadding: 24, cornerRadius: AppTheme.radius.card }) {
      Column({ space: 10 }) {
        Text('暂无心愿尾款')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text('添加带尾款时间的心愿裙装后，会在这里按月或系列汇总。')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private DepositRow(item: WardrobeItem) {
    Row({ space: 12 }) {
      Stack() {
        Text(item.category.length > 0 ? item.category.substring(0, 1) : '衣')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
      }
      .width(54)
      .height(54)
      .backgroundColor(AppTheme.color.primaryPale)
      .borderRadius(AppTheme.radius.tile)

      Column({ space: 4 }) {
        Text(item.name)
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(`尾款: ${this.formatDepositDate(item.finalPaymentDate)}`)
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.primary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(AppTheme.color.primaryPale)
            .borderRadius(AppTheme.radius.chip)
          Text(item.brandName.length > 0 ? item.brandName : item.category)
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 2 }) {
        Text('定金 ' + this.formatCurrency(totalDeposit(item)))
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textTertiary)
        Text('尾款 ' + this.formatCurrency(totalBalance(item)))
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.card)
  }

  @Builder
  private SimpleDepositRow(item: WardrobeItem) {
    Row({ space: 10 }) {
      Text(item.name)
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.color.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.formatDepositDate(item.finalPaymentDate))
        .fontSize(AppTheme.font.tiny)
        .fontColor(AppTheme.color.textSecondary)
      Text(this.formatCurrency(totalBalance(item)))
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.primary)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.card)
  }

  @Builder
  private ItemGrid() {
    if (this.isLoading) {
      this.LoadingState();
    } else if (this.errorMessage.length > 0) {
      this.ErrorState();
    } else if (this.items.length === 0) {
      this.EmptyState();
    } else {
      Grid() {
        ForEach(this.items, (item: WardrobeItem, index?: number) => {
          GridItem() {
            this.ItemCard(item);
          }
        }, (item: WardrobeItem) => item.id)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(18)
      .width('100%')
      .editMode(this.isSelectionMode && this.currentSort === WardrobeSortOption.Custom)
      .supportAnimation(true)
      .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
        AppLogger.info(`[Reorder] drag start index=${itemIndex}`);
        this.dragPreviewItem = this.items[itemIndex];
        return this.DragPreview();
      })
      .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
        AppLogger.info(`[Reorder] drop from=${itemIndex} to=${insertIndex} ok=${isSuccess}`);
        this.dragPreviewItem = null;
        if (!isSuccess || itemIndex === insertIndex || insertIndex < 0) {
          return;
        }
        this.handleReorderDrop(itemIndex, insertIndex);
      })
    }
  }

  @Builder
  private DragPreview() {
    Column() {
      if (this.dragPreviewItem !== null && this.dragPreviewItem.imageUri.length > 0) {
        Image(this.dragPreviewItem.imageUri)
          .width(96)
          .height(96)
          .objectFit(ImageFit.Cover)
          .borderRadius(AppTheme.radius.card)
      } else {
        Text(this.dragPreviewItem !== null && this.dragPreviewItem.category.length > 0
          ? this.dragPreviewItem.category.substring(0, 1)
          : '衣')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
          .width(96)
          .height(96)
          .textAlign(TextAlign.Center)
          .backgroundColor(AppTheme.color.primaryPale)
          .borderRadius(AppTheme.radius.card)
      }
    }
    .shadow({ radius: 18, color: AppTheme.color.shadowSoft, offsetX: 0, offsetY: 8 })
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

  @Builder
  private ItemCard(item: WardrobeItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        // 主视觉：优先显示图片，缺图时回退到分类首字
        if (item.imageUri.length > 0) {
          Image(item.imageUri)
            .width('100%')
            .height(112)
            .objectFit(ImageFit.Cover)
            .alt($r('app.media.start_icon'))
        } else {
          Stack() {
            Text(item.category.length > 0 ? item.category.substring(0, 1) : '衣')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.primary)
          }
          .width('100%')
          .height(112)
          .linearGradient({
            angle: 150,
            colors: [
              [AppTheme.color.primaryPale, 0.0],
              [AppTheme.color.surface, 0.45],
              [AppTheme.color.primarySoft, 1.0]
            ]
          })
        }

        // 编辑模式：右上角勾选圈；非编辑模式：保留尾款小角标
        if (this.isSelectionMode) {
          Text(this.isItemSelected(item.id) ? '✓' : '')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.isItemSelected(item.id)
              ? AppTheme.color.primary
              : 'rgba(255,255,255,0.65)')
            .borderRadius(12)
            .border({
              width: 1.5,
              color: this.isItemSelected(item.id) ? AppTheme.color.primary : AppTheme.color.border
            })
            .margin({ top: 8, right: 8 })
        } else {
          Text('心愿尾款')
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.textOnPrimary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('rgba(50, 35, 43, 0.68)')
            .borderRadius(AppTheme.radius.chip)
            .margin({ top: 10, right: 10 })
        }
      }
      .width('100%')
      .borderRadius(AppTheme.radius.card)
      .clip(true)

      Column({ space: 5 }) {
        Text(item.name)
          .fontSize(AppTheme.font.caption)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`定金 ¥${Math.round(item.price * 0.4)}  尾款 ¥${Math.round(item.price * 0.6)}`)
          .fontSize(AppTheme.font.tiny)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .padding(6)
    .backgroundColor(AppTheme.color.overlayGlass)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.card)
    .border({
      width: this.isSelectionMode && this.isItemSelected(item.id) ? 2 : 1,
      color: this.isSelectionMode && this.isItemSelected(item.id)
        ? AppTheme.color.primary
        : AppTheme.color.border
    })
    .shadow({
      radius: 14,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 6
    })
    .onClick(() => {
      if (this.isSelectionMode) {
        AppLogger.info(`[ItemCard] selection toggle id=${item.id}`);
        this.toggleItemSelection(item.id);
      } else {
        AppLogger.info(`[ItemCard] open detail id=${item.id}, name=${item.name}`);
        this.navPathStack.pushPathByName(
          'wardrobeItemDetail',
          new WardrobeDetailArgs(item.name, item.category, item.price)
        );
      }
    })
  }

  @Builder
  private LoadingState() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(AppTheme.color.primary)
      Text('正在读取衣橱...')
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .padding(40)
  }

  @Builder
  private EmptyState() {
    GlassCard({ innerPadding: 24, cornerRadius: AppTheme.radius.card }) {
      Column({ space: 10 }) {
        Text('衣橱还空着呢～')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text(this.searchKeyword.length > 0
          ? '没有找到匹配的衣物，换个关键词试试。'
          : '点右上角「+」手动创建，或批量导入相册图片来点亮你的第一件梦裙。')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private ErrorState() {
    GlassCard({ innerPadding: 24, cornerRadius: AppTheme.radius.card }) {
      Column({ space: 10 }) {
        Text('衣橱读取失败')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text(this.errorMessage)
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textSecondary)
        Text('重试')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .backgroundColor(AppTheme.color.primary)
          .borderRadius(AppTheme.radius.pill)
          .onClick(() => {
            this.loadItems();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private SheetContent() {
    Column() {
      if (this.activeSheet === 'sort') {
        SortSheet({
          currentSort: $currentSort,
          onClose: () => {
            AppLogger.info('[Sheet] sort onClose');
            this.showSheet = false;
            this.persistSortOption();
          }
        })
      } else if (this.activeSheet === 'layout') {
        ViewLayoutSheet({
          currentLayout: $currentLayout,
          onClose: () => {
            AppLogger.info('[Sheet] layout onClose');
            this.showSheet = false;
            this.persistViewLayout();
          }
        })
      } else if (this.activeSheet === 'filter') {
        FilterSheet({
          filterState: $filterState,
          candidateTypes: this.collectUniqueValues('types'),
          candidateColors: this.collectUniqueValues('colors'),
          candidateSizes: this.collectUniqueValues('sizes'),
          candidateLengths: this.collectUniqueValues('length'),
          candidateConditions: this.collectUniqueValues('condition'),
          onClose: () => {
            AppLogger.info('[Sheet] filter onClose');
            this.showSheet = false;
          }
        })
      } else if (this.activeSheet === 'create') {
        ClothingEditPage({
          onSave: (draft: ClothingDraft) => {
            this.saveClothingDraft(draft);
          },
          onCancel: () => {
            AppLogger.info('[Create] cancel tapped');
            this.showSheet = false;
          }
        })
      } else if (this.activeSheet === 'batchImport') {
        this.BatchImportSheet();
      } else {
        Text('loading...')
          .fontSize(AppTheme.font.body)
          .fontColor(AppTheme.color.textTertiary)
          .padding(40)
      }
    }
    .width('100%')
    .onAppear(() => {
      AppLogger.info(`[Sheet] onAppear: activeSheet=${this.activeSheet}`);
    })
    .onDisAppear(() => {
      AppLogger.info(`[Sheet] onDisAppear: activeSheet=${this.activeSheet}, showSheet=${this.showSheet}`);
    })
  }

  private collectUniqueValues(field: string): string[] {
    const values: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      let raw = '';
      if (field === 'types') {
        raw = item.types;
      } else if (field === 'colors') {
        raw = item.colors;
      } else if (field === 'sizes') {
        raw = item.sizes;
      } else if (field === 'length') {
        raw = item.length;
      } else if (field === 'condition') {
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

  @Builder
  pageMap(name: string, param: object) {
    if (name === 'wardrobeItemDetail') {
      WardrobeItemDetailPage({ args: param as WardrobeDetailArgs })
    }
  }

  @Builder
  private SelectionBottomBar() {
    Row({ space: 16 }) {
      Text(`批量删除 (${this.selectedItemIds.length})`)
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.selectedItemIds.length > 0 ? AppTheme.color.textOnPrimary : AppTheme.color.textTertiary)
        .layoutWeight(1)
        .height(46)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.selectedItemIds.length > 0 ? AppTheme.color.primary : AppTheme.color.overlayGlassStrong)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          AppLogger.info(`[Selection] batch delete tapped, count=${this.selectedItemIds.length}`);
          if (this.selectedItemIds.length === 0) {
            return;
          }
          AlertDialog.show({
            title: '确认删除所选衣物？',
            message: `将移出衣橱 ${this.selectedItemIds.length} 件，可在回收站恢复。`,
            primaryButton: { value: '取消', action: () => {} },
            secondaryButton: {
              value: '删除',
              fontColor: AppTheme.color.primary,
              action: () => { this.batchDeleteSelected(); }
            }
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    .backgroundColor(AppTheme.color.surface)
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: { top: 1 }, color: AppTheme.color.border })
  }

  build() {
    Navigation(this.navPathStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          this.TopBar();

          Scroll() {
            Column({ space: 16 }) {
              this.SummaryPanel();
              this.ContentArea();
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: AppTheme.spacing.page,
              right: AppTheme.spacing.page,
              top: 10,
              bottom: this.isSelectionMode ? 96 : 126
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .backgroundColor(Color.Transparent)
        }
        .width('100%')
        .height('100%')

        if (this.isSelectionMode) {
          this.SelectionBottomBar();
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .bindSheet($$this.showSheet, this.SheetContent(), {
      height: (this.activeSheet === 'filter' || this.activeSheet === 'batchImport') ? SheetSize.MEDIUM :
              (this.activeSheet === 'create') ? SheetSize.MEDIUM : SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: AppTheme.color.backgroundLight,
      onDisappear: () => {
        AppLogger.info(`[Sheet] bindSheet onDisappear: activeSheet=${this.activeSheet}`);
        this.showSheet = false;
      }
    })
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
    } catch (error) {
      this.handleError('load wardrobe items failed', error);
    } finally {
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
    } catch (error) {
      this.handleError('search wardrobe items failed', error);
    } finally {
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
    } catch (error) {
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
    } catch (error) {
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
}

class DepositStats {
  count: number;
  amount: number;

  constructor(count: number, amount: number) {
    this.count = count;
    this.amount = amount;
  }
}
