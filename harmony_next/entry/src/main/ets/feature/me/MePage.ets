import { AppTheme } from '../../core/theme/AppTheme';
import { GlassCard } from '../../core/theme/GlassComponents';

/**
 * "我" 页占位：对齐 IMG_8205 的 VIP 卡 + 卡片矩阵骨架。
 * P3 阶段再补上真实数据、VIP 序号动效、魔法任务等。
 */
@Component
export struct MePage {
  @Builder
  private VipCard() {
    Column({ space: 10 }) {
      Row() {
        Text('少女心愿 VIP')
          .fontSize(AppTheme.font.titleMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textOnPrimary)
        Blank()
        Text('梦幻限定')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('rgba(255, 255, 255, 0.28)')
          .borderRadius(AppTheme.radius.pill)
      }
      .width('100%')

      Text('0490  48')
        .fontSize(AppTheme.font.displayMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
        .letterSpacing(4)

      Text('VALID THRU  2026/6/6')
        .fontSize(AppTheme.font.tiny)
        .fontColor('rgba(255, 255, 255, 0.78)')
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 18, bottom: 18 })
    .linearGradient({
      angle: 135,
      colors: [['#F2C4CE', 0.0], ['#E9A0B0', 0.55], ['#D98294', 1.0]]
    })
    .borderRadius(AppTheme.radius.cardLarge)
    .shadow({
      radius: 22,
      color: AppTheme.color.shadowSoft,
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private EntryCard(title: string, subtitle: string, glyph: string) {
    Row({ space: 12 }) {
      Stack() {
        Text(glyph)
          .fontSize(22)
      }
      .width(44)
      .height(44)
      .backgroundColor(AppTheme.color.primarySoft)
      .borderRadius(14)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.textPrimary)
        Text(subtitle)
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('我')
          .fontSize(AppTheme.font.displayMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
          .alignSelf(ItemAlign.Start)
          .padding({ top: 8, bottom: 4 })

        this.VipCard()

        this.EntryCard('魔法任务', '完成任务解锁更多功能', '✦')

        Row({ space: 12 }) {
          Column() { this.EntryCard('梦幻衣橱', '外观 · 随机 · 提醒', '👗') }
            .layoutWeight(1)
          Column() { this.EntryCard('House', '场景与功能地图', '🏠') }
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 12 }) {
          Column() { this.EntryCard('智能萌宠', '陪伴 · 聊天 · 投喂', '🐾') }
            .layoutWeight(1)
          Column() { this.EntryCard('备份资料', '云同步占位', '☁︎') }
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 12, bottom: 120 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
