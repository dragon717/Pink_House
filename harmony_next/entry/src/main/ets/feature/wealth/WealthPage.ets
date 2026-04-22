import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';

const FORTUNE_RESULTS: string[][] = [
  ['上签', '积少成多，稳步前行', '财运渐入佳境，坚持储蓄必有回报。'],
  ['上签', '好运将至，万事顺遂', '近日财运亨通，宜把握良机。'],
  ['中签', '平稳度日，细水长流', '财运平稳，不宜冒进，稳扎稳打为上。'],
  ['中签', '守正待时，厚积薄发', '虽无大财，但积累可期，耐心等待。'],
  ['下签', '量入为出，谨慎理财', '近期财运欠佳，宜节俭度日，避免冲动消费。'],
  ['下签', '风雨之后，终见彩虹', '暂时困难，但只要坚持，终会好转。']
];

const CURRENCY_OPTIONS: string[] = ['人民币', '日元', '美刀'];
const ASSET_TYPES: string[] = ['黄金', '白银', '虚拟'];

@Component
export struct WealthPage {
  @State private selectedTab: string = 'divination';
  @State private fortuneIndex: number = -1;
  @State private selectedCurrency: number = 0;
  @State private selectedAssetType: number = 0;
  @State private swiperIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();

  private drawFortune(): void {
    this.fortuneIndex = Math.floor(Math.random() * FORTUNE_RESULTS.length);
  }

  private tabLabel(key: string): string {
    switch (key) {
      case 'divination': return '请签';
      case 'moneyCounting': return '数钱';
      case 'wealthStorage': return '安财';
      default: return '';
    }
  }

  @Builder
  private TabButton(key: string, index: number) {
    Text(this.tabLabel(key))
      .fontSize(AppTheme.font.body)
      .fontWeight(this.selectedTab === key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedTab === key ? AppTheme.color.textPrimary : AppTheme.color.textSecondary)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.selectedTab === key ? AppTheme.color.surfaceGlass : Color.Transparent)
      .borderRadius(AppTheme.radius.pill)
      .onClick(() => {
        this.selectedTab = key;
        this.swiperController.changeIndex(index);
      })
  }

  @Builder
  private TopBar() {
    Row() {
      Row({ space: 2 }) {
        this.TabButton('divination', 0);
        this.TabButton('moneyCounting', 1);
        this.TabButton('wealthStorage', 2);
      }
      .padding(4)
      .backgroundColor(AppTheme.color.overlayGlass)
      .backgroundBlurStyle(BlurStyle.Thin)
      .borderRadius(AppTheme.radius.pill)
      .border({ width: 1, color: AppTheme.color.border })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 14, bottom: 8 })
  }

  @Builder
  private DivinationPage() {
    Column({ space: 24 }) {
      Blank().height(40)

      if (this.fortuneIndex >= 0) {
        GlassCard({ innerPadding: 0, cornerRadius: 24 }) {
          Column({ space: 0 }) {
            Column() {
              Text(FORTUNE_RESULTS[this.fortuneIndex][0])
                .fontSize(56)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.textPrimary)
            }
            .width('100%')
            .height(260)
            .justifyContent(FlexAlign.Center)
            .linearGradient({
              angle: 180,
              colors: [
                ['rgba(201, 169, 110, 0.15)', 0.0],
                ['rgba(201, 169, 110, 0.05)', 1.0]
              ]
            })
            .borderRadius({ topLeft: 24, topRight: 24 })

            Column({ space: 8 }) {
              Text(`✨ ${FORTUNE_RESULTS[this.fortuneIndex][1]} ✨`)
                .fontSize(AppTheme.font.titleMedium)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.textPrimary)
                .textAlign(TextAlign.Center)
                .width('100%')
              Text(FORTUNE_RESULTS[this.fortuneIndex][2])
                .fontSize(AppTheme.font.body)
                .fontColor(AppTheme.color.textSecondary)
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            .padding(20)
          }
          .width('100%')
        }
      } else {
        GlassCard({ innerPadding: 32, cornerRadius: 24 }) {
          Column({ space: 16 }) {
            Text('🏮')
              .fontSize(80)
            Text('点击下方按钮求签')
              .fontSize(AppTheme.font.body)
              .fontColor(AppTheme.color.textSecondary)
          }
          .width('100%')
          .height(280)
          .justifyContent(FlexAlign.Center)
        }
      }

      Text('再求一签')
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
        .padding({ left: 36, right: 36, top: 14, bottom: 14 })
        .backgroundColor('#8B4513')
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.drawFortune();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
  }

  @Builder
  private CurrencyChip(label: string, index: number) {
    Text(label)
      .fontSize(AppTheme.font.caption)
      .fontWeight(this.selectedCurrency === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedCurrency === index ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.selectedCurrency === index ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong)
      .borderRadius(AppTheme.radius.pill)
      .onClick(() => {
        this.selectedCurrency = index;
      })
  }

  @Builder
  private MoneyCountingPage() {
    Column({ space: 24 }) {
      Row({ space: 8 }) {
        ForEach(CURRENCY_OPTIONS, (label: string, index: number) => {
          this.CurrencyChip(label, index);
        }, (label: string) => label)
      }
      .padding({ top: 18 })

      Column({ space: 8 }) {
        Text(CURRENCY_OPTIONS[this.selectedCurrency] === '人民币' ? 'CNY' :
          CURRENCY_OPTIONS[this.selectedCurrency] === '日元' ? 'JPY' : 'USD')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
        Text('0')
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor('#C9A96E')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Text('已购入小裙装总价 + 心愿尾款已付总定金')
        .fontSize(AppTheme.font.tiny)
        .fontColor(AppTheme.color.textTertiary)

      Blank().height(30)

      GlassCard({ innerPadding: 24, cornerRadius: AppTheme.radius.cardLarge }) {
        Column({ space: 12 }) {
          Text('点击上方金额开始数钱')
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textSecondary)
            .textAlign(TextAlign.Center)
            .width('100%')
          Text('纸币堆叠动画（待实现）')
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.textTertiary)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
  }

  @Builder
  private AssetChip(label: string, index: number) {
    Text(label)
      .fontSize(AppTheme.font.caption)
      .fontWeight(this.selectedAssetType === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedAssetType === index ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.selectedAssetType === index ? AppTheme.color.primaryStrong : AppTheme.color.overlayGlassStrong)
      .borderRadius(AppTheme.radius.pill)
      .onClick(() => {
        this.selectedAssetType = index;
      })
  }

  @Builder
  private WealthStoragePage() {
    Column({ space: 24 }) {
      Row({ space: 8 }) {
        ForEach(ASSET_TYPES, (label: string, index: number) => {
          this.AssetChip(label, index);
        }, (label: string) => label)
      }
      .padding({ top: 18 })

      Column({ space: 8 }) {
        Text('0.00')
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor('#C9A96E')
        Text(ASSET_TYPES[this.selectedAssetType] === '黄金' ? '克' :
          ASSET_TYPES[this.selectedAssetType] === '白银' ? '克' : '枚')
          .fontSize(AppTheme.font.titleMedium)
          .fontColor(AppTheme.color.textSecondary)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      Row({ space: 4 }) {
        Text('金价:')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textTertiary)
        Text('--- CNY/g')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textTertiary)
        Blank().layoutWeight(1)
        Text('数据来源: Gold-API.com')
          .fontSize(9)
          .fontColor(AppTheme.color.textTertiary)
      }
      .width('100%')

      Blank().height(20)

      GlassCard({ innerPadding: 24, cornerRadius: AppTheme.radius.cardLarge }) {
        Column({ space: 12 }) {
          Text('金豆物理模拟（待实现）')
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textSecondary)
            .textAlign(TextAlign.Center)
            .width('100%')
          Text('此处将展示衣橱总值折算的贵金属重量，配合金豆掉落动画')
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.textTertiary)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
  }

  build() {
    Column() {
      this.TopBar();

      Swiper(this.swiperController) {
        this.DivinationPage();
        this.MoneyCountingPage();
        this.WealthStoragePage();
      }
      .index(this.swiperIndex)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.swiperIndex = index;
        const tabs: string[] = ['divination', 'moneyCounting', 'wealthStorage'];
        this.selectedTab = tabs[index];
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
