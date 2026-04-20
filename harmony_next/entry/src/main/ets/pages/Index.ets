import { AppRoute, HOME_TABS, RouteTab } from '../core/navigation/AppRoute';
import { AppTheme } from '../core/theme/AppTheme';
import { FeatureDescriptor } from '../domain/model/FeatureDescriptor';
import { GetHomeFeaturesUseCase } from '../domain/usecase/GetHomeFeaturesUseCase';
import { WardrobePage } from '../feature/wardrobe/WardrobePage';
import { PetPage } from '../feature/pet/PetPage';
import { SmallWorldPage } from '../feature/smallworld/SmallWorldPage';
import { WealthPage } from '../feature/wealth/WealthPage';
import { VipPage } from '../feature/vip/VipPage';
import { SettingsPage } from '../feature/settings/SettingsPage';

@Entry
@Component
struct Index {
  @State private selectedRoute: AppRoute = AppRoute.Wardrobe;
  private readonly features: FeatureDescriptor[] = new GetHomeFeaturesUseCase().execute();

  @Builder
  private Header() {
    Column({ space: 8 }) {
      Text('少女心愿 HarmonyOS Next')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
      Text('Stage + ArkTS + ArkUI 工程骨架，已预留 RDB、Preferences、HMS IAP、提醒、天气和服务卡片扩展点。')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 8 })
  }

  @Builder
  private RouteTabs() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(HOME_TABS, (tab: RouteTab) => {
          Button(tab.title)
            .fontSize(14)
            .fontColor(this.selectedRoute === tab.route ? '#FFFFFF' : AppTheme.color.primary)
            .backgroundColor(this.selectedRoute === tab.route ? AppTheme.color.primary : AppTheme.color.primarySoft)
            .borderRadius(AppTheme.radius.pill)
            .onClick(() => {
              this.selectedRoute = tab.route;
            })
        }, (tab: RouteTab) => tab.route)
      }
      .padding({ top: 4, bottom: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private FeatureContent() {
    if (this.selectedRoute === AppRoute.Wardrobe) {
      WardrobePage();
    } else if (this.selectedRoute === AppRoute.Pet) {
      PetPage();
    } else if (this.selectedRoute === AppRoute.SmallWorld) {
      SmallWorldPage();
    } else if (this.selectedRoute === AppRoute.Wealth) {
      WealthPage();
    } else if (this.selectedRoute === AppRoute.Vip) {
      VipPage();
    } else {
      SettingsPage();
    }
  }

  @Builder
  private MilestoneList() {
    Column({ space: 10 }) {
      Text('首批工程占位')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)

      ForEach(this.features, (feature: FeatureDescriptor) => {
        Row({ space: 12 }) {
          Text(feature.milestone)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.color.primary)
            .width(54)
          Column({ space: 3 }) {
            Text(feature.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.color.textPrimary)
            Text(feature.description)
              .fontSize(13)
              .lineHeight(18)
              .fontColor(AppTheme.color.textSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .backgroundColor(AppTheme.color.surface)
        .borderRadius(16)
        .border({ width: 1, color: AppTheme.color.border })
      }, (feature: FeatureDescriptor) => feature.route)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [[AppTheme.color.background, 0.0], ['#FFFDF8', 0.52], ['#F8FBFF', 1.0]]
        })

      Scroll() {
        Column({ space: 18 }) {
          this.Header();
          this.RouteTabs();
          this.FeatureContent();
          this.MilestoneList();
        }
        .width('100%')
        .padding(AppTheme.spacing.page)
      }
      .width('100%')
      .height('100%')
    }
  }
}
