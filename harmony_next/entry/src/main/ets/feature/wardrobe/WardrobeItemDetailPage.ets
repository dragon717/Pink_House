import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';

export class WardrobeDetailArgs {
  name: string = '';
  category: string = '';
  price: number = 0;

  constructor(name: string = '', category: string = '', price: number = 0) {
    this.name = name;
    this.category = category;
    this.price = price;
  }
}

@Component
export struct WardrobeItemDetailPage {
  @Prop args: WardrobeDetailArgs = new WardrobeDetailArgs();
  private pathStack: NavPathStack = new NavPathStack();

  @Builder
  private Header() {
    Row() {
      Row({ space: 5 }) {
        Text('‹')
          .fontSize(28)
          .fontColor(AppTheme.color.primary)
        Text('返回')
          .fontSize(AppTheme.font.body)
          .fontColor(AppTheme.color.primary)
      }
      .width(92)
      .onClick(() => {
        this.pathStack.pop();
      })

      Blank()
        .layoutWeight(1)

      Text('衣橱详情')
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)

      Blank()
        .layoutWeight(1)

      Row({ space: 12 }) {
        AppSymbol({
          name: AppSymbolName.Share,
          iconSize: 19,
          color: AppTheme.color.textPrimary
        })
        AppSymbol({
          name: AppSymbolName.More,
          iconSize: 22,
          color: AppTheme.color.textPrimary
        })
      }
      .width(92)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(54)
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private HeroImage() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height(330)
        .linearGradient({
          angle: 150,
          colors: [
            [AppTheme.color.primaryPale, 0.0],
            [AppTheme.color.surface, 0.48],
            [AppTheme.color.primarySoft, 1.0]
          ]
        })

      Column({ space: 10 }) {
        Text(this.args.category.length > 0 ? this.args.category.substring(0, 1) : '衣')
          .fontSize(94)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
        Text('少女衣橱')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .width('100%')
      .height(330)
      .justifyContent(FlexAlign.Center)

      Text('1 / 5')
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textOnPrimary)
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .backgroundColor('rgba(50, 35, 43, 0.56)')
        .borderRadius(AppTheme.radius.pill)
        .margin({ right: 16, bottom: 16 })
    }
    .width('100%')
  }

  @Builder
  private NameBlock() {
    Column({ space: 8 }) {
      Text(this.args.name.length > 0 ? this.args.name : '未命名衣物')
        .fontSize(AppTheme.font.titleLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
        .maxLines(2)

      Row({ space: 8 }) {
        Text('Lolita')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.primary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(AppTheme.color.primaryPale)
          .borderRadius(AppTheme.radius.pill)
        Text(this.args.category.length > 0 ? this.args.category : '未分类')
          .fontSize(AppTheme.font.tiny)
          .fontColor(AppTheme.color.textSecondary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(AppTheme.color.surfaceTint)
          .borderRadius(AppTheme.radius.pill)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 18 })
  }

  @Builder
  private InfoRow(symbolName: string, label: string, value: string) {
    Row() {
      AppSymbol({
        name: symbolName,
        iconSize: 18,
        color: AppTheme.color.primary
      })
        .width(24)
      Text(label)
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.textSecondary)
      Blank()
        .layoutWeight(1)
      Text(value)
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.textPrimary)
    }
    .width('100%')
    .height(42)
  }

  @Builder
  private InfoSection() {
    Column() {
      GlassCard({ innerPadding: 16, cornerRadius: AppTheme.radius.card }) {
        Column({ space: 4 }) {
          Text('裙装信息')
            .fontSize(AppTheme.font.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textPrimary)
            .width('100%')

          this.InfoRow(AppSymbolName.Info, '类型', this.args.category.length > 0 ? this.args.category : '未分类');
          this.InfoRow(AppSymbolName.Color, '颜色', '粉白');
          this.InfoRow(AppSymbolName.Size, '尺码', 'S');
          this.InfoRow(AppSymbolName.Length, '衣长', '未填写');
          this.InfoRow(AppSymbolName.State, '状态', '全新');
          this.InfoRow(AppSymbolName.Spark, '小物', '无');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .margin({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 16 })
  }

  @Builder
  private PriceSection() {
    Column() {
      GlassCard({ innerPadding: 16, cornerRadius: AppTheme.radius.card }) {
        Column({ space: 10 }) {
          Text('价格信息')
            .fontSize(AppTheme.font.body)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textPrimary)
            .width('100%')

          Row() {
            Text('总价')
              .fontSize(AppTheme.font.body)
              .fontColor(AppTheme.color.textSecondary)
            Blank()
              .layoutWeight(1)
            Text(`¥${Math.round(this.args.price)}`)
              .fontSize(AppTheme.font.titleMedium)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.textPrimary)
          }
          .width('100%')

          Row() {
            Text('总尾款')
              .fontSize(AppTheme.font.body)
              .fontColor(AppTheme.color.textSecondary)
            Blank()
              .layoutWeight(1)
            Text(`¥${Math.round(this.args.price * 0.6)}`)
              .fontSize(AppTheme.font.titleMedium)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.primary)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .margin({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 16, bottom: 120 })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.Header();
          this.HeroImage();
          this.NameBlock();
          this.InfoSection();
          this.PriceSection();
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.color.backgroundLight)
      .scrollBar(BarState.Off)
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}
