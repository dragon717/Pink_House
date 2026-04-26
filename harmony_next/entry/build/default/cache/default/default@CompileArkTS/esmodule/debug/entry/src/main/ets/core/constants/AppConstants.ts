interface AppConstantsConfig {
    appDisplayName: string;
    bundleName: string;
    databaseName: string;
    databaseVersion: number;
    preferencesName: string;
    backupSchemaVersion: number;
}
export const AppConstants: AppConstantsConfig = {
    appDisplayName: '少女心愿',
    bundleName: 'com.pinkhouse.harmony',
    databaseName: 'pink_house.db',
    databaseVersion: 4,
    preferencesName: 'pink_house_preferences',
    backupSchemaVersion: 1
};
