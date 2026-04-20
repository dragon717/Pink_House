import type AbilityConstant from "@ohos:app.ability.AbilityConstant";
import UIAbility from "@ohos:app.ability.UIAbility";
import type Want from "@ohos:app.ability.Want";
import type window from "@ohos:window";
import { AppLogger } from "@bundle:com.pinkhouse.harmony/entry/ets/core/utils/AppLogger";
export default class EntryAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
        AppLogger.info('EntryAbility created');
    }
    onWindowStageCreate(windowStage: window.WindowStage): void {
        windowStage.loadContent('pages/Index', (error) => {
            if (error.code) {
                AppLogger.error(`Failed to load Index page. code=${error.code}, message=${error.message}`);
                return;
            }
            AppLogger.info('Index page loaded');
        });
    }
    onWindowStageDestroy(): void {
        AppLogger.info('EntryAbility window destroyed');
    }
    onDestroy(): void {
        AppLogger.info('EntryAbility destroyed');
    }
}
