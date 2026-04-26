if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface FeatureShell_Params {
    title?: string;
    badge?: string;
    description?: string;
    checklist?: string[];
}
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
export interface FeatureShellOptions {
    readonly title: string;
    readonly badge: string;
    readonly description: string;
    readonly checklist: string[];
}
export class FeatureShell extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__title = new SynchedPropertySimpleOneWayPU(params.title, this, "title");
        this.__badge = new SynchedPropertySimpleOneWayPU(params.badge, this, "badge");
        this.__description = new SynchedPropertySimpleOneWayPU(params.description, this, "description");
        this.__checklist = new SynchedPropertyObjectOneWayPU(params.checklist, this, "checklist");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: FeatureShell_Params) {
        if (params.title === undefined) {
            this.__title.set('');
        }
        if (params.badge === undefined) {
            this.__badge.set('');
        }
        if (params.description === undefined) {
            this.__description.set('');
        }
        if (params.checklist === undefined) {
            this.__checklist.set([]);
        }
    }
    updateStateVars(params: FeatureShell_Params) {
        this.__title.reset(params.title);
        this.__badge.reset(params.badge);
        this.__description.reset(params.description);
        this.__checklist.reset(params.checklist);
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__title.purgeDependencyOnElmtId(rmElmtId);
        this.__badge.purgeDependencyOnElmtId(rmElmtId);
        this.__description.purgeDependencyOnElmtId(rmElmtId);
        this.__checklist.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__title.aboutToBeDeleted();
        this.__badge.aboutToBeDeleted();
        this.__description.aboutToBeDeleted();
        this.__checklist.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __title: SynchedPropertySimpleOneWayPU<string>;
    get title() {
        return this.__title.get();
    }
    set title(newValue: string) {
        this.__title.set(newValue);
    }
    private __badge: SynchedPropertySimpleOneWayPU<string>;
    get badge() {
        return this.__badge.get();
    }
    set badge(newValue: string) {
        this.__badge.set(newValue);
    }
    private __description: SynchedPropertySimpleOneWayPU<string>;
    get description() {
        return this.__description.get();
    }
    set description(newValue: string) {
        this.__description.set(newValue);
    }
    private __checklist: SynchedPropertySimpleOneWayPU<string[]>;
    get checklist() {
        return this.__checklist.get();
    }
    set checklist(newValue: string[]) {
        this.__checklist.set(newValue);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 14 });
            Column.width('100%');
            Column.padding(16);
            Column.backgroundColor(AppTheme.color.surface);
            Column.borderRadius(AppTheme.radius.card);
            Column.border({ width: 1, color: AppTheme.color.border });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.justifyContent(FlexAlign.SpaceBetween);
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.title);
            Text.fontSize(24);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.badge);
            Text.fontSize(12);
            Text.fontWeight(FontWeight.Medium);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 10, right: 10, top: 5, bottom: 5 });
            Text.backgroundColor(AppTheme.color.primarySoft);
            Text.borderRadius(AppTheme.radius.pill);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.description);
            Text.fontSize(15);
            Text.lineHeight(22);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.padding(14);
            Column.backgroundColor(AppTheme.color.surface);
            Column.borderRadius(18);
            Column.border({ width: 1, color: AppTheme.color.border });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const item = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create({ space: 8 });
                    Row.width('100%');
                    Row.alignItems(VerticalAlign.Top);
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create('•');
                    Text.fontSize(16);
                    Text.fontColor(AppTheme.color.primary);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(item);
                    Text.fontSize(14);
                    Text.fontColor(AppTheme.color.textPrimary);
                }, Text);
                Text.pop();
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, this.checklist, forEachItemGenFunction, (item: string) => item, false, false);
        }, ForEach);
        ForEach.pop();
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
