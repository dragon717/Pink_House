import { AppTheme } from '../../../core/theme/AppTheme';
import { GlassCard } from '../../../core/theme/GlassComponents';
import {
  AllSortOptions,
  sortOptionLabel,
  sortOptionSymbol,
  WardrobeSortOption
} from '../../../domain/model/WardrobeListOptions';

@Component
export struct SortSheet {
  @Link currentSort: WardrobeSortOption;
  onClose: () => void = () => {};

  @Builder
  private SortRow(option: WardrobeSortOption) {
    Row({ space: 12 }) {
      SymbolGlyph($r(sortOptionSymbol(option)))
        .fontSize(20)
        .fontColor([this.currentSort === option ? AppTheme.color.primary : AppTheme.color.textSecondary])

      Text(sortOptionLabel(option))
        .fontSize(AppTheme.font.body)
        .fontWeight(this.currentSort === option ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentSort === option ? AppTheme.color.textPrimary : AppTheme.color.textSecondary)
        .layoutWeight(1)

      if (this.currentSort === option) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([AppTheme.color.primary])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.currentSort === option ? AppTheme.color.primaryPale : Color.Transparent)
    .borderRadius(AppTheme.radius.chip)
    .onClick(() => {
      this.currentSort = option;
      this.onClose();
    })
  }

  build() {
    Column({ space: 0 }) {
      Text('排序方式')
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 12 })

      ForEach(AllSortOptions, (option: WardrobeSortOption) => {
        this.SortRow(option);
      }, (option: WardrobeSortOption) => option)

      Blank().height(20)
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, bottom: 16 })
  }
}
