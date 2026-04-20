if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    selectedRoute?: AppRoute;
    features?: FeatureDescriptor[];
}
import { AppRoute, HOME_TABS } from "@bundle:com.pinkhouse.harmony/entry/ets/core/navigation/AppRoute";
import type { RouteTab } from "@bundle:com.pinkhouse.harmony/entry/ets/core/navigation/AppRoute";
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import type { FeatureDescriptor } from '../domain/model/FeatureDescriptor';
import { GetHomeFeaturesUseCase } from "@bundle:com.pinkhouse.harmony/entry/ets/domain/usecase/GetHomeFeaturesUseCase";
import { WardrobePage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/WardrobePage";
import { PetPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/pet/PetPage";
import { SmallWorldPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/smallworld/SmallWorldPage";
import { WealthPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wealth/WealthPage";
import { VipPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/vip/VipPage";
import { SettingsPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/settings/SettingsPage";
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__selectedRoute = new ObservedPropertySimplePU(AppRoute.Wardrobe, this, "selectedRoute");
        this.features = new GetHomeFeaturesUseCase().execute();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.selectedRoute !== undefined) {
            this.selectedRoute = params.selectedRoute;
        }
        if (params.features !== undefined) {
            this.features = params.features;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__selectedRoute.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__selectedRoute.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __selectedRoute: ObservedPropertySimplePU<AppRoute>;
    get selectedRoute() {
        return this.__selectedRoute.get();
    }
    set selectedRoute(newValue: AppRoute) {
        this.__selectedRoute.set(newValue);
    }
    private readonly features: FeatureDescriptor[];
    private Header(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({ bottom: 8 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('少女心愿 HarmonyOS Next');
            Text.fontSize(28);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Stage + ArkTS + ArkUI 工程骨架，已预留 RDB、Preferences、HMS IAP、提醒、天气和服务卡片扩展点。');
            Text.fontSize(15);
            Text.lineHeight(22);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private RouteTabs(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.scrollable(ScrollDirection.Horizontal);
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.padding({ top: 4, bottom: 4 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const tab = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Button.createWithLabel(tab.title);
                    Button.fontSize(14);
                    Button.fontColor(this.selectedRoute === tab.route ? '#FFFFFF' : AppTheme.color.primary);
                    Button.backgroundColor(this.selectedRoute === tab.route ? AppTheme.color.primary : AppTheme.color.primarySoft);
                    Button.borderRadius(AppTheme.radius.pill);
                    Button.onClick(() => {
                        this.selectedRoute = tab.route;
                    });
                }, Button);
                Button.pop();
            };
            this.forEachUpdateFunction(elmtId, HOME_TABS, forEachItemGenFunction, (tab: RouteTab) => tab.route, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        Scroll.pop();
    }
    private FeatureContent(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.selectedRoute === AppRoute.Wardrobe) {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new WardrobePage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 60, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "WardrobePage" });
                    }
                });
            }
            else if (this.selectedRoute === AppRoute.Pet) {
                this.ifElseBranchUpdateFunction(1, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new PetPage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 62, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "PetPage" });
                    }
                });
            }
            else if (this.selectedRoute === AppRoute.SmallWorld) {
                this.ifElseBranchUpdateFunction(2, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new SmallWorldPage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 64, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "SmallWorldPage" });
                    }
                });
            }
            else if (this.selectedRoute === AppRoute.Wealth) {
                this.ifElseBranchUpdateFunction(3, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new WealthPage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 66, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "WealthPage" });
                    }
                });
            }
            else if (this.selectedRoute === AppRoute.Vip) {
                this.ifElseBranchUpdateFunction(4, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new VipPage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 68, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "VipPage" });
                    }
                });
            }
            else {
                this.ifElseBranchUpdateFunction(5, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new SettingsPage(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 70, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {};
                                };
                                componentCall.paramsGenerator_ = paramsLambda;
                            }
                            else {
                                this.updateStateVarsOfChildByElmtId(elmtId, {});
                            }
                        }, { name: "SettingsPage" });
                    }
                });
            }
        }, If);
        If.pop();
    }
    private MilestoneList(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('首批工程占位');
            Text.fontSize(18);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const feature = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create({ space: 12 });
                    Row.width('100%');
                    Row.padding(12);
                    Row.backgroundColor(AppTheme.color.surface);
                    Row.borderRadius(16);
                    Row.border({ width: 1, color: AppTheme.color.border });
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(feature.milestone);
                    Text.fontSize(12);
                    Text.fontWeight(FontWeight.Medium);
                    Text.fontColor(AppTheme.color.primary);
                    Text.width(54);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create({ space: 3 });
                    Column.layoutWeight(1);
                    Column.alignItems(HorizontalAlign.Start);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(feature.title);
                    Text.fontSize(15);
                    Text.fontWeight(FontWeight.Medium);
                    Text.fontColor(AppTheme.color.textPrimary);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(feature.description);
                    Text.fontSize(13);
                    Text.lineHeight(18);
                    Text.fontColor(AppTheme.color.textSecondary);
                }, Text);
                Text.pop();
                Column.pop();
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, this.features, forEachItemGenFunction, (feature: FeatureDescriptor) => feature.route, false, false);
        }, ForEach);
        ForEach.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
            Column.linearGradient({
                angle: 160,
                colors: [[AppTheme.color.background, 0.0], ['#FFFDF8', 0.52], ['#F8FBFF', 1.0]]
            });
        }, Column);
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 18 });
            Column.width('100%');
            Column.padding(AppTheme.spacing.page);
        }, Column);
        this.Header.bind(this)();
        this.RouteTabs.bind(this)();
        this.FeatureContent.bind(this)();
        this.MilestoneList.bind(this)();
        Column.pop();
        Scroll.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "com.pinkhouse.harmony", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
