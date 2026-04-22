import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { AppConstants } from '../../core/constants/AppConstants';
import { PreferenceKeys } from './PreferenceKeys';

export class AppPreferences {
  private preferencesStore?: preferences.Preferences;

  async getStore(context: common.Context): Promise<preferences.Preferences> {
    if (this.preferencesStore) {
      return this.preferencesStore;
    }

    this.preferencesStore = await preferences.getPreferences(context, AppConstants.preferencesName);
    return this.preferencesStore;
  }

  async getBoolean(context: common.Context, key: PreferenceKeys, defaultValue: boolean): Promise<boolean> {
    const store = await this.getStore(context);
    return await store.get(key, defaultValue) as boolean;
  }

  async putBoolean(context: common.Context, key: PreferenceKeys, value: boolean): Promise<void> {
    const store = await this.getStore(context);
    await store.put(key, value);
    await store.flush();
  }

  async getString(context: common.Context, key: PreferenceKeys, defaultValue: string): Promise<string> {
    const store = await this.getStore(context);
    return await store.get(key, defaultValue) as string;
  }

  async putString(context: common.Context, key: PreferenceKeys, value: string): Promise<void> {
    const store = await this.getStore(context);
    await store.put(key, value);
    await store.flush();
  }

  async getNumber(context: common.Context, key: PreferenceKeys, defaultValue: number): Promise<number> {
    const store = await this.getStore(context);
    return await store.get(key, defaultValue) as number;
  }

  async putNumber(context: common.Context, key: PreferenceKeys, value: number): Promise<void> {
    const store = await this.getStore(context);
    await store.put(key, value);
    await store.flush();
  }
}

export const appPreferences = new AppPreferences();
