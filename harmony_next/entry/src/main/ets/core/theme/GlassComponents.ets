import { AppTheme } from './AppTheme';

/**
 * 共享视觉组件：玻璃卡片、胶囊分段、粉色 CTA 按钮。
 * 对齐 temp/design 系列图的视觉：纯白卡 + 柔阴影 + 胶囊圆角。
 */

export interface SegmentOption {
  readonly key: string;
  readonly label: string;
  readonly glyph?: string;
}

@Component
export struct GlassCard {
  @Prop innerPadding: number = AppTheme.spacing.card;
  @Prop cornerRadius: number = AppTheme.radius.card;
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
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(this.cornerRadius)
    .shadow({
      radius: 18,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 6
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
              .fontSize(15)
              .fontColor(
                this.selectedKey === opt.key
                  ? AppTheme.color.primary
                  : AppTheme.color.textSecondary
              )
          }
          Text(opt.label)
            .fontSize(AppTheme.font.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(
              this.selectedKey === opt.key
                ? AppTheme.color.textPrimary
                : AppTheme.color.textSecondary
            )
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(
          this.selectedKey === opt.key ? AppTheme.color.surface : Color.Transparent
        )
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.selectedKey = opt.key;
        })
      }, (opt: SegmentOption) => opt.key)
    }
    .padding(4)
    .backgroundColor(
      this.fillBackground ? AppTheme.color.overlayGlassStrong : Color.Transparent
    )
    .borderRadius(AppTheme.radius.pill)
  }
}

@Component
export struct PrimaryPillButton {
  @Prop label: string = '';
  @Prop disabled: boolean = false;
  private onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(AppTheme.font.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.color.textOnPrimary)
      .padding({ left: 22, right: 22, top: 11, bottom: 11 })
      .backgroundColor(
        this.disabled ? AppTheme.color.primarySoft : AppTheme.color.primary
      )
      .borderRadius(AppTheme.radius.pill)
      .opacity(this.disabled ? 0.6 : 1)
      .onClick(() => {
        if (!this.disabled) {
          this.onTap();
        }
      })
  }
}

@Component
export struct GhostPillButton {
  @Prop label: string = '';
  private onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(AppTheme.font.body)
      .fontColor(AppTheme.color.primary)
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
      .backgroundColor(AppTheme.color.primarySoft)
      .borderRadius(AppTheme.radius.pill)
      .onClick(() => {
        this.onTap();
      })
  }
}

/**
 * 圆形图标胶囊：用于顶部工具栏的单图标按钮（筛选 / 排序 / 搜索 / 更多）。
 */
@Component
export struct IconCapsule {
  @Prop glyph: string = '';
  @Prop diameter: number = 38;
  private onTap: () => void = () => {};

  build() {
    Stack() {
      Text(this.glyph)
        .fontSize(AppTheme.font.titleMedium)
        .fontColor(AppTheme.color.textPrimary)
    }
    .width(this.diameter)
    .height(this.diameter)
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .borderRadius(AppTheme.radius.pill)
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * 页面水彩粉底层：纯色 + 渐变近似，不依赖图片。
 * 放在 Stack 最底层，其他内容叠在其上。
 */
@Component
export struct WatercolorBackground {
  build() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 160,
        colors: [
          [AppTheme.color.backgroundLight, 0.0],
          [AppTheme.color.background, 0.55],
          [AppTheme.color.backgroundLight, 1.0]
        ]
      })
  }
}
