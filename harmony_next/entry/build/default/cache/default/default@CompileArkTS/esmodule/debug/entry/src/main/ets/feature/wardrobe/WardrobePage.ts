if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WardrobePage_Params {
    items?: WardrobeItem[];
    searchKeyword?: string;
    isLoading?: boolean;
    errorMessage?: string;
}
import type common from "@ohos:app.ability.common";
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import { AppLogger } from "@bundle:com.pinkhouse.harmony/entry/ets/core/utils/AppLogger";
import { RdbWardrobeRepository } from "@bundle:com.pinkhouse.harmony/entry/ets/data/repository/RdbWardrobeRepository";
import type { WardrobeItem } from '../../domain/model/WardrobeItem';
import { AddSampleWardrobeItemUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/AddSampleWardrobeItemUseCase";
import { GetWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/GetWardrobeItemsUseCase";
import { SearchWardrobeItemsUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/SearchWardrobeItemsUseCase";
import { SoftDeleteWardrobeItemUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/SoftDeleteWardrobeItemUseCase";
export class WardrobePage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__items = new ObservedPropertyObjectPU([], this, "items");
        this.__searchKeyword = new ObservedPropertySimplePU('', this, "searchKeyword");
        this.__isLoading = new ObservedPropertySimplePU(false, this, "isLoading");
        this.__errorMessage = new ObservedPropertySimplePU('', this, "errorMessage");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WardrobePage_Params) {
        if (params.items !== undefined) {
            this.items = params.items;
        }
        if (params.searchKeyword !== undefined) {
            this.searchKeyword = params.searchKeyword;
        }
        if (params.isLoading !== undefined) {
            this.isLoading = params.isLoading;
        }
        if (params.errorMessage !== undefined) {
            this.errorMessage = params.errorMessage;
        }
    }
    updateStateVars(params: WardrobePage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__items.purgeDependencyOnElmtId(rmElmtId);
        this.__searchKeyword.purgeDependencyOnElmtId(rmElmtId);
        this.__isLoading.purgeDependencyOnElmtId(rmElmtId);
        this.__errorMessage.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__items.aboutToBeDeleted();
        this.__searchKeyword.aboutToBeDeleted();
        this.__isLoading.aboutToBeDeleted();
        this.__errorMessage.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __items: ObservedPropertyObjectPU<WardrobeItem[]>;
    get items() {
        return this.__items.get();
    }
    set items(newValue: WardrobeItem[]) {
        this.__items.set(newValue);
    }
    private __searchKeyword: ObservedPropertySimplePU<string>;
    get searchKeyword() {
        return this.__searchKeyword.get();
    }
    set searchKeyword(newValue: string) {
        this.__searchKeyword.set(newValue);
    }
    private __isLoading: ObservedPropertySimplePU<boolean>;
    get isLoading() {
        return this.__isLoading.get();
    }
    set isLoading(newValue: boolean) {
        this.__isLoading.set(newValue);
    }
    private __errorMessage: ObservedPropertySimplePU<string>;
    get errorMessage() {
        return this.__errorMessage.get();
    }
    set errorMessage(newValue: string) {
        this.__errorMessage.set(newValue);
    }
    aboutToAppear(): void {
        this.loadItems();
    }
    private Header(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('衣橱 MVP');
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.items.length} 件`);
            Text.fontSize(13);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 10, right: 10, top: 5, bottom: 5 });
            Text.backgroundColor(AppTheme.color.primarySoft);
            Text.borderRadius(AppTheme.radius.pill);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('RDB 驱动的衣物列表雏形，当前支持查询、按名称搜索、添加示例衣物和软删除。');
            Text.fontSize(14);
            Text.lineHeight(20);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private SearchBar(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '搜索衣物名称', text: this.searchKeyword });
            TextInput.height(44);
            TextInput.fontSize(15);
            TextInput.placeholderColor('#B89AA7');
            TextInput.fontColor(AppTheme.color.textPrimary);
            TextInput.backgroundColor('#FFF8FB');
            TextInput.borderRadius(14);
            TextInput.border({ width: 1, color: AppTheme.color.border });
            TextInput.onChange((value: string) => {
                this.searchKeyword = value;
                this.searchItems();
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('添加示例衣物');
            Button.fontSize(14);
            Button.fontColor('#FFFFFF');
            Button.backgroundColor(AppTheme.color.primary);
            Button.borderRadius(AppTheme.radius.pill);
            Button.layoutWeight(1);
            Button.onClick(() => {
                this.addSampleItem();
            });
        }, Button);
        Button.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('刷新');
            Button.fontSize(14);
            Button.fontColor(AppTheme.color.primary);
            Button.backgroundColor(AppTheme.color.primarySoft);
            Button.borderRadius(AppTheme.radius.pill);
            Button.onClick(() => {
                this.loadItems();
            });
        }, Button);
        Button.pop();
        Row.pop();
        Column.pop();
    }
    private Content(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isLoading) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.LoadingState.bind(this)();
                });
            }
            else if (this.errorMessage.length > 0) {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.ErrorState.bind(this)();
                });
            }
            else if (this.items.length === 0) {
                this.ifElseBranchUpdateFunction(2, () => {
                    this.EmptyState.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(3, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create({ space: 10 });
                        Column.width('100%');
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            this.ItemCard.bind(this)(item);
                        };
                        this.forEachUpdateFunction(elmtId, this.items, forEachItemGenFunction, (item: WardrobeItem) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Column.pop();
                });
            }
        }, If);
        If.pop();
    }
    private ItemCard(item: WardrobeItem, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 12 });
            Row.width('100%');
            Row.padding(14);
            Row.backgroundColor(AppTheme.color.surface);
            Row.borderRadius(AppTheme.radius.card);
            Row.border({ width: 1, color: AppTheme.color.border });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width(48);
            Column.height(48);
            Column.justifyContent(FlexAlign.Center);
            Column.backgroundColor(AppTheme.color.primarySoft);
            Column.borderRadius(16);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.category.substring(0, 1));
            Text.fontSize(20);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.layoutWeight(1);
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.name);
            Text.fontSize(16);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${item.category} · ¥${item.price.toFixed(0)}`);
            Text.fontSize(13);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('移除');
            Button.fontSize(12);
            Button.fontColor(AppTheme.color.textSecondary);
            Button.backgroundColor('#FFF8FB');
            Button.border({ width: 1, color: AppTheme.color.border });
            Button.borderRadius(AppTheme.radius.pill);
            Button.onClick(() => {
                this.softDeleteItem(item.id);
            });
        }, Button);
        Button.pop();
        Row.pop();
    }
    private LoadingState(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(24);
            Column.backgroundColor(AppTheme.color.surface);
            Column.borderRadius(AppTheme.radius.card);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            LoadingProgress.create();
            LoadingProgress.width(32);
            LoadingProgress.height(32);
            LoadingProgress.color(AppTheme.color.primary);
        }, LoadingProgress);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('正在读取衣橱...');
            Text.fontSize(14);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private EmptyState(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
            Column.padding(24);
            Column.backgroundColor(AppTheme.color.surface);
            Column.borderRadius(AppTheme.radius.card);
            Column.border({ width: 1, color: AppTheme.color.border });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('还没有衣物');
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.searchKeyword.length > 0 ? '没有找到匹配名称，换个关键词试试。' : '先添加一件示例衣物，验证 RDB 列表链路。');
            Text.fontSize(14);
            Text.lineHeight(20);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private ErrorState(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
            Column.padding(24);
            Column.backgroundColor(AppTheme.color.surface);
            Column.borderRadius(AppTheme.radius.card);
            Column.border({ width: 1, color: AppTheme.color.border });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('衣橱读取失败');
            Text.fontSize(17);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.errorMessage);
            Text.fontSize(13);
            Text.lineHeight(18);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Button.createWithLabel('重试');
            Button.fontSize(14);
            Button.fontColor('#FFFFFF');
            Button.backgroundColor(AppTheme.color.primary);
            Button.borderRadius(AppTheme.radius.pill);
            Button.onClick(() => {
                this.loadItems();
            });
        }, Button);
        Button.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding(AppTheme.spacing.card);
            Column.backgroundColor('rgba(255, 255, 255, 0.72)');
            Column.borderRadius(AppTheme.radius.card);
            Column.border({ width: 1, color: AppTheme.color.border });
        }, Column);
        this.Header.bind(this)();
        this.SearchBar.bind(this)();
        this.Content.bind(this)();
        Column.pop();
    }
    private async loadItems(): Promise<void> {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const repository = new RdbWardrobeRepository(getContext(this) as common.Context);
            const useCase = new GetWardrobeItemsUseCase(repository);
            this.items = await useCase.execute();
            this.searchKeyword = '';
        }
        catch (error) {
            this.handleError('load wardrobe items failed', error);
        }
        finally {
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
        }
        catch (error) {
            this.handleError('search wardrobe items failed', error);
        }
        finally {
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
        }
        catch (error) {
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
        }
        catch (error) {
            this.handleError('soft delete wardrobe item failed', error);
        }
    }
    private handleError(message: string, error: Object): void {
        AppLogger.error(`${message}: ${JSON.stringify(error)}`);
        this.errorMessage = message;
    }
    rerender() {
        this.updateDirtyElements();
    }
}
