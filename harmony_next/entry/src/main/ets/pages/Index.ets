import { AppTheme } from '../core/theme/AppTheme';
import { WatercolorBackground } from '../core/theme/GlassComponents';
import { AppSymbol, AppSymbolName } from '../core/theme/AppSymbols';
import { WardrobePage } from '../feature/wardrobe/WardrobePage';
import { SmallWorldPage } from '../feature/smallworld/SmallWorldPage';
import { MePage } from '../feature/me/MePage';
import { PetPage } from '../feature/pet/PetPage';

interface BottomTabItem {
  readonly index: number;
  readonly label: string;
  readonly symbolName: string;
}

const MAIN_TABS: BottomTabItem[] = [
  { index: 0, label: '衣橱', symbolName: AppSymbolName.Wardrobe },
  { index: 1, label: 'House', symbolName: AppSymbolName.House },
  { index: 2, label: '我', symbolName: AppSymbolName.Me }
];

@Entry
@Component
struct Index {
  @State private currentIndex: number = 0;
  @State private wardrobeSegment: string = 'wardrobe';
  @State private smallWorldDestination: string = 'menu';
  @State private isPetOpen: boolean = false;
  private tabsController: TabsController = new TabsController();

  private houseTitle(): string {
    switch (this.smallWorldDestination) {
      case 'wealth':
        return '来财';
      case 'ootd':
        return '穿搭手帐';
      case 'calendar':
        return '梦裙日历';
      case 'perler':
        return '拼豆工坊';
      case 'deposit':
        return '心愿尾款';
      case 'wardrobe':
        return '衣橱';
      default:
        return 'House';
    }
  }

  @Builder
  private MainTabs() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
      TabContent() {
      WardrobePage({
        selectedSegment: $wardrobeSegment,
        onOpenHouse: (destination: string) => {
          this.openHouse(destination);
        }
      })
      }
      .tabBar(this.MainTabBar(MAIN_TABS[0]))

      TabContent() {
      SmallWorldPage({
        destination: $smallWorldDestination,
        onOpenWardrobe: (segment: string) => {
          this.wardrobeSegment = segment;
          this.smallWorldDestination = 'menu';
          this.switchMainTab(0);
        }
      })
      }
      .tabBar(this.MainTabBar(MAIN_TABS[1]))

      TabContent() {
      MePage({
        onOpenHouse: (destination: string) => {
          this.openHouse(destination);
        },
        onOpenPet: () => {
          this.openPet();
        }
      })
      }
      .tabBar(this.MainTabBar(MAIN_TABS[2]))
    }
    .width('100%')
    .height('100%')
    .barHeight(92)
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .barBackgroundColor(AppTheme.color.overlayGlassStrong)
    .divider(null)
    .onChange((index: number) => {
      this.currentIndex = index;
      this.isPetOpen = false;
    })
  }

  @Builder
  private ActiveContent() {
    if (this.isPetOpen) {
      PetPage({
        onOpenWardrobe: () => {
          this.switchMainTab(0);
        }
      })
    } else {
      this.MainTabs();
    }
  }

  @Builder
  private MainTabBar(item: BottomTabItem) {
    Column({ space: 3 }) {
      Stack() {
        if (this.currentIndex === item.index) {
          Circle({ width: 48, height: 36 })
            .fill(AppTheme.color.primaryMist)
        }
        AppSymbol({
          name: item.symbolName,
          iconSize: item.index === 1 ? 28 : 25,
          color: this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary
        })
      }
      .width(68)
      .height(38)
      .alignContent(Alignment.Center)

      Text(item.index === 1 ? this.houseTitle() : item.label)
        .fontSize(AppTheme.font.caption)
        .fontWeight(this.currentIndex === item.index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary)
        .maxLines(1)
    }
    .width('100%')
    .height(74)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (item.index === 1 && this.currentIndex === 1 && this.smallWorldDestination !== 'menu') {
        this.smallWorldDestination = 'menu';
      }
      this.switchMainTab(item.index);
    })
  }

  @Builder
  private PetEntryOverlay() {
    if (!this.isPetOpen && this.currentIndex !== 1) {
      Stack({ alignContent: Alignment.Bottom }) {
        Image($r('app.media.pet_cat_peek'))
          .width(96)
          .height(62)
          .objectFit(ImageFit.Contain)
      }
      .width(108)
      .height(64)
      .margin({ bottom: 70 })
      .onClick(() => {
        this.openPet();
      })
    }
  }

  private openHouse(destination: string): void {
    if (destination === 'wardrobe' || destination === 'deposit') {
      this.wardrobeSegment = destination === 'deposit' ? 'deposit' : 'wardrobe';
      this.smallWorldDestination = 'menu';
      this.switchMainTab(0);
      return;
    }
    this.smallWorldDestination = destination;
    this.switchMainTab(1);
  }

  private openPet(): void {
    this.isPetOpen = true;
  }

  private switchMainTab(index: number): void {
    this.currentIndex = index;
    this.isPetOpen = false;
    this.tabsController.changeIndex(index);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      WatercolorBackground();

      Column() {
        this.ActiveContent();
      }
      .width('100%')
      .height('100%')

      this.PetEntryOverlay();
    }
    .width('100%')
    .height('100%')
  }
}
