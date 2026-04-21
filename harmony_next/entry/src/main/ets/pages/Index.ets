import { AppTheme } from '../core/theme/AppTheme';
import { WatercolorBackground } from '../core/theme/GlassComponents';
import { WardrobePage } from '../feature/wardrobe/WardrobePage';
import { SmallWorldPage } from '../feature/smallworld/SmallWorldPage';
import { MePage } from '../feature/me/MePage';
import { PetPage } from '../feature/pet/PetPage';

/**
 * 底部胶囊导航三入口对齐 temp/design：衣橱 / House（动态中位）/ 我。
 * 聊天入口走右侧独立 FAB，不占 tab。点击 FAB 以模态方式进入 PetPage。
 * 参考 iOS MainTabView（ItemManager/Views/MainTabView.swift）：
 * 4 入口 + 聊天 search role 的结构，鸿蒙 Next 按跨端 PRD 子集改为 3 tab + FAB。
 */

interface BottomTabItem {
  readonly index: number;
  readonly label: string;
  readonly glyph: string;
}

const BOTTOM_TABS: BottomTabItem[] = [
  { index: 0, label: '衣橱', glyph: '👗' },
  { index: 1, label: 'House', glyph: '🏠' },
  { index: 2, label: '我', glyph: '🙂' }
];

@Entry
@Component
struct Index {
  @State private currentIndex: number = 0;
  @State private isChatOpen: boolean = false;

  @Builder
  private ActiveContent() {
    if (this.currentIndex === 0) {
      WardrobePage();
    } else if (this.currentIndex === 1) {
      SmallWorldPage();
    } else {
      MePage();
    }
  }

  @Builder
  private TabSlot(item: BottomTabItem) {
    Column({ space: 2 }) {
      Stack() {
        // 选中态粉色光晕
        if (this.currentIndex === item.index) {
          Circle({ width: 36, height: 36 })
            .fill(AppTheme.color.primaryHalo)
            .opacity(0.55)
        }
        Text(item.glyph)
          .fontSize(20)
      }
      .width(40)
      .height(32)
      .alignContent(Alignment.Center)

      Text(item.label)
        .fontSize(AppTheme.font.tiny)
        .fontWeight(this.currentIndex === item.index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(
          this.currentIndex === item.index
            ? AppTheme.color.primary
            : AppTheme.color.textSecondary
        )
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick(() => {
      this.currentIndex = item.index;
    })
  }

  @Builder
  private BottomBar() {
    Row({ space: 10 }) {
      // 三入口胶囊容器
      Row({ space: 0 }) {
        ForEach(BOTTOM_TABS, (item: BottomTabItem) => {
          this.TabSlot(item);
        }, (item: BottomTabItem) => item.index.toString())
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(AppTheme.color.overlayGlassStrong)
      .backgroundBlurStyle(BlurStyle.Regular)
      .borderRadius(AppTheme.radius.pill)
      .shadow({
        radius: 22,
        color: AppTheme.color.shadowSoft,
        offsetX: 0,
        offsetY: 6
      })

      // 聊天 FAB
      Stack() {
        Text('💬')
          .fontSize(22)
      }
      .width(56)
      .height(56)
      .backgroundColor(AppTheme.color.overlayGlassStrong)
      .backgroundBlurStyle(BlurStyle.Regular)
      .borderRadius(AppTheme.radius.pill)
      .shadow({
        radius: 22,
        color: AppTheme.color.shadowSoft,
        offsetX: 0,
        offsetY: 6
      })
      .onClick(() => {
        this.isChatOpen = true;
      })
    }
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, bottom: 18 })
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ChatSheet() {
    Column() {
      PetPage();
      Row() {
        Text('关闭')
          .fontSize(AppTheme.font.body)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 22, right: 22, top: 11, bottom: 11 })
          .backgroundColor(AppTheme.color.primary)
          .borderRadius(AppTheme.radius.pill)
          .onClick(() => {
            this.isChatOpen = false;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.color.backgroundLight)
  }

  build() {
    Stack() {
      WatercolorBackground();

      // 主内容，底部留白避开悬浮 bar
      Column() {
        this.ActiveContent();
      }
      .width('100%')
      .height('100%')

      // 底部悬浮壳层
      Column() {
        this.BottomBar();
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .bindSheet($$this.isChatOpen, this.ChatSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      backgroundColor: AppTheme.color.backgroundLight
    })
  }
}
