import { AppTheme } from './AppTheme';

export interface SegmentOption {
  readonly key: string;
  readonly label: string;
  readonly glyph?: string;
}

@Component
export struct GlassCard {
  @Prop innerPadding: number = AppTheme.spacing.card;
  @Prop cornerRadius: number = AppTheme.radius.card;
  @Prop material: string = AppTheme.color.overlayGlassStrong;
  @BuilderParam content: () => void = this.defaultContent;

  @Builder
  defaultContent() {
  }

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .padding(this.innerPadding)
    .backgroundColor(this.material)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(this.cornerRadius)
    .border({ width: 1, color: AppTheme.color.border })
    .shadow({
      radius: 18,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 8
    })
  }
}

@Component
export struct PillSegment {
  @Prop options: SegmentOption[] = [];
  @Link selectedKey: string;
  @Prop fillBackground: boolean = true;

  build() {
    Row({ space: 0 }) {
      ForEach(this.options, (opt: SegmentOption) => {
        Row({ space: 6 }) {
          if (opt.glyph && opt.glyph.length > 0) {
            Text(opt.glyph)
              .fontSize(17)
              .fontColor(
                this.selectedKey === opt.key
                  ? AppTheme.color.primary
                  : AppTheme.color.textTertiary
              )
          }
          Text(opt.label)
            .fontSize(AppTheme.font.caption)
            .fontWeight(this.selectedKey === opt.key ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(
              this.selectedKey === opt.key
                ? AppTheme.color.textPrimary
                : AppTheme.color.textSecondary
            )
        }
        .height(42)
        .padding({ left: 18, right: 18 })
        .backgroundColor(
          this.selectedKey === opt.key ? AppTheme.color.surfaceGlass : Color.Transparent
        )
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.selectedKey = opt.key;
        })
      }, (opt: SegmentOption) => opt.key)
    }
    .padding(4)
    .backgroundColor(
      this.fillBackground ? AppTheme.color.overlayGlass : Color.Transparent
    )
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.pill)
    .border({ width: 1, color: AppTheme.color.border })
  }
}

@Component
export struct PrimaryPillButton {
  @Prop label: string = '';
  @Prop disabled: boolean = false;

  build() {
    Text(this.label)
      .fontSize(AppTheme.font.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.disabled ? AppTheme.color.textTertiary : AppTheme.color.textOnPrimary)
      .padding({ left: 22, right: 22, top: 11, bottom: 11 })
      .backgroundColor(
        this.disabled ? AppTheme.color.primaryPale : AppTheme.color.primary
      )
      .borderRadius(AppTheme.radius.pill)
      .opacity(this.disabled ? 0.72 : 1)
  }
}

@Component
export struct IconCapsule {
  @Prop glyph: string = '';
  @Prop diameter: number = 42;
  @Prop selected: boolean = false;

  build() {
    Stack() {
      Text(this.glyph)
        .fontSize(this.diameter >= 52 ? 24 : 19)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selected ? AppTheme.color.textPrimary : AppTheme.color.textPrimary)
    }
    .width(this.diameter)
    .height(this.diameter)
    .backgroundColor(this.selected ? AppTheme.color.primaryPale : AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.pill)
    .border({ width: 1, color: AppTheme.color.border })
  }
}

@Component
export struct WatercolorBackground {
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [
            [AppTheme.color.backgroundLight, 0.0],
            [AppTheme.color.background, 0.50],
            [AppTheme.color.backgroundLight, 1.0]
          ]
        })

      Column()
        .width('100%')
        .height('100%')
        .opacity(0.36)
        .linearGradient({
          angle: 35,
          colors: [
            ['rgba(255, 255, 255, 0.0)', 0.0],
            ['rgba(255, 255, 255, 0.74)', 0.42],
            ['rgba(235, 180, 194, 0.26)', 1.0]
          ]
        })
    }
    .width('100%')
    .height('100%')
  }
}
