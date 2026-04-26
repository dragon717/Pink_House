if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface SettingsPage_Params {
}
import { FeatureShell } from "@bundle:com.pinkhouse.harmony/entry/ets/feature/FeatureShell";
export class SettingsPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: SettingsPage_Params) {
    }
    updateStateVars(params: SettingsPage_Params) {
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
                        title: '设置',
                        badge: 'M7',
                        description: '隐私协议、备份导入导出、分享、字体注册和调试工具的集中入口。',
                        checklist: ['隐私弹窗', 'filePicker JSON 导入', 'systemShare 分享', 'rawfile/fonts 字体注册']
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/settings/SettingsPage.ets", line: 6, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            title: '设置',
                            badge: 'M7',
                            description: '隐私协议、备份导入导出、分享、字体注册和调试工具的集中入口。',
                            checklist: ['隐私弹窗', 'filePicker JSON 导入', 'systemShare 分享', 'rawfile/fonts 字体注册']
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        title: '设置',
                        badge: 'M7',
                        description: '隐私协议、备份导入导出、分享、字体注册和调试工具的集中入口。',
                        checklist: ['隐私弹窗', 'filePicker JSON 导入', 'systemShare 分享', 'rawfile/fonts 字体注册']
                    });
                }
            }, { name: "FeatureShell" });
        }
    }
    rerender() {
        this.updateDirtyElements();
    }
}
