import common from '@ohos.app.ability.common';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';
import { AppLogger } from '../../core/utils/AppLogger';
import { RdbWardrobeRepository } from '../../data/repository/RdbWardrobeRepository';
import { totalBalance, totalDeposit, WardrobeItem } from '../../domain/model/WardrobeItem';
import { SeriesAnalyzer, SeriesGroup } from '../../domain/service/SeriesAnalyzer';
import { AddSampleWardrobeItemUseCase } from '../../domain/usecase/AddSampleWardrobeItemUseCase';
import { GetDepositPlansUseCase } from '../../domain/usecase/GetDepositPlansUseCase';
import { GetWardrobeItemsUseCase } from '../../domain/usecase/GetWardrobeItemsUseCase';
import { SearchWardrobeItemsUseCase } from '../../domain/usecase/SearchWardrobeItemsUseCase';
import { SoftDeleteWardrobeItemUseCase } from '../../domain/usecase/SoftDeleteWardrobeItemUseCase';
import { WardrobeItemDetailPage, WardrobeDetailArgs } from './WardrobeItemDetailPage';

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
  @State private showToolbarMenu: boolean = false;
  @State private depositViewMode: string = 'monthly';
  @State private selectedDepositYear: number = new Date().getFullYear();
  @State private selectedDepositMonth: number = 0;
  @State private selectedSeriesKey: string = '';
  @State private isDepositSelectorExpanded: boolean = false;
  @State private showDepositTotal: boolean = false;
  @State private showDepositYearStats: boolean = false;

  private navPathStack: NavPathStack = new NavPathStack();
  onOpenHouse: (destination: string) => void = () => {};

  aboutToAppear(): void {
    this.loadItems();
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
    .width(34)
    .height(44)
    .onClick(onTap)
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
      this.showToolbarMenu = false;
    })
  }

  @Builder
  private TopBar() {
    Column({ space: 6 }) {
      Row({ space: 4 }) {
        this.ModeButton('wardrobe', AppSymbolName.Wardrobe, '少女衣橱');
        this.ModeButton('deposit', AppSymbolName.Deposit, '心愿尾款');

        Blank()
          .layoutWeight(1)

        Row({ space: 2 }) {
          this.RoundButton(AppSymbolName.Sort, () => {});
          this.RoundButton(AppSymbolName.Filter, () => {});
          this.RoundButton(AppSymbolName.Grid, () => {});
          this.RoundButton(this.showToolbarMenu ? AppSymbolName.Close : AppSymbolName.More, () => {
            this.showToolbarMenu = !this.showToolbarMenu;
          });
          this.RoundButton(AppSymbolName.Add, () => {
            this.addSampleItem();
          });
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showToolbarMenu) {
        this.ToolbarMenu();
      }
    }
    .width('100%')
    .padding({
      left: AppTheme.spacing.page,
      right: AppTheme.spacing.page,
      top: 8,
      bottom: 4
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private MenuChip(label: string, symbolName: string, onTap: () => void) {
    Row({ space: 6 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 17,
        color: AppTheme.color.primary
      })
      Text(label)
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.color.textPrimary)
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .borderRadius(AppTheme.radius.pill)
    .border({ width: 1, color: AppTheme.color.border })
    .onClick(onTap)
  }

  @Builder
  private ToolbarMenu() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      this.MenuChip('搜索', AppSymbolName.Search, () => {});
      this.MenuChip('筛选', AppSymbolName.Filter, () => {});
      this.MenuChip('编辑', AppSymbolName.Edit, () => {});
      this.MenuChip('详细统计', AppSymbolName.Stats, () => {});
      this.MenuChip('批量导入', AppSymbolName.Import, () => {});
      this.MenuChip('穿搭手帐', AppSymbolName.Outfit, () => {
        this.showToolbarMenu = false;
        this.onOpenHouse('ootd');
      });
    }
    .width('100%')
    .padding({ left: 4, right: 4, bottom: 2 })
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
      this.DepositModeTabs();
      this.DepositSelector();

      if (this.isLoading) {
        this.LoadingState();
      } else if (this.depositVisibleItems().length === 0) {
        this.DepositEmptyState();
      } else {
        ForEach(this.depositVisibleItems(), (item: WardrobeItem) => {
          this.DepositRow(item);
        }, (item: WardrobeItem) => item.id)
      }
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
              this.showDepositTotal = !this.showDepositTotal;
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
  private ItemGrid() {
    if (this.isLoading) {
      this.LoadingState();
    } else if (this.errorMessage.length > 0) {
      this.ErrorState();
    } else if (this.items.length === 0) {
      this.EmptyState();
    } else {
      Grid() {
        ForEach(this.items, (item: WardrobeItem) => {
          GridItem() {
            this.ItemCard(item);
          }
        }, (item: WardrobeItem) => item.id)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(18)
      .width('100%')
    }
  }

  @Builder
  private ItemCard(item: WardrobeItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
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

        Text('心愿尾款')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor('rgba(50, 35, 43, 0.68)')
          .borderRadius(AppTheme.radius.chip)
          .margin({ top: 10, right: 10 })
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
    .border({ width: 1, color: AppTheme.color.border })
    .shadow({
      radius: 14,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 6
    })
    .onClick(() => {
      this.navPathStack.pushPathByName(
        'wardrobeItemDetail',
        new WardrobeDetailArgs(item.name, item.category, item.price)
      );
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
        Text('还没有衣物')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text(this.searchKeyword.length > 0 ? '没有找到匹配名称，换个关键词试试。' : '先添加一件示例衣物，验证 RDB 列表链路。')
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
  pageMap(name: string, param: object) {
    if (name === 'wardrobeItemDetail') {
      WardrobeItemDetailPage({ args: param as WardrobeDetailArgs })
    }
  }

  build() {
    Navigation(this.navPathStack) {
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
            bottom: 126
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
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
