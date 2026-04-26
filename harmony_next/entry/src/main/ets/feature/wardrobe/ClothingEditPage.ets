import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import { AppTheme } from '../../core/theme/AppTheme';
import { GlassCard } from '../../core/theme/GlassComponents';
import { WardrobeImageStore } from '../../core/media/WardrobeImageStore';
import { AppLogger } from '../../core/utils/AppLogger';
import { WardrobeCategory } from '../../domain/model/WardrobeItem';

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

  private async pickMainImage(): Promise<void> {
    AppLogger.info('[ClothingEditPage] main image tapped');
    try {
      const ctx = getContext(this) as common.Context;
      const uris = await WardrobeImageStore.pickImages(ctx, 1);
      AppLogger.info(`[ClothingEditPage] main image picker result=${uris.length}`);
      if (uris.length > 0) {
        this.draft.draftImageUri = await WardrobeImageStore.persistPickedImage(ctx, uris[0]);
        AppLogger.info(`[ClothingEditPage] main image selected=${this.draft.draftImageUri}`);
      } else {
        promptAction.showToast({ message: '未选择图片' });
      }
    } catch (error) {
      AppLogger.error(`[ClothingEditPage] main image failed: ${JSON.stringify(error)}`);
      promptAction.showToast({ message: '图片选择失败，请看 PinkHouse 日志' });
    }
  }

  @Builder
  private Header() {
    Row() {
      Text('取消')
        .fontSize(AppTheme.font.body)
        .fontColor(AppTheme.color.primary)
        .onClick(() => { this.onCancel(); })

      Blank().layoutWeight(1)

      Text('手动创建')
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
          Text('选择图片 (最多9张，第一张为主图)')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)

          Row({ space: 12 }) {
            if (this.draft.draftImageUri.length > 0) {
              Image(this.draft.draftImageUri)
                .width(92)
                .height(92)
                .borderRadius(AppTheme.radius.chip)
                .objectFit(ImageFit.Cover)
                .onClick(() => { this.pickMainImage(); })
            } else {
              Column({ space: 6 }) {
                Text('+')
                  .fontSize(32)
                  .fontColor(AppTheme.color.textTertiary)
                Text('主图')
                  .fontSize(AppTheme.font.tiny)
                  .fontColor(AppTheme.color.textTertiary)
              }
              .width(92)
              .height(92)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(AppTheme.color.surfaceTint)
              .borderRadius(AppTheme.radius.chip)
              .border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border })
              .onClick(() => { this.pickMainImage(); })
            }

            Text(this.draft.draftImageUri.length > 0 ? '更换' : '添加')
              .fontSize(AppTheme.font.body)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.primary)
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .backgroundColor(AppTheme.color.primaryPale)
              .borderRadius(AppTheme.radius.pill)
              .onClick(() => { this.pickMainImage(); })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        this.FormField('裙装名称 *', '请输入裙装名称', this.draft.draftName, (v: string) => {
          this.draft.draftName = v;
        });

        this.FormField('品牌名称', '品牌名称', this.draft.draftBrand, (v: string) => {
          this.draft.draftBrand = v;
        });

        Column({ space: 4 }) {
          Text('分类')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.textSecondary)
          Text(this.draft.draftCategory.length > 0 ? this.draft.draftCategory : WardrobeCategory.Dress)
            .fontSize(AppTheme.font.body)
            .fontColor(AppTheme.color.textPrimary)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .width('100%')
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.chip)
            .onClick(() => {
              this.showCategoryPicker = !this.showCategoryPicker;
            })
        }
        .width('100%')

        if (this.showCategoryPicker) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(CATEGORY_LABELS, (label: string) => {
              Text(label)
                .fontSize(AppTheme.font.caption)
                .fontWeight(this.draft.draftCategory === label ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.draft.draftCategory === label ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.draft.draftCategory === label ? AppTheme.color.primaryStrong : AppTheme.color.surfaceTint)
                .borderRadius(AppTheme.radius.pill)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.draft.draftCategory = label;
                  this.showCategoryPicker = false;
                })
            }, (label: string) => label)
          }
          .width('100%')
        }

        this.FormField('类型 (逗号分隔，如: JSK,OP,SK,小物)', '例如: JSK, OP', this.draft.draftTypes, (v: string) => {
          this.draft.draftTypes = v;
        });

        this.FormField('颜色', '颜色', this.draft.draftColors, (v: string) => {
          this.draft.draftColors = v;
        });

        Row({ space: 10 }) {
          Column() {
            this.FormField('尺码', 'S/M/L', this.draft.draftSizes, (v: string) => {
              this.draft.draftSizes = v;
            });
          }
          .layoutWeight(1)
          Column() {
            this.FormField('衣长', '衣长', this.draft.draftLength, (v: string) => {
              this.draft.draftLength = v;
            });
          }
          .layoutWeight(1)
        }
        .width('100%')

        this.FormField('状态', '全新/95新/9新...', this.draft.draftCondition, (v: string) => {
          this.draft.draftCondition = v;
        });

        this.FormField('小物', '发带、KC、胸针等', this.draft.draftAccessories, (v: string) => {
          this.draft.draftAccessories = v;
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

        Flex({ wrap: FlexWrap.Wrap }) {
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
            .margin({ right: 8, bottom: 8 })
          }, (tag: string, idx: number) => `${tag}_${idx}`)

          Text('+ 添加标签')
            .fontSize(AppTheme.font.caption)
            .fontColor(AppTheme.color.primary)
            .fontWeight(FontWeight.Bold)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(AppTheme.color.surfaceTint)
            .borderRadius(AppTheme.radius.pill)
            .border({ width: 1, style: BorderStyle.Dashed, color: AppTheme.color.border })
            .margin({ right: 8, bottom: 8 })
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
  draftCategory: string = WardrobeCategory.Dress;
  draftColors: string = '';
  draftSizes: string = '';
  draftLength: string = '';
  draftCondition: string = '全新';
  draftTypes: string = '';
  draftAccessories: string = '';
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
