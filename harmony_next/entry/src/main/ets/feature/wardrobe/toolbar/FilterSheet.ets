import { AppTheme } from '../../../core/theme/AppTheme';
import {
  AllDepositStatus,
  countActiveFilters,
  createDefaultFilter,
  depositStatusLabel,
  DepositStatusFilter,
  WardrobeFilterState
} from '../../../domain/model/WardrobeListOptions';

@Component
export struct FilterSheet {
  @Link filterState: WardrobeFilterState;
  @Prop candidateTypes: string[] = [];
  @Prop candidateColors: string[] = [];
  @Prop candidateSizes: string[] = [];
  @Prop candidateLengths: string[] = [];
  @Prop candidateConditions: string[] = [];
  onClose: () => void = () => {};

  private isTypeSelected(value: string): boolean {
    return this.filterState.types.indexOf(value) >= 0;
  }

  private isColorSelected(value: string): boolean {
    return this.filterState.colors.indexOf(value) >= 0;
  }

  private isSizeSelected(value: string): boolean {
    return this.filterState.sizes.indexOf(value) >= 0;
  }

  private isLengthSelected(value: string): boolean {
    return this.filterState.lengths.indexOf(value) >= 0;
  }

  private isConditionSelected(value: string): boolean {
    return this.filterState.conditions.indexOf(value) >= 0;
  }

  private toggleArrayItem(arr: string[], value: string): string[] {
    const idx = arr.indexOf(value);
    if (idx >= 0) {
      return arr.filter((v: string) => v !== value);
    } else {
      const result = arr.slice();
      result.push(value);
      return result;
    }
  }

  private resetAll(): void {
    this.filterState = createDefaultFilter();
  }

  @Builder
  private SectionHeader(title: string, count: number) {
    Row() {
      Text(title)
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
      if (count > 0) {
        Text(` (${count})`)
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.primary)
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 6 })
  }

  @Builder
  private FilterChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(AppTheme.font.caption)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(selected ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(selected ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong)
      .borderRadius(AppTheme.radius.pill)
      .border({ width: 1, color: selected ? AppTheme.color.primaryStrong : AppTheme.color.border })
      .margin({ right: 8, bottom: 8 })
      .onClick(onTap)
  }

  @Builder
  private DepositStatusSection() {
    this.SectionHeader('状态', this.filterState.depositStatus !== DepositStatusFilter.All ? 1 : 0);
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(AllDepositStatus, (status: DepositStatusFilter) => {
        this.FilterChip(depositStatusLabel(status), this.filterState.depositStatus === status, () => {
          this.filterState.depositStatus = status;
        });
      }, (status: DepositStatusFilter) => status)
    }
    .width('100%')
  }

  @Builder
  private MultiSelectSection(title: string, options: string[], selected: string[], onToggle: (value: string) => void) {
    if (options.length > 0) {
      this.SectionHeader(title, selected.length);
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(options, (option: string) => {
          this.FilterChip(option, selected.indexOf(option) >= 0, () => {
            onToggle(option);
          });
        }, (option: string) => option)
      }
      .width('100%')
    }
  }

  build() {
    Column({ space: 0 }) {
      Row() {
        Text('多维筛选')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)

        Blank().layoutWeight(1)

        if (countActiveFilters(this.filterState) > 0) {
          Text(`清除 (${countActiveFilters(this.filterState)})`)
            .fontSize(AppTheme.font.caption)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E53935')
            .onClick(() => {
              this.resetAll();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 8 })

      Scroll() {
        Column({ space: 4 }) {
          this.DepositStatusSection();

          this.MultiSelectSection('类型', this.candidateTypes, this.filterState.types, (v: string) => {
            this.filterState.types = this.toggleArrayItem(this.filterState.types, v);
          });

          this.MultiSelectSection('颜色', this.candidateColors, this.filterState.colors, (v: string) => {
            this.filterState.colors = this.toggleArrayItem(this.filterState.colors, v);
          });

          this.MultiSelectSection('尺码', this.candidateSizes, this.filterState.sizes, (v: string) => {
            this.filterState.sizes = this.toggleArrayItem(this.filterState.sizes, v);
          });

          this.MultiSelectSection('裙长', this.candidateLengths, this.filterState.lengths, (v: string) => {
            this.filterState.lengths = this.toggleArrayItem(this.filterState.lengths, v);
          });

          this.MultiSelectSection('品相', this.candidateConditions, this.filterState.conditions, (v: string) => {
            this.filterState.conditions = this.toggleArrayItem(this.filterState.conditions, v);
          });

          Blank().height(20)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 14 }) {
        Text('重置')
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.textPrimary)
          .padding({ left: 24, right: 24, top: 11, bottom: 11 })
          .backgroundColor(AppTheme.color.overlayGlassStrong)
          .borderRadius(AppTheme.radius.pill)
          .border({ width: 1, color: AppTheme.color.border })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.resetAll(); })

        Text('确定')
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 24, right: 24, top: 11, bottom: 11 })
          .backgroundColor(AppTheme.color.primary)
          .borderRadius(AppTheme.radius.pill)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 10, bottom: 28 })
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
  }
}
