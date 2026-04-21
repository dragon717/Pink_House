import common from '@ohos.app.ability.common';
import { AppTheme } from '../../core/theme/AppTheme';
import { IconCapsule, PillSegment, SegmentOption } from '../../core/theme/GlassComponents';
import { AppLogger } from '../../core/utils/AppLogger';
import { RdbWardrobeRepository } from '../../data/repository/RdbWardrobeRepository';
import { WardrobeItem } from '../../domain/model/WardrobeItem';
import { AddSampleWardrobeItemUseCase } from '../../domain/usecase/AddSampleWardrobeItemUseCase';
import { GetWardrobeItemsUseCase } from '../../domain/usecase/GetWardrobeItemsUseCase';
import { SearchWardrobeItemsUseCase } from '../../domain/usecase/SearchWardrobeItemsUseCase';
import { SoftDeleteWardrobeItemUseCase } from '../../domain/usecase/SoftDeleteWardrobeItemUseCase';

/**
 * 衣橱首页视觉对齐 IMG_7936：
 * - 顶部工具栏：左 2 图标（sort / grid）+ 中央胶囊分段（少女衣橱 / 心愿尾款）+ 右 3 图标（filter / more / +）
 * - 统计玻璃行 3 列：总件数/款 · 裙装价值（橙）· 总价值，列间细竖线分隔
 * - 快捷 3 列大 tile：今日穿搭色 · 穿搭手帐 · 详细统计（图标在上，文字在下）
 * - 2 列衣物网格
 * 参考 iOS：
 *   ItemManager/Views/HomeView.swift:353-411 (tabSwitcher 少女衣橱/心愿尾款)
 *   ItemManager/Views/WardrobeView.swift:1441-1524 (stats + action 3 列同卡)
 */

const SEGMENT_OPTIONS: SegmentOption[] = [
  { key: 'wardrobe', label: '少女衣橱', glyph: '🧺' },
  { key: 'deposit', label: '心愿尾款', glyph: '📅' }
];

@Component
export struct WardrobePage {
  @State private items: WardrobeItem[] = [];
  @State private searchKeyword: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private selectedSegment: string = 'wardrobe';

  aboutToAppear(): void {
    this.loadItems();
  }

  private formatCurrency(value: number): string {
    const intVal = Math.round(value);
    return '¥' + intVal.toString();
  }

  private computeTotalValue(): number {
    let sum = 0;
    for (let i = 0; i < this.items.length; i++) {
      sum += this.items[i].price;
    }
    return sum;
  }

  @Builder
  private TopBar() {
    Row({ space: 8 }) {
      IconCapsule({ glyph: '↑' });
      IconCapsule({ glyph: '⊞' });

      Blank()
        .layoutWeight(1)

      PillSegment({ options: SEGMENT_OPTIONS, selectedKey: $selectedSegment });

      Blank()
        .layoutWeight(1)

      IconCapsule({ glyph: '☰' });
      IconCapsule({ glyph: '⋯' });
      IconCapsule({ glyph: '＋' });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private StatColumn(title: string, value: string, valueColor: string) {
    Column({ space: 6 }) {
      Row({ space: 4 }) {
        Text(title)
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
        Text('◉')
          .fontSize(10)
          .fontColor(AppTheme.color.textTertiary)
      }
      Text(value)
        .fontSize(AppTheme.font.titleLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(valueColor)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private StatsRow() {
    // items 数量与价值内联读取，不用 getter（ArkTS 不观察 getter）
    Row() {
      this.StatColumn(
        '总件数/款',
        `${this.items.length}/${this.items.length}`,
        AppTheme.color.textPrimary
      );

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppTheme.color.border)
        .height(36)

      this.StatColumn(
        '裙装价值',
        this.formatCurrency(this.computeTotalValue()),
        '#FF9800'
      );

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .color(AppTheme.color.border)
        .height(36)

      this.StatColumn(
        '总价值',
        this.formatCurrency(this.computeTotalValue()),
        AppTheme.color.textPrimary
      );
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 14, bottom: 14 })
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .borderRadius(AppTheme.radius.card)
  }

  @Builder
  private QuickTile(glyph: string, label: string, tintStart: string, tintEnd: string, textColor: string) {
    Column({ space: 6 }) {
      Text(glyph)
        .fontSize(22)
        .fontColor(textColor)
      Text(label)
        .fontSize(AppTheme.font.tiny)
        .fontWeight(FontWeight.Medium)
        .fontColor(textColor)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .linearGradient({
      angle: 135,
      colors: [[tintStart, 0.0], [tintEnd, 1.0]]
    })
    .borderRadius(AppTheme.radius.tile)
  }

  @Builder
  private QuickTilesRow() {
    Row({ space: 10 }) {
      this.QuickTile('✦', '今日穿搭色', '#FDE8EC', '#FADEE2', AppTheme.color.primary);
      this.QuickTile('📓', '穿搭手帐', '#FDEEE4', '#F9E4D6', '#B7793F');
      this.QuickTile('▦', '详细统计', '#EDE4F3', '#E4D8EC', '#7C6B9A');
    }
    .width('100%')
  }

  @Builder
  private SearchField() {
    Row({ space: 10 }) {
      TextInput({ placeholder: '搜索衣物名称', text: this.searchKeyword })
        .height(42)
        .fontSize(AppTheme.font.body)
        .placeholderColor(AppTheme.color.textTertiary)
        .fontColor(AppTheme.color.textPrimary)
        .backgroundColor(AppTheme.color.surfaceTint)
        .borderRadius(AppTheme.radius.pill)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchKeyword = value;
          this.searchItems();
        })

      Text('+ 示例')
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textOnPrimary)
        .padding({ left: 14, right: 14, top: 11, bottom: 11 })
        .backgroundColor(AppTheme.color.primary)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.addSampleItem();
        })
    }
    .width('100%')
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
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
    }
  }

  @Builder
  private ItemCard(item: WardrobeItem) {
    Column({ space: 8 }) {
      // 图片占位 + "心愿尾款" 角标叠加
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width('100%')
          .height(160)
          .linearGradient({
            angle: 180,
            colors: [[AppTheme.color.primaryPale, 0.0], [AppTheme.color.primarySoft, 1.0]]
          })
        Text('心愿尾款')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(AppTheme.color.primaryStrong)
          .borderRadius(AppTheme.radius.pill)
          .margin({ top: 8, right: 8 })
        Text(item.category.substring(0, 1))
          .fontSize(36)
          .fontColor(AppTheme.color.primary)
      }
      .width('100%')
      .borderRadius(AppTheme.radius.tile)
      .clip(true)

      Column({ space: 4 }) {
        Text(item.name)
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`定金 ¥${Math.round(item.price * 0.4)}  尾款 ¥${Math.round(item.price * 0.6)}`)
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
    .shadow({
      radius: 14,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private LoadingState() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(AppTheme.color.primary)
      Text('正在读取衣橱…')
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .padding(40)
  }

  @Builder
  private EmptyState() {
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
    .padding(24)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
  }

  @Builder
  private ErrorState() {
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
    .padding(24)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        this.TopBar();
        this.StatsRow();
        this.QuickTilesRow();
        this.SearchField();
        this.ItemGrid();
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: AppTheme.spacing.page,
        right: AppTheme.spacing.page,
        top: 12,
        bottom: 120
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
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
