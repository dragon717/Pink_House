import { AppTheme } from '../core/theme/AppTheme';

export interface FeatureShellOptions {
  readonly title: string;
  readonly badge: string;
  readonly description: string;
  readonly checklist: string[];
}

@Component
export struct FeatureShell {
  @Prop title: string = '';
  @Prop badge: string = '';
  @Prop description: string = '';
  @Prop checklist: string[] = [];

  build() {
    Column({ space: 14 }) {
      Row() {
        Text(this.title)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text(this.badge)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.primary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.color.primarySoft)
          .borderRadius(AppTheme.radius.pill)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Text(this.description)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(AppTheme.color.textSecondary)

      Column({ space: 8 }) {
        ForEach(this.checklist, (item: string) => {
          Row({ space: 8 }) {
            Text('•')
              .fontSize(16)
              .fontColor(AppTheme.color.primary)
            Text(item)
              .fontSize(14)
              .fontColor(AppTheme.color.textPrimary)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: string) => item)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(AppTheme.color.surface)
      .borderRadius(18)
      .border({ width: 1, color: AppTheme.color.border })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }
}
