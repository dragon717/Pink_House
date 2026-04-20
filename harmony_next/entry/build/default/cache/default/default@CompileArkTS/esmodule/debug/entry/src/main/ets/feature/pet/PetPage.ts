if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface PetPage_Params {
}
import { FeatureShell } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/FeatureShell";
export class PetPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: PetPage_Params) {
    }
    updateStateVars(params: PetPage_Params) {
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
                        title: '宠物',
                        badge: 'M3',
                        description: '宠物状态、喂食、互动、提醒和序列帧动画的 HarmonyOS Next 原生实现入口。',
                        checklist: ['RDB: pet_states', 'reminderAgent 定时提醒', 'PNG 序列帧动画', 'Service Card 2x2 数据源']
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/pet/PetPage.ets", line: 6, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            title: '宠物',
                            badge: 'M3',
                            description: '宠物状态、喂食、互动、提醒和序列帧动画的 HarmonyOS Next 原生实现入口。',
                            checklist: ['RDB: pet_states', 'reminderAgent 定时提醒', 'PNG 序列帧动画', 'Service Card 2x2 数据源']
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        title: '宠物',
                        badge: 'M3',
                        description: '宠物状态、喂食、互动、提醒和序列帧动画的 HarmonyOS Next 原生实现入口。',
                        checklist: ['RDB: pet_states', 'reminderAgent 定时提醒', 'PNG 序列帧动画', 'Service Card 2x2 数据源']
                    });
                }
            }, { name: "FeatureShell" });
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
