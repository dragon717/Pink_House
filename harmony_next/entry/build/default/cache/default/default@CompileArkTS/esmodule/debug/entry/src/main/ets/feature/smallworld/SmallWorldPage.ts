if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SmallWorldPage_Params {
}
import { FeatureShell } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/FeatureShell";
export class SmallWorldPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SmallWorldPage_Params) {
    }
    updateStateVars(params: SmallWorldPage_Params) {
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
                        title: '小世界',
                        badge: 'M3/M4',
                        description: '小世界首页、天气组件、签到入口与未来分布式流转能力的聚合页面。',
                        checklist: ['和风天气 JWT', '粗略定位降级', '签到状态', '平板/折叠屏布局预留']
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/smallworld/SmallWorldPage.ets", line: 6, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            title: '小世界',
                            badge: 'M3/M4',
                            description: '小世界首页、天气组件、签到入口与未来分布式流转能力的聚合页面。',
                            checklist: ['和风天气 JWT', '粗略定位降级', '签到状态', '平板/折叠屏布局预留']
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        title: '小世界',
                        badge: 'M3/M4',
                        description: '小世界首页、天气组件、签到入口与未来分布式流转能力的聚合页面。',
                        checklist: ['和风天气 JWT', '粗略定位降级', '签到状态', '平板/折叠屏布局预留']
                    });
                }
            }, { name: "FeatureShell" });
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
