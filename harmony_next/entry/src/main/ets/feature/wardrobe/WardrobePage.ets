import common from '@ohos.app.ability.common';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';
import { AppLogger } from '../../core/utils/AppLogger';
import { RdbWardrobeRepository } from '../../data/repository/RdbWardrobeRepository';
import { WardrobeItem } from '../../domain/model/WardrobeItem';
import { AddSampleWardrobeItemUseCase } from '../../domain/usecase/AddSampleWardrobeItemUseCase';
import { GetWardrobeItemsUseCase } from '../../domain/usecase/GetWardrobeItemsUseCase';
import { SearchWardrobeItemsUseCase } from '../../domain/usecase/SearchWardrobeItemsUseCase';
import { SoftDeleteWardrobeItemUseCase } from '../../domain/usecase/SoftDeleteWardrobeItemUseCase';
import { WardrobeItemDetailPage, WardrobeDetailArgs } from './WardrobeItemDetailPage';

@Component
export struct WardrobePage {
  @State private items: WardrobeItem[] = [];
  @State private searchKeyword: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State selectedSegment: string = 'wardrobe';
  @State private showCount: boolean = true;
  @State private showDressValue: boolean = false;
  @State private showTotalValue: boolean = false;
  @State private showToolbarMenu: boolean = false;

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
      GlassCard({ innerPadding: 18, cornerRadius: AppTheme.radius.card }) {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text('本月待付尾款')
                .fontSize(AppTheme.font.caption)
                .fontColor(AppTheme.color.textSecondary)
              Text(this.formatCurrency(this.computeTotalValue() * 0.6))
                .fontSize(AppTheme.font.displayMedium)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.primary)
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Text('月视图')
              .fontSize(AppTheme.font.caption)
              .fontColor(AppTheme.color.primary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(AppTheme.color.primaryPale)
              .borderRadius(AppTheme.radius.pill)
          }
          .width('100%')

          Row({ space: 10 }) {
            this.DepositShortcut('提醒', '本地提醒', AppSymbolName.Reminder);
            this.DepositShortcut('系列', '按系列看', AppSymbolName.Series);
            this.DepositShortcut('日历', '梦裙日历', AppSymbolName.Calendar);
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      ForEach(this.items, (item: WardrobeItem) => {
        this.DepositRow(item);
      }, (item: WardrobeItem) => item.id)
    }
    .width('100%')
  }

  @Builder
  private DepositShortcut(title: string, subtitle: string, symbolName: string) {
    Column({ space: 4 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 24,
        color: AppTheme.color.primary
      })
      Text(title)
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
      Text(subtitle)
        .fontSize(AppTheme.font.tiny)
        .fontColor(AppTheme.color.textTertiary)
    }
    .layoutWeight(1)
    .height(86)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.color.surfaceTint)
    .borderRadius(AppTheme.radius.tile)
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
        Text('定金 ' + this.formatCurrency(item.price * 0.4))
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.formatCurrency(item.price * 0.6))
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.primary)
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
}
