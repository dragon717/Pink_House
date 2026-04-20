if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface WealthPage_Params {
}
import { FeatureShell } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/FeatureShell";
export class WealthPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: WealthPage_Params) {
    }
    updateStateVars(params: WealthPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
    }
    aboutToBeDeleted() {
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    initialRender() {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new FeatureShell(this, {
                        title: '财富',
                        badge: 'M5',
                        description: '喵币流水、账本、尾款提醒、拼豆和 OOTD 统计能力的占位入口。',
                        checklist: ['RDB: wallet_transactions', '尾款 Calendar 提醒', '资产趋势统计', 'Service Card 2x4 数据源']
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/wealth/WealthPage.ets", line: 6, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            title: '财富',
                            badge: 'M5',
                            description: '喵币流水、账本、尾款提醒、拼豆和 OOTD 统计能力的占位入口。',
                            checklist: ['RDB: wallet_transactions', '尾款 Calendar 提醒', '资产趋势统计', 'Service Card 2x4 数据源']
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        title: '财富',
                        badge: 'M5',
                        description: '喵币流水、账本、尾款提醒、拼豆和 OOTD 统计能力的占位入口。',
                        checklist: ['RDB: wallet_transactions', '尾款 Calendar 提醒', '资产趋势统计', 'Service Card 2x4 数据源']
                    });
                }
            }, { name: "FeatureShell" });
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
