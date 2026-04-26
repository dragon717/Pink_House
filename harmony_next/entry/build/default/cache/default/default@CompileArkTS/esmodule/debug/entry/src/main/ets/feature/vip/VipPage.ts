if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface VipPage_Params {
}
import { FeatureShell } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/FeatureShell";
export class VipPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: VipPage_Params) {
    }
    updateStateVars(params: VipPage_Params) {
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
                        title: 'VIP',
                        badge: 'M6',
                        description: 'HMS IAP 仅用于喵币充值，VIP 通过喵币兑换，和 iOS/Android 产品规则保持一致。',
                        checklist: ['HMS 商品 ID', '订单验签', '幂等发币', '恢复购买']
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/vip/VipPage.ets", line: 6, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            title: 'VIP',
                            badge: 'M6',
                            description: 'HMS IAP 仅用于喵币充值，VIP 通过喵币兑换，和 iOS/Android 产品规则保持一致。',
                            checklist: ['HMS 商品 ID', '订单验签', '幂等发币', '恢复购买']
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        title: 'VIP',
                        badge: 'M6',
                        description: 'HMS IAP 仅用于喵币充值，VIP 通过喵币兑换，和 iOS/Android 产品规则保持一致。',
                        checklist: ['HMS 商品 ID', '订单验签', '幂等发币', '恢复购买']
                    });
                }
            }, { name: "FeatureShell" });
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
