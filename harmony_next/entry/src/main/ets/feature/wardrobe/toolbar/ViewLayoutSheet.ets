import { AppTheme } from '../../../core/theme/AppTheme';
import {
  AllViewLayouts,
  viewLayoutLabel,
  WardrobeViewLayout
} from '../../../domain/model/WardrobeListOptions';

const VIEW_LAYOUT_ICONS: Record<string, string> = {
  'listBrief': 'sys.symbol.list_bullet',
  'listDetailed': 'sys.symbol.list_bullet_rectangle_portrait',
  'grid2': 'sys.symbol.square_grid_2x2',
  'grid3': 'sys.symbol.square_grid_3x3',
  'grid6': 'sys.symbol.rectangle_grid_3x2'
};

@Component
export struct ViewLayoutSheet {
  @Link currentLayout: WardrobeViewLayout;
  onClose: () => void = () => {};

  private layoutIcon(layout: WardrobeViewLayout): string {
    return VIEW_LAYOUT_ICONS[layout] ?? 'sys.symbol.square_grid_2x2';
  }

  @Builder
  private LayoutRow(layout: WardrobeViewLayout) {
    Row({ space: 12 }) {
      SymbolGlyph($r(this.layoutIcon(layout)))
        .fontSize(20)
        .fontColor([this.currentLayout === layout ? AppTheme.color.primary : AppTheme.color.textSecondary])

      Text(viewLayoutLabel(layout))
        .fontSize(AppTheme.font.body)
        .fontWeight(this.currentLayout === layout ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentLayout === layout ? AppTheme.color.textPrimary : AppTheme.color.textSecondary)
        .layoutWeight(1)

      if (this.currentLayout === layout) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([AppTheme.color.primary])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.currentLayout === layout ? AppTheme.color.primaryPale : Color.Transparent)
    .borderRadius(AppTheme.radius.chip)
    .onClick(() => {
      this.currentLayout = layout;
      this.onClose();
    })
  }

  build() {
    Column({ space: 0 }) {
      Text('布局方式')
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 12 })

      ForEach(AllViewLayouts, (layout: WardrobeViewLayout) => {
        this.LayoutRow(layout);
      }, (layout: WardrobeViewLayout) => layout)

      Blank().height(20)
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, bottom: 16 })
  }
}
