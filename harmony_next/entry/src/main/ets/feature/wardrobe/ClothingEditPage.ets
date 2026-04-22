import { AppTheme } from '../../core/theme/AppTheme';
import { GlassCard } from '../../core/theme/GlassComponents';
import { WardrobeCategory } from '../../domain/model/WardrobeItem';

const CATEGORY_KEYS: string[] = Object.keys(WardrobeCategory);
const CATEGORY_LABELS: string[] = Object.values(WardrobeCategory);

@Component
export struct ClothingEditPage {
  onSave: (draft: ClothingDraft) => void = () => {};
  onCancel: () => void = () => {};

  @State private draft: ClothingDraft = new ClothingDraft();
  @State private showCategoryPicker: boolean = false;

  private formatDate(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  @Builder
  private Header() {
    Row() {
      Text('取消')
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.primary)
        .onClick(() => { this.onCancel(); })

      Blank().layoutWeight(1)

      Text('新建裙装')
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)

      Blank().layoutWeight(1)

      Text('保存')
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.draft.draftName.length > 0 ? AppTheme.color.primary : AppTheme.color.textTertiary)
        .onClick(() => {
          if (this.draft.draftName.length > 0) {
            this.onSave(this.draft);
          }
        })
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 14, bottom: 10 })
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(AppTheme.font.titleMedium)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.color.textPrimary)
      .margin({ bottom: 4 })
  }

  @Builder
  private FormField(label: string, placeholder: string, value: string, onChange: (v: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.textPrimary)
        .placeholderColor(AppTheme.color.textTertiary)
        .backgroundColor(AppTheme.color.surfaceTint)
        .borderRadius(AppTheme.radius.chip)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .width('100%')
        .onChange((v: string) => { onChange(v); })
    }
    .width('100%')
  }

  @Builder
  private NumberField(label: string, placeholder: string, value: number, onChange: (v: number) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(AppTheme.font.caption)
        .fontColor(AppTheme.color.textSecondary)
      TextInput({ text: value > 0 ? value.toString() : '', placeholder: placeholder })
        .type(InputType.Number)
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.textPrimary)
        .placeholderColor(AppTheme.color.textTertiary)
        .backgroundColor(AppTheme.color.surfaceTint)
        .borderRadius(AppTheme.radius.chip)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .width('100%')
        .onChange((v: string) => {
          const n = parseFloat(v);
          onChange(isNaN(n) ? 0 : n);
        })
    }
    .width('100%')
  }

  @Builder
  private BasicInfoSection() {
    GlassCard({ innerPadding: 18, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        this.SectionTitle('裙装信息');

        Column({ space: 4 }) {
          Text('图片')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)
          Row() {
            Column({ space: 6 }) {
              Text('+')
                .fontSize(32)
                .fontColor(AppTheme.color.textTertiary)
              Text('添加图片')
                .fontSize(AppTheme.font.tiny)
                .fontColor(AppTheme.color.textTertiary)
            }
            .width(88)
            .height(88)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.chip)
            .border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        this.FormField('名称 *', '裙装名称', this.draft.draftName, (v: string) => {
          this.draft.draftName = v;
        });

        this.FormField('品牌', '品牌名称', this.draft.draftBrand, (v: string) => {
          this.draft.draftBrand = v;
        });

        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text('类型')
              .fontSize(AppTheme.font.caption)
              .fontColor(AppTheme.color.textSecondary)
            Text(this.draft.draftCategory.length > 0 ? this.draft.draftCategory : '选择类型')
              .fontSize(AppTheme.font.body)
              .fontColor(this.draft.draftCategory.length > 0 ? AppTheme.color.textPrimary : AppTheme.color.textTertiary)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .width('100%')
              .backgroundColor(AppTheme.color.surfaceTint)
              .borderRadius(AppTheme.radius.chip)
              .onClick(() => {
                this.showCategoryPicker = !this.showCategoryPicker;
              })
          }
          .layoutWeight(1)

          Column({ space: 4 }) {
            Text('颜色')
              .fontSize(AppTheme.font.caption)
              .fontColor(AppTheme.color.textSecondary)
            TextInput({ text: this.draft.draftColors, placeholder: '颜色' })
              .fontSize(AppTheme.font.body)
              .fontColor(AppTheme.color.textPrimary)
              .placeholderColor(AppTheme.color.textTertiary)
              .backgroundColor(AppTheme.color.surfaceTint)
              .borderRadius(AppTheme.radius.chip)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .width('100%')
              .onChange((v: string) => { this.draft.draftColors = v; })
          }
          .layoutWeight(1)
        }
        .width('100%')

        if (this.showCategoryPicker) {
          Row({ space: 6 }) {
            ForEach(CATEGORY_LABELS, (label: string, idx: number) => {
              Text(label)
                .fontSize(AppTheme.font.caption)
                .fontWeight(this.draft.draftCategory === CATEGORY_KEYS[idx] ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.draft.draftCategory === CATEGORY_KEYS[idx] ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.draft.draftCategory === CATEGORY_KEYS[idx] ? AppTheme.color.primaryStrong : AppTheme.color.surfaceTint)
                .borderRadius(AppTheme.radius.pill)
                .onClick(() => {
                  this.draft.draftCategory = CATEGORY_KEYS[idx];
                  this.showCategoryPicker = false;
                })
            }, (label: string) => label)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }

        Row({ space: 10 }) {
          Column() {
            this.FormField('尺码', 'S/M/L', this.draft.draftSizes, (v: string) => {
              this.draft.draftSizes = v;
            });
          }
          .layoutWeight(1)
          Column() {
            this.FormField('裙长', '裙长', this.draft.draftLength, (v: string) => {
              this.draft.draftLength = v;
            });
          }
          .layoutWeight(1)
        }
        .width('100%')

        this.FormField('品相', '全新/95新/9新...', this.draft.draftCondition, (v: string) => {
          this.draft.draftCondition = v;
        });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private TagsSection() {
    GlassCard({ innerPadding: 18, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        this.SectionTitle('标签');

        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(this.draft.draftTags, (tag: string, idx: number) => {
            Row({ space: 4 }) {
              Text(tag)
                .fontSize(AppTheme.font.caption)
                .fontColor(AppTheme.color.textPrimary)
              Text('×')
                .fontSize(AppTheme.font.caption)
                .fontColor(AppTheme.color.textTertiary)
                .onClick(() => {
                  const tags = this.draft.draftTags.filter((_: string, i: number) => i !== idx);
                  this.draft.draftTags = tags;
                })
            }
            .padding({ left: 10, right: 8, top: 5, bottom: 5 })
            .backgroundColor(AppTheme.color.primaryPale)
            .borderRadius(AppTheme.radius.pill)
          }, (tag: string, idx: number) => `${tag}_${idx}`)

          Text('+ 添加标签')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.primary)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.pill)
            .border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private PriceSection() {
    GlassCard({ innerPadding: 18, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        this.SectionTitle('价格信息');

        Row({ space: 10 }) {
          Column() {
            this.NumberField('原价', '0', this.draft.draftOriginalPrice, (v: number) => {
              this.draft.draftOriginalPrice = v;
            });
          }
          .layoutWeight(1)
          Column() {
            this.NumberField('总价', '0', this.draft.draftPrice, (v: number) => {
              this.draft.draftPrice = v;
            });
          }
          .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          Column() {
            this.NumberField('定金', '0', this.draft.draftDeposit, (v: number) => {
              this.draft.draftDeposit = v;
            });
          }
          .layoutWeight(1)
          Column() {
            this.NumberField('尾款', '0', this.draft.draftBalance, (v: number) => {
              this.draft.draftBalance = v;
            });
          }
          .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          Column() {
            this.NumberField('配件价', '0', this.draft.draftAccessoriesPrice, (v: number) => {
              this.draft.draftAccessoriesPrice = v;
            });
          }
          .layoutWeight(1)

          Column({ space: 4 }) {
            Text('库存')
              .fontSize(AppTheme.font.caption)
              .fontColor(AppTheme.color.textSecondary)
            Row({ space: 0 }) {
              Text('−')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.draft.draftStock > 1 ? AppTheme.color.primary : AppTheme.color.textTertiary)
                .width(38)
                .height(38)
                .textAlign(TextAlign.Center)
                .backgroundColor(AppTheme.color.surfaceTint)
                .borderRadius({ topLeft: AppTheme.radius.chip, bottomLeft: AppTheme.radius.chip })
                .onClick(() => {
                  if (this.draft.draftStock > 1) {
                    this.draft.draftStock -= 1;
                  }
                })
              Text(this.draft.draftStock.toString())
                .fontSize(AppTheme.font.body)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.textPrimary)
                .layoutWeight(1)
                .height(38)
                .textAlign(TextAlign.Center)
                .backgroundColor(AppTheme.color.surfaceTint)
              Text('+')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.color.primary)
                .width(38)
                .height(38)
                .textAlign(TextAlign.Center)
                .backgroundColor(AppTheme.color.surfaceTint)
                .borderRadius({ topRight: AppTheme.radius.chip, bottomRight: AppTheme.radius.chip })
                .onClick(() => {
                  this.draft.draftStock += 1;
                })
            }
            .width('100%')
            .borderRadius(AppTheme.radius.chip)
            .border({ width: 1, color: AppTheme.color.border })
          }
          .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private PurchaseInfoSection() {
    GlassCard({ innerPadding: 18, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        this.SectionTitle('购买信息');

        Column({ space: 4 }) {
          Text('购买日期')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)
          Text(this.formatDate(this.draft.draftPurchasedAt))
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textPrimary)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .width('100%')
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.chip)
            .onClick(() => {
              DatePickerDialog.show({
                selected: new Date(this.draft.draftPurchasedAt),
                onDateAccept: (value: Date) => {
                  this.draft.draftPurchasedAt = value.getTime();
                }
              });
            })
        }
        .width('100%')

        Row() {
          Text('尾款计划')
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textPrimary)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.draft.draftIsDepositPlan })
            .selectedColor(AppTheme.color.primary)
            .onChange((isOn: boolean) => {
              this.draft.draftIsDepositPlan = isOn;
            })
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })

        if (this.draft.draftIsDepositPlan) {
          Column({ space: 4 }) {
            Text('定金日期')
              .fontSize(AppTheme.font.caption)
              .fontColor(AppTheme.color.textSecondary)
            Text(this.draft.draftDepositDate > 0 ? this.formatDate(this.draft.draftDepositDate) : '选择日期')
              .fontSize(AppTheme.font.body)
              .fontColor(this.draft.draftDepositDate > 0 ? AppTheme.color.textPrimary : AppTheme.color.textTertiary)
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .width('100%')
              .backgroundColor(AppTheme.color.surfaceTint)
              .borderRadius(AppTheme.radius.chip)
              .onClick(() => {
                DatePickerDialog.show({
                  onDateAccept: (value: Date) => {
                    this.draft.draftDepositDate = value.getTime();
                  }
                });
              })
          }
          .width('100%')

          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text('尾款开始')
                .fontSize(AppTheme.font.caption)
                .fontColor(AppTheme.color.textSecondary)
              Text(this.draft.draftFinalPaymentDate > 0 ? this.formatDate(this.draft.draftFinalPaymentDate) : '选择日期')
                .fontSize(AppTheme.font.body)
                .fontColor(this.draft.draftFinalPaymentDate > 0 ? AppTheme.color.textPrimary : AppTheme.color.textTertiary)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .width('100%')
                .backgroundColor(AppTheme.color.surfaceTint)
                .borderRadius(AppTheme.radius.chip)
                .onClick(() => {
                  DatePickerDialog.show({
                    onDateAccept: (value: Date) => {
                      this.draft.draftFinalPaymentDate = value.getTime();
                    }
                  });
                })
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text('尾款截止')
                .fontSize(AppTheme.font.caption)
                .fontColor(AppTheme.color.textSecondary)
              Text(this.draft.draftFinalPaymentEndDate > 0 ? this.formatDate(this.draft.draftFinalPaymentEndDate) : '选择日期')
                .fontSize(AppTheme.font.body)
                .fontColor(this.draft.draftFinalPaymentEndDate > 0 ? AppTheme.color.textPrimary : AppTheme.color.textTertiary)
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .width('100%')
                .backgroundColor(AppTheme.color.surfaceTint)
                .borderRadius(AppTheme.radius.chip)
                .onClick(() => {
                  DatePickerDialog.show({
                    onDateAccept: (value: Date) => {
                      this.draft.draftFinalPaymentEndDate = value.getTime();
                    }
                  });
                })
            }
            .layoutWeight(1)
          }
          .width('100%')
        }

        Column({ space: 4 }) {
          Text('备注')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)
          TextArea({ text: this.draft.draftNote, placeholder: '备注信息...' })
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textPrimary)
            .placeholderColor(AppTheme.color.textTertiary)
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.chip)
            .padding(12)
            .width('100%')
            .height(80)
            .onChange((v: string) => { this.draft.draftNote = v; })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private BottomActions() {
    Row({ space: 14 }) {
      Text('取消')
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.color.textPrimary)
        .padding({ left: 28, right: 28, top: 12, bottom: 12 })
        .backgroundColor(AppTheme.color.overlayGlassStrong)
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(AppTheme.radius.pill)
        .border({ width: 1, color: AppTheme.color.border })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.onCancel(); })

      Text('保存')
        .fontSize(AppTheme.font.body)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textOnPrimary)
        .padding({ left: 28, right: 28, top: 12, bottom: 12 })
        .backgroundColor(this.draft.draftName.length > 0 ? AppTheme.color.primary : AppTheme.color.primarySoft)
        .borderRadius(AppTheme.radius.pill)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (this.draft.draftName.length > 0) {
            this.onSave(this.draft);
          }
        })
    }
    .width('100%')
    .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 12, bottom: 30 })
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
  }

  build() {
    Column() {
      this.Header();

      Scroll() {
        Column({ space: 18 }) {
          this.BasicInfoSection();
          this.TagsSection();
          this.PriceSection();
          this.PurchaseInfoSection();
          Blank().height(20)
        }
        .width('100%')
        .padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 8, bottom: 100 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.BottomActions();
    }
    .width('100%')
    .height('100%')
  }
}

@Observed
export class ClothingDraft {
  draftName: string = '';
  draftBrand: string = '';
  draftCategory: string = '';
  draftColors: string = '';
  draftSizes: string = '';
  draftLength: string = '';
  draftCondition: string = '';
  draftTypes: string = '';
  draftNote: string = '';
  draftImageUri: string = '';

  draftPrice: number = 0;
  draftOriginalPrice: number = 0;
  draftDeposit: number = 0;
  draftBalance: number = 0;
  draftAccessoriesPrice: number = 0;
  draftStock: number = 1;

  draftPurchasedAt: number = Date.now();
  draftDepositDate: number = 0;
  draftIsDepositPlan: boolean = false;
  draftFinalPaymentDate: number = 0;
  draftFinalPaymentEndDate: number = 0;

  draftTags: string[] = [];
}
