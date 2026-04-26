import hilog from "@ohos:hilog";
const DOMAIN = 0x0010;
const TAG = 'PinkHouse';
export class AppLogger {
    static info(message: string): void {
        console.log(`[${TAG}] ${message}`);
        console.info(`[${TAG}] ${message}`);
        hilog.info(DOMAIN, TAG, '%{public}s', message);
    }
    static warn(message: string): void {
        console.log(`[${TAG}] WARN ${message}`);
        console.warn(`[${TAG}] ${message}`);
        hilog.warn(DOMAIN, TAG, '%{public}s', message);
    }
    static error(message: string): void {
        console.log(`[${TAG}] ERROR ${message}`);
        console.error(`[${TAG}] ${message}`);
        hilog.error(DOMAIN, TAG, '%{public}s', message);
    }
}
