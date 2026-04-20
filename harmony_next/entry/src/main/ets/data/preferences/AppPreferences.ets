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
    return store.get(key, defaultValue) as boolean;
  }

  async putBoolean(context: common.Context, key: PreferenceKeys, value: boolean): Promise<void> {
    const store = await this.getStore(context);
    await store.put(key, value);
    await store.flush();
  }
}

export const appPreferences = new AppPreferences();
