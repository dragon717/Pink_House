import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';

interface HotspotSpec {
  readonly title: string;
  readonly symbolName: string;
  readonly destination: string;
  readonly xPct: number;
  readonly yPct: number;
}

// iOS 房间图原始宽高比 1859:1593 ≈ 1.167:1
// 两张图 VStack(spacing: -80pt) 堆叠，总高 ≈ 2 * imgH - overlap
const ROOM_IMAGE_RATIO: number = 1593 / 1859;
const ROOM_OVERLAP_RATIO: number = 0.06;

// 热点坐标为占整个地图区域(两张图堆叠后)的百分比
// 参考 iOS RococoSmallWorldView 的 hotspot rect/label position
const HOUSE_HOTSPOTS: HotspotSpec[] = [
  { title: '少女衣橱', symbolName: AppSymbolName.Wardrobe, destination: 'wardrobe', xPct: 0.52, yPct: 0.12 },
  { title: '穿搭手帐', symbolName: AppSymbolName.Outfit, destination: 'ootd', xPct: 0.41, yPct: 0.42 },
  { title: '马上来财', symbolName: AppSymbolName.Wealth, destination: 'wealth', xPct: 0.52, yPct: 0.44 },
  { title: '心愿尾款', symbolName: AppSymbolName.Deposit, destination: 'deposit', xPct: 0.10, yPct: 0.66 },
  { title: '梦裙日历', symbolName: AppSymbolName.Calendar, destination: 'calendar', xPct: 0.45, yPct: 0.82 },
  { title: '拼豆工坊', symbolName: AppSymbolName.Perler, destination: 'perler', xPct: 0.78, yPct: 0.62 }
];

@Component
export struct SmallWorldPage {
  @Link destination: string;
  onOpenWardrobe: (segment: string) => void = () => {};
  @State private mapWidth: number = 0;

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

  private roomImageHeight(): number {
    const usableWidth = this.mapWidth > 0 ? this.mapWidth - 36 : 320;
    return usableWidth * ROOM_IMAGE_RATIO;
  }

  private mapTotalHeight(): number {
    const singleH = this.roomImageHeight();
    const overlap = singleH * ROOM_OVERLAP_RATIO;
    return singleH * 2 - overlap + 20;
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
    .position({
      x: `${(item.xPct * 100).toFixed(1)}%`,
      y: `${(item.yPct * 100).toFixed(1)}%`
    })
    .onClick(() => {
      if (item.destination === 'wardrobe') {
        this.onOpenWardrobe('wardrobe');
      } else if (item.destination === 'deposit') {
        this.onOpenWardrobe('deposit');
      } else {
        this.destination = item.destination;
      }
    })
  }

  @Builder
  private HouseMap() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: -(this.roomImageHeight() * ROOM_OVERLAP_RATIO) }) {
          Image($r('app.media.small_world_rococo_1'))
            .width('100%')
            .height(this.roomImageHeight())
            .objectFit(ImageFit.Contain)
          Image($r('app.media.small_world_rococo_2'))
            .width('100%')
            .height(this.roomImageHeight())
            .objectFit(ImageFit.Contain)
        }
        .width('100%')
        .padding({ top: 10 })

        ForEach(HOUSE_HOTSPOTS, (item: HotspotSpec) => {
          this.Hotspot(item);
        }, (item: HotspotSpec) => item.destination)
      }
      .width('100%')
      .height(this.mapTotalHeight())
      .padding({ left: 18, right: 18, top: 10, bottom: 130 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      if (w > 0) {
        this.mapWidth = w;
      }
    })
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
                  this.onOpenWardrobe('wardrobe');
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
