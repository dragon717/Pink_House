if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SmallWorldPage_Params {
    destination?: string;
    onOpenWardrobe?: (segment: string) => void;
    mapWidth?: number;
}
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import { AppSymbol, AppSymbolName } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppSymbols";
import { GlassCard } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/GlassComponents";
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
export class SmallWorldPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__destination = new SynchedPropertySimpleTwoWayPU(params.destination, this, "destination");
        this.onOpenWardrobe = () => { };
        this.__mapWidth = new ObservedPropertySimplePU(0, this, "mapWidth");
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SmallWorldPage_Params) {
        if (params.onOpenWardrobe !== undefined) {
            this.onOpenWardrobe = params.onOpenWardrobe;
        }
        if (params.mapWidth !== undefined) {
            this.mapWidth = params.mapWidth;
        }
    }
    updateStateVars(params: SmallWorldPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__destination.purgeDependencyOnElmtId(rmElmtId);
        this.__mapWidth.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__destination.aboutToBeDeleted();
        this.__mapWidth.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __destination: SynchedPropertySimpleTwoWayPU<string>;
    get destination() {
        return this.__destination.get();
    }
    set destination(newValue: string) {
        this.__destination.set(newValue);
    }
    private onOpenWardrobe: (segment: string) => void;
    private __mapWidth: ObservedPropertySimplePU<number>;
    get mapWidth() {
        return this.__mapWidth.get();
    }
    set mapWidth(newValue: number) {
        this.__mapWidth.set(newValue);
    }
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
    private Header(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.padding({ left: AppTheme.spacing.page, right: AppTheme.spacing.page, top: 18 });
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.destination !== 'menu') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('‹ House');
                        Text.fontSize(AppTheme.font.body);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(AppTheme.color.primary);
                        Text.onClick(() => {
                            this.destination = 'menu';
                        });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create('House');
                        Text.fontSize(AppTheme.font.displayMedium);
                        Text.fontWeight(FontWeight.Bold);
                        Text.fontColor(AppTheme.color.textPrimary);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            __Common__.create();
            __Common__.width(54);
            __Common__.height(54);
            __Common__.backgroundColor('rgba(255, 255, 255, 0.30)');
            __Common__.borderRadius(AppTheme.radius.pill);
        }, __Common__);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: AppSymbolName.Import,
                        iconSize: 28,
                        color: AppTheme.color.textOnPrimary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/smallworld/SmallWorldPage.ets", line: 73, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: AppSymbolName.Import,
                            iconSize: 28,
                            color: AppTheme.color.textOnPrimary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: AppSymbolName.Import,
                        iconSize: 28,
                        color: AppTheme.color.textOnPrimary
                    });
                }
            }, { name: "AppSymbol" });
        }
        __Common__.pop();
        Row.pop();
    }
    private RoomBlock(title: string, tint: string, height: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.TopStart });
            Stack.width('100%');
            Stack.height(height);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height(height);
            Column.linearGradient({
                angle: 135,
                colors: [
                    [tint, 0.0],
                    ['rgba(255, 255, 255, 0.72)', 0.62],
                    [AppTheme.color.surfaceTint, 1.0]
                ]
            });
            Column.borderRadius(18);
            Column.border({ width: 1, color: 'rgba(255, 255, 255, 0.82)' });
        }, Column);
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor('rgba(255, 255, 255, 0.92)');
            Text.rotate({ angle: -22 });
            Text.margin({ top: 20, left: 18 });
        }, Text);
        Text.pop();
        Stack.pop();
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
    private Hotspot(item: HotspotSpec, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 6 });
            Row.padding({ left: 10, right: 10, top: 6, bottom: 6 });
            Row.backgroundColor('rgba(50, 35, 43, 0.30)');
            Row.backgroundBlurStyle(BlurStyle.Thin);
            Row.borderRadius(AppTheme.radius.pill);
            Row.rotate({ angle: -22 });
            Row.position({
                x: `${(item.xPct * 100).toFixed(1)}%`,
                y: `${(item.yPct * 100).toFixed(1)}%`
            });
            Row.onClick(() => {
                if (item.destination === 'wardrobe') {
                    this.onOpenWardrobe('wardrobe');
                }
                else if (item.destination === 'deposit') {
                    this.onOpenWardrobe('deposit');
                }
                else {
                    this.destination = item.destination;
                }
            });
        }, Row);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: item.symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textOnPrimary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/smallworld/SmallWorldPage.ets", line: 130, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: item.symbolName,
                            iconSize: 20,
                            color: AppTheme.color.textOnPrimary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: item.symbolName,
                        iconSize: 20,
                        color: AppTheme.color.textOnPrimary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(item.title);
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textOnPrimary);
        }, Text);
        Text.pop();
        Row.pop();
    }
    private HouseMap(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.scrollBar(BarState.Off);
            Scroll.onAreaChange((_oldValue: Area, newValue: Area) => {
                const w = newValue.width as number;
                if (w > 0) {
                    this.mapWidth = w;
                }
            });
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.TopStart });
            Stack.width('100%');
            Stack.height(this.mapTotalHeight());
            Stack.padding({ left: 18, right: 18, top: 10, bottom: 130 });
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: -(this.roomImageHeight() * ROOM_OVERLAP_RATIO) });
            Column.width('100%');
            Column.padding({ top: 10 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Image.create({ "id": 16777228, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
            Image.width('100%');
            Image.height(this.roomImageHeight());
            Image.objectFit(ImageFit.Contain);
        }, Image);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Image.create({ "id": 16777229, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
            Image.width('100%');
            Image.height(this.roomImageHeight());
            Image.objectFit(ImageFit.Contain);
        }, Image);
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const item = _item;
                this.Hotspot.bind(this)(item);
            };
            this.forEachUpdateFunction(elmtId, HOUSE_HOTSPOTS, forEachItemGenFunction, (item: HotspotSpec) => item.destination, false, false);
        }, ForEach);
        ForEach.pop();
        Stack.pop();
        Scroll.pop();
    }
    private DestinationSkeleton(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.scrollBar(BarState.Off);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.width('100%');
            Column.padding({ bottom: 130 });
        }, Column);
        this.Header.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.margin({ left: AppTheme.spacing.page, right: AppTheme.spacing.page });
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 22, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 14 });
                                Column.width('100%');
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.destinationTitle());
                                Text.fontSize(AppTheme.font.displayMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('这是从 House 热区进入的 HarmonyOS Next 子集骨架。这里保留本地数据、普通动效和页面入口，不显示 AI、CloudKit、RealityKit 或裙子股市。');
                                Text.fontSize(AppTheme.font.body);
                                Text.lineHeight(24);
                                Text.fontColor(AppTheme.color.textSecondary);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 12 });
                                Row.width('100%');
                            }, Row);
                            this.ActionTile.bind(this)('返回 House', AppSymbolName.House, () => {
                                this.destination = 'menu';
                            });
                            this.ActionTile.bind(this)('去衣橱', AppSymbolName.Wardrobe, () => {
                                this.onOpenWardrobe('wardrobe');
                            });
                            Row.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/smallworld/SmallWorldPage.ets", line: 203, col: 11 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 22,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 14 });
                                    Column.width('100%');
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create(this.destinationTitle());
                                    Text.fontSize(AppTheme.font.displayMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                    Text.width('100%');
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('这是从 House 热区进入的 HarmonyOS Next 子集骨架。这里保留本地数据、普通动效和页面入口，不显示 AI、CloudKit、RealityKit 或裙子股市。');
                                    Text.fontSize(AppTheme.font.body);
                                    Text.lineHeight(24);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                    Text.width('100%');
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create({ space: 12 });
                                    Row.width('100%');
                                }, Row);
                                this.ActionTile.bind(this)('返回 House', AppSymbolName.House, () => {
                                    this.destination = 'menu';
                                });
                                this.ActionTile.bind(this)('去衣橱', AppSymbolName.Wardrobe, () => {
                                    this.onOpenWardrobe('wardrobe');
                                });
                                Row.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 22, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
        Column.pop();
        Column.pop();
        Scroll.pop();
    }
    private ActionTile(label: string, symbolName: string, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 8 });
            Column.layoutWeight(1);
            Column.height(92);
            Column.justifyContent(FlexAlign.Center);
            Column.backgroundColor(AppTheme.color.surfaceTint);
            Column.borderRadius(AppTheme.radius.tile);
            Column.onClick(onTap);
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 30,
                        color: AppTheme.color.primary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/smallworld/SmallWorldPage.ets", line: 244, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 30,
                            color: AppTheme.color.primary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 30,
                        color: AppTheme.color.primary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.width('100%');
            Column.height('100%');
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.destination === 'menu') {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.Header.bind(this)();
                    this.HouseMap.bind(this)();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.DestinationSkeleton.bind(this)();
                });
            }
        }, If);
        If.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
