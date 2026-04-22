import common from '@ohos.app.ability.common';
import { appPreferences } from './AppPreferences';
import { PreferenceKeys } from './PreferenceKeys';
import {
  DefaultSortOption,
  DefaultViewLayout,
  parseSortOption,
  parseViewLayout,
  WardrobeSortOption,
  WardrobeViewLayout
} from '../../domain/model/WardrobeListOptions';

export class WardrobePreferences {
  async getSortOption(context: common.Context): Promise<WardrobeSortOption> {
    const raw = await appPreferences.getString(context, PreferenceKeys.WardrobeSortOption, DefaultSortOption);
    return parseSortOption(raw);
  }

  async setSortOption(context: common.Context, option: WardrobeSortOption): Promise<void> {
    await appPreferences.putString(context, PreferenceKeys.WardrobeSortOption, option);
  }

  async getViewLayout(context: common.Context): Promise<WardrobeViewLayout> {
    const raw = await appPreferences.getString(context, PreferenceKeys.WardrobeViewLayout, DefaultViewLayout);
    return parseViewLayout(raw);
  }

  async setViewLayout(context: common.Context, layout: WardrobeViewLayout): Promise<void> {
    await appPreferences.putString(context, PreferenceKeys.WardrobeViewLayout, layout);
  }
}

export const wardrobePreferences = new WardrobePreferences();
