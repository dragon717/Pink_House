import common from '@ohos.app.ability.common';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppLogger } from '../../core/utils/AppLogger';
import { RdbWardrobeRepository } from '../../data/repository/RdbWardrobeRepository';
import { WardrobeItem } from '../../domain/model/WardrobeItem';
import { AddSampleWardrobeItemUseCase } from '../../domain/usecase/AddSampleWardrobeItemUseCase';
import { GetWardrobeItemsUseCase } from '../../domain/usecase/GetWardrobeItemsUseCase';
import { SearchWardrobeItemsUseCase } from '../../domain/usecase/SearchWardrobeItemsUseCase';
import { SoftDeleteWardrobeItemUseCase } from '../../domain/usecase/SoftDeleteWardrobeItemUseCase';

@Component
export struct WardrobePage {
  @State private items: WardrobeItem[] = [];
  @State private searchKeyword: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    this.loadItems();
  }

  @Builder
  private Header() {
    Column({ space: 6 }) {
      Row() {
        Text('衣橱 MVP')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Blank()
        Text(`${this.items.length} 件`)
          .fontSize(13)
          .fontColor(AppTheme.color.primary)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(AppTheme.color.primarySoft)
          .borderRadius(AppTheme.radius.pill)
      }
      .width('100%')

      Text('RDB 驱动的衣物列表雏形，当前支持查询、按名称搜索、添加示例衣物和软删除。')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SearchBar() {
    Column({ space: 10 }) {
      TextInput({ placeholder: '搜索衣物名称', text: this.searchKeyword })
        .height(44)
        .fontSize(15)
        .placeholderColor('#B89AA7')
        .fontColor(AppTheme.color.textPrimary)
        .backgroundColor('#FFF8FB')
        .borderRadius(14)
        .border({ width: 1, color: AppTheme.color.border })
        .onChange((value: string) => {
          this.searchKeyword = value;
          this.searchItems();
        })

      Row({ space: 10 }) {
        Button('添加示例衣物')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(AppTheme.color.primary)
          .borderRadius(AppTheme.radius.pill)
          .layoutWeight(1)
          .onClick(() => {
            this.addSampleItem();
          })

        Button('刷新')
          .fontSize(14)
          .fontColor(AppTheme.color.primary)
          .backgroundColor(AppTheme.color.primarySoft)
          .borderRadius(AppTheme.radius.pill)
          .onClick(() => {
            this.loadItems();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private Content() {
    if (this.isLoading) {
      this.LoadingState();
    } else if (this.errorMessage.length > 0) {
      this.ErrorState();
    } else if (this.items.length === 0) {
      this.EmptyState();
    } else {
      Column({ space: 10 }) {
        ForEach(this.items, (item: WardrobeItem) => {
          this.ItemCard(item);
        }, (item: WardrobeItem) => item.id)
      }
      .width('100%')
    }
  }

  @Builder
  private ItemCard(item: WardrobeItem) {
    Row({ space: 12 }) {
      Column() {
        Text(item.category.substring(0, 1))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.primary)
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppTheme.color.primarySoft)
      .borderRadius(16)

      Column({ space: 4 }) {
        Text(item.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.textPrimary)
        Text(`${item.category} · ¥${item.price.toFixed(0)}`)
          .fontSize(13)
          .fontColor(AppTheme.color.textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('移除')
        .fontSize(12)
        .fontColor(AppTheme.color.textSecondary)
        .backgroundColor('#FFF8FB')
        .border({ width: 1, color: AppTheme.color.border })
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.softDeleteItem(item.id);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }

  @Builder
  private LoadingState() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(AppTheme.color.primary)
      Text('正在读取衣橱...')
        .fontSize(14)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .padding(24)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Text('还没有衣物')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
      Text(this.searchKeyword.length > 0 ? '没有找到匹配名称，换个关键词试试。' : '先添加一件示例衣物，验证 RDB 列表链路。')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(AppTheme.color.textSecondary)
    }
    .width('100%')
    .padding(24)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }

  @Builder
  private ErrorState() {
    Column({ space: 10 }) {
      Text('衣橱读取失败')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
      Text(this.errorMessage)
        .fontSize(13)
        .lineHeight(18)
        .fontColor(AppTheme.color.textSecondary)
      Button('重试')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor(AppTheme.color.primary)
        .borderRadius(AppTheme.radius.pill)
        .onClick(() => {
          this.loadItems();
        })
    }
    .width('100%')
    .padding(24)
    .backgroundColor(AppTheme.color.surface)
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }

  build() {
    Column({ space: 16 }) {
      this.Header();
      this.SearchBar();
      this.Content();
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(AppTheme.spacing.card)
    .backgroundColor('rgba(255, 255, 255, 0.72)')
    .borderRadius(AppTheme.radius.card)
    .border({ width: 1, color: AppTheme.color.border })
  }

  private async loadItems(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
      const useCase = new GetWardrobeItemsUseCase(repository);
      this.items = await useCase.execute();
      this.searchKeyword = '';
    } catch (error) {
      this.handleError('load wardrobe items failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  private async searchItems(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';

    try {
      const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
      const useCase = new SearchWardrobeItemsUseCase(repository);
      this.items = await useCase.execute(this.searchKeyword);
    } catch (error) {
      this.handleError('search wardrobe items failed', error);
    } finally {
      this.isLoading = false;
    }
  }

  private async addSampleItem(): Promise<void> {
    this.errorMessage = '';

    try {
      const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
      const useCase = new AddSampleWardrobeItemUseCase(repository);
      await useCase.execute();
      await this.searchItems();
    } catch (error) {
      this.handleError('add sample wardrobe item failed', error);
    }
  }

  private async softDeleteItem(id: string): Promise<void> {
    this.errorMessage = '';

    try {
      const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
      const useCase = new SoftDeleteWardrobeItemUseCase(repository);
      await useCase.execute(id);
      await this.searchItems();
    } catch (error) {
      this.handleError('soft delete wardrobe item failed', error);
    }
  }

  private handleError(message: string, error: Object): void {
    AppLogger.error(`${message}: ${JSON.stringify(error)}`);
    this.errorMessage = message;
  }
}
