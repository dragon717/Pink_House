import hilog from "@ohos:hilog";
const DOMAIN = 0x0010;
const TAG = 'PinkHouse';
export class AppLogger {
    static info(message: string): void {
        hilog.info(DOMAIN, TAG, '%{public}s', message);
    }
    static warn(message: string): void {
        hilog.warn(DOMAIN, TAG, '%{public}s', message);
    }
    static error(message: string): void {
        hilog.error(DOMAIN, TAG, '%{public}s', message);
    }
}
