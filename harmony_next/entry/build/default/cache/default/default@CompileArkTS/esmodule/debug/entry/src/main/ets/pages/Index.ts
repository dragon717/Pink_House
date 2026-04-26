if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    currentIndex?: number;
    wardrobeSegment?: string;
    smallWorldDestination?: string;
    isPetOpen?: boolean;
    tabsController?: TabsController;
}
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import { WatercolorBackground } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/GlassComponents";
import { AppSymbol, AppSymbolName } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppSymbols";
import { WardrobePage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/wardrobe/WardrobePage";
import { SmallWorldPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/smallworld/SmallWorldPage";
import { MePage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/me/MePage";
import { PetPage } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/pet/PetPage";
interface BottomTabItem {
    readonly index: number;
    readonly label: string;
    readonly symbolName: string;
}
const MAIN_TABS: BottomTabItem[] = [
    { index: 0, label: '衣橱', symbolName: AppSymbolName.Wardrobe },
    { index: 1, label: 'House', symbolName: AppSymbolName.House },
    { index: 2, label: '我', symbolName: AppSymbolName.Me }
];
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__currentIndex = new ObservedPropertySimplePU(0, this, "currentIndex");
        this.__wardrobeSegment = new ObservedPropertySimplePU('wardrobe', this, "wardrobeSegment");
        this.__smallWorldDestination = new ObservedPropertySimplePU('menu', this, "smallWorldDestination");
        this.__isPetOpen = new ObservedPropertySimplePU(false, this, "isPetOpen");
        this.tabsController = new TabsController();
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.currentIndex !== undefined) {
            this.currentIndex = params.currentIndex;
        }
        if (params.wardrobeSegment !== undefined) {
            this.wardrobeSegment = params.wardrobeSegment;
        }
        if (params.smallWorldDestination !== undefined) {
            this.smallWorldDestination = params.smallWorldDestination;
        }
        if (params.isPetOpen !== undefined) {
            this.isPetOpen = params.isPetOpen;
        }
        if (params.tabsController !== undefined) {
            this.tabsController = params.tabsController;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__currentIndex.purgeDependencyOnElmtId(rmElmtId);
        this.__wardrobeSegment.purgeDependencyOnElmtId(rmElmtId);
        this.__smallWorldDestination.purgeDependencyOnElmtId(rmElmtId);
        this.__isPetOpen.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__currentIndex.aboutToBeDeleted();
        this.__wardrobeSegment.aboutToBeDeleted();
        this.__smallWorldDestination.aboutToBeDeleted();
        this.__isPetOpen.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __currentIndex: ObservedPropertySimplePU<number>;
    get currentIndex() {
        return this.__currentIndex.get();
    }
    set currentIndex(newValue: number) {
        this.__currentIndex.set(newValue);
    }
    private __wardrobeSegment: ObservedPropertySimplePU<string>;
    get wardrobeSegment() {
        return this.__wardrobeSegment.get();
    }
    set wardrobeSegment(newValue: string) {
        this.__wardrobeSegment.set(newValue);
    }
    private __smallWorldDestination: ObservedPropertySimplePU<string>;
    get smallWorldDestination() {
        return this.__smallWorldDestination.get();
    }
    set smallWorldDestination(newValue: string) {
        this.__smallWorldDestination.set(newValue);
    }
    private __isPetOpen: ObservedPropertySimplePU<boolean>;
    get isPetOpen() {
        return this.__isPetOpen.get();
    }
    set isPetOpen(newValue: boolean) {
        this.__isPetOpen.set(newValue);
    }
    private tabsController: TabsController;
    private houseTitle(): string {
        switch (this.smallWorldDestination) {
            case 'wealth':
                return '来财';
            case 'ootd':
                return '穿搭手帐';
            case 'calendar':
                return '梦裙日历';
            case 'perler':
                return '拼豆工坊';
            case 'deposit':
                return '心愿尾款';
            case 'wardrobe':
                return '衣橱';
            default:
                return 'House';
        }
    }
    private MainTabs(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Tabs.create({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController });
            Tabs.width('100%');
            Tabs.height('100%');
            Tabs.barHeight(92);
            Tabs.barMode(BarMode.Fixed);
            Tabs.scrollable(false);
            Tabs.barBackgroundColor(AppTheme.color.overlayGlassStrong);
            Tabs.divider(null);
            Tabs.onChange((index: number) => {
                this.currentIndex = index;
                this.isPetOpen = false;
            });
        }, Tabs);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new WardrobePage(this, {
                                selectedSegment: this.__wardrobeSegment,
                                onOpenHouse: (destination: string) => {
                                    this.openHouse(destination);
                                }
                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 53, col: 7 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {
                                    selectedSegment: this.wardrobeSegment,
                                    onOpenHouse: (destination: string) => {
                                        this.openHouse(destination);
                                    }
                                };
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "WardrobePage" });
                }
            });
            TabContent.tabBar({ builder: () => {
                    this.MainTabBar.call(this, MAIN_TABS[0]);
                } });
        }, TabContent);
        TabContent.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new SmallWorldPage(this, {
                                destination: this.__smallWorldDestination,
                                onOpenWardrobe: (segment: string) => {
                                    this.wardrobeSegment = segment;
                                    this.smallWorldDestination = 'menu';
                                    this.switchMainTab(0);
                                }
                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 63, col: 7 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {
                                    destination: this.smallWorldDestination,
                                    onOpenWardrobe: (segment: string) => {
                                        this.wardrobeSegment = segment;
                                        this.smallWorldDestination = 'menu';
                                        this.switchMainTab(0);
                                    }
                                };
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "SmallWorldPage" });
                }
            });
            TabContent.tabBar({ builder: () => {
                    this.MainTabBar.call(this, MAIN_TABS[1]);
                } });
        }, TabContent);
        TabContent.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TabContent.create(() => {
                {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        if (isInitialRender) {
                            let componentCall = new MePage(this, {
                                onOpenHouse: (destination: string) => {
                                    this.openHouse(destination);
                                },
                                onOpenPet: () => {
                                    this.openPet();
                                }
                            }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 75, col: 7 });
                            ViewPU.create(componentCall);
                            let paramsLambda = () => {
                                return {
                                    onOpenHouse: (destination: string) => {
                                        this.openHouse(destination);
                                    },
                                    onOpenPet: () => {
                                        this.openPet();
                                    }
                                };
                            };
                            componentCall.paramsGenerator_ = paramsLambda;
                        }
                        else {
                            this.updateStateVarsOfChildByElmtId(elmtId, {});
                        }
                    }, { name: "MePage" });
                }
            });
            TabContent.tabBar({ builder: () => {
                    this.MainTabBar.call(this, MAIN_TABS[2]);
                } });
        }, TabContent);
        TabContent.pop();
        Tabs.pop();
    }
    private ActiveContent(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.isPetOpen) {
                this.ifElseBranchUpdateFunction(0, () => {
                    {
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            if (isInitialRender) {
                                let componentCall = new PetPage(this, {
                                    onOpenWardrobe: () => {
                                        this.switchMainTab(0);
                                    }
                                }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 102, col: 7 });
                                ViewPU.create(componentCall);
                                let paramsLambda = () => {
                                    return {
                                        onOpenWardrobe: () => {
                                            this.switchMainTab(0);
                                        }
                                    };
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
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.MainTabs.bind(this)();
                });
            }
        }, If);
        If.pop();
    }
    private MainTabBar(item: BottomTabItem, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.width('100%');
            Column.height(74);
            Column.justifyContent(FlexAlign.Center);
            Column.onClick(() => {
                if (item.index === 1 && this.currentIndex === 1 && this.smallWorldDestination !== 'menu') {
                    this.smallWorldDestination = 'menu';
                }
                this.switchMainTab(item.index);
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create();
            Stack.width(68);
            Stack.height(38);
            Stack.alignContent(Alignment.Center);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.currentIndex === item.index) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Circle.create({ width: 48, height: 36 });
                        Circle.fill(AppTheme.color.primaryMist);
                    }, Circle);
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: item.symbolName,
                        iconSize: item.index === 1 ? 28 : 25,
                        color: this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 120, col: 9 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: item.symbolName,
                            iconSize: item.index === 1 ? 28 : 25,
                            color: this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: item.symbolName,
                        iconSize: item.index === 1 ? 28 : 25,
                        color: this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary
                    });
                }
            }, { name: "AppSymbol" });
        }
        Stack.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.index === 1 ? this.houseTitle() : item.label);
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(this.currentIndex === item.index ? FontWeight.Bold : FontWeight.Medium);
            Text.fontColor(this.currentIndex === item.index ? AppTheme.color.textPrimary : AppTheme.color.textSecondary);
            Text.maxLines(1);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private PetEntryOverlay(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!this.isPetOpen && this.currentIndex !== 1) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Stack.create({ alignContent: Alignment.Bottom });
                        Stack.width(108);
                        Stack.height(64);
                        Stack.margin({ bottom: 70 });
                        Stack.onClick(() => {
                            this.openPet();
                        });
                    }, Stack);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Image.create({ "id": 16777227, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
                        Image.width(96);
                        Image.height(62);
                        Image.objectFit(ImageFit.Contain);
                    }, Image);
                    Stack.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
    }
    private openHouse(destination: string): void {
        if (destination === 'wardrobe' || destination === 'deposit') {
            this.wardrobeSegment = destination === 'deposit' ? 'deposit' : 'wardrobe';
            this.smallWorldDestination = 'menu';
            this.switchMainTab(0);
            return;
        }
        this.smallWorldDestination = destination;
        this.switchMainTab(1);
    }
    private openPet(): void {
        this.isPetOpen = true;
    }
    private switchMainTab(index: number): void {
        this.currentIndex = index;
        this.isPetOpen = false;
        this.tabsController.changeIndex(index);
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Bottom });
            Stack.width('100%');
            Stack.height('100%');
        }, Stack);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new WatercolorBackground(this, {}, undefined, elmtId, () => { }, { page: "entry/src/main/ets/pages/Index.ets", line: 188, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {};
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {});
                }
            }, { name: "WatercolorBackground" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.ActiveContent.bind(this)();
        Column.pop();
        this.PetEntryOverlay.bind(this)();
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
