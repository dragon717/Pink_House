import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';

interface HotspotSpec {
  readonly title: string;
  readonly symbolName: string;
  readonly destination: string;
  readonly x: number;
  readonly y: number;
  readonly tint: string;
}

const HOUSE_HOTSPOTS: HotspotSpec[] = [
  { title: '少女衣橱', symbolName: AppSymbolName.Wardrobe, destination: 'wardrobe', x: 58, y: 46, tint: '#FFFFFF' },
  { title: '穿搭手帐', symbolName: AppSymbolName.Outfit, destination: 'ootd', x: 34, y: 242, tint: '#FFFFFF' },
  { title: '马上来财', symbolName: AppSymbolName.Wealth, destination: 'wealth', x: 190, y: 238, tint: '#FFFFFF' },
  { title: '心愿尾款', symbolName: AppSymbolName.Deposit, destination: 'deposit', x: 26, y: 452, tint: '#FFFFFF' },
  { title: '梦裙日历', symbolName: AppSymbolName.Calendar, destination: 'calendar', x: 112, y: 544, tint: '#FFFFFF' },
  { title: '拼豆工坊', symbolName: AppSymbolName.Perler, destination: 'perler', x: 246, y: 470, tint: '#FFFFFF' }
];

@Component
export struct SmallWorldPage {
  @Link destination: string;
  onOpenWardrobe: () => void = () => {};

  private destinationTitle(): string {
    switch (this.destination) {
      case 'wealth':
        return '马上来财';
      case 'ootd':
        return '穿搭手帐';
      case 'calendar':
        return '梦裙日历';
      case 'perler':
        return '拼豆工坊';
      case 'deposit':
        return '心愿尾款';
      default:
        return 'House';
    }
  }

  @Builder
  private Header() {
    Row() {
      if (this.destination !== 'menu') {
        Text('‹ House')
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
          .onClick(() => {
            this.destination = 'menu';
          })
      } else {
        Text('House')
          .fontSize(AppTheme.font.displayMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
      }

      Blank()
        .layoutWeight(1)

      AppSymbol({
        name: AppSymbolName.Import,
        iconSize: 28,
        color: AppTheme.color.textOnPrimary
      })
        .width(54)
        .height(54)
        .backgroundColor('rgba(255, 255, 255, 0.30)')
        .borderRadius(AppTheme.radius.pill)
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 18 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private RoomBlock(title: string, tint: string, height: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(height)
        .linearGradient({
          angle: 135,
          colors: [
            [tint, 0.0],
            ['rgba(255, 255, 255, 0.72)', 0.62],
            [AppTheme.color.surfaceTint, 1.0]
          ]
        })
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.82)' })

      Text(title)
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor('rgba(255, 255, 255, 0.92)')
        .rotate({ angle: -22 })
        .margin({ top: 20, left: 18 })
    }
    .width('100%')
    .height(height)
  }

  @Builder
  private Hotspot(item: HotspotSpec) {
    Row({ space: 6 }) {
      AppSymbol({
        name: item.symbolName,
        iconSize: 20,
        color: AppTheme.color.textOnPrimary
      })
      Text(item.title)
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor('rgba(50, 35, 43, 0.30)')
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.pill)
    .rotate({ angle: -22 })
    .position({ x: item.x, y: item.y })
    .onClick(() => {
      if (item.destination === 'wardrobe') {
        this.onOpenWardrobe();
      } else {
        this.destination = item.destination;
      }
    })
  }

  @Builder
  private HouseMap() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 46 }) {
          Stack({ alignContent: Alignment.Center }) {
            this.RoomBlock('少女衣橱', '#F7D7E1', 300);
            Row({ space: 18 }) {
              this.RoomBlock('卧室', '#F5C7D7', 220);
              this.RoomBlock('梳妆间', '#F8E2CB', 220);
            }
            .width('92%')
            .margin({ top: 46 })
          }
          .width('100%')
          .height(360)

          Stack({ alignContent: Alignment.Center }) {
            this.RoomBlock('心愿屋', '#F4CCD8', 330);
            Row({ space: 18 }) {
              this.RoomBlock('日历角', '#F7E4C8', 240);
              this.RoomBlock('工坊', '#EED5E8', 240);
            }
            .width('92%')
            .margin({ top: 62 })
          }
          .width('100%')
          .height(380)
        }
        .width('100%')

        ForEach(HOUSE_HOTSPOTS, (item: HotspotSpec) => {
          this.Hotspot(item);
        }, (item: HotspotSpec) => item.destination)
      }
      .width('100%')
      .height(790)
      .padding({ left: 18, right: 18, top: 10, bottom: 130 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private DestinationSkeleton() {
    Scroll() {
      Column({ space: 16 }) {
        this.Header();

        Column() {
          GlassCard({ innerPadding: 22, cornerRadius: AppTheme.radius.cardLarge }) {
            Column({ space: 14 }) {
              Text(this.destinationTitle())
                .fontSize(AppTheme.font.displayMedium)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.textPrimary)
                .width('100%')

              Text('这是从 House 热区进入的 HarmonyOS Next 子集骨架。这里保留本地数据、普通动效和页面入口，不显示 AI、CloudKit、RealityKit 或裙子股市。')
                .fontSize(AppTheme.font.body)
                .lineHeight(24)
                .fontColor(AppTheme.color.textSecondary)
                .width('100%')

              Row({ space: 12 }) {
                this.ActionTile('返回 House', AppSymbolName.House, () => {
                  this.destination = 'menu';
                });
                this.ActionTile('去衣橱', AppSymbolName.Wardrobe, () => {
                  this.onOpenWardrobe();
                });
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .margin({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
      }
      .width('100%')
      .padding({ bottom: 130 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  private ActionTile(label: string, symbolName: string, onTap: () => void) {
    Column({ space: 8 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 30,
        color: AppTheme.color.primary
      })
      Text(label)
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
    }
    .layoutWeight(1)
    .height(92)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.color.surfaceTint)
    .borderRadius(AppTheme.radius.tile)
    .onClick(onTap)
  }

  build() {
    Column() {
      if (this.destination === 'menu') {
        this.Header();
        this.HouseMap();
      } else {
        this.DestinationSkeleton();
      }
    }
    .width('100%')
    .height('100%')
  }
}
