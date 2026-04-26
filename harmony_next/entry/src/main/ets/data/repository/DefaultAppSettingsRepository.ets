import common from '@ohos.app.ability.common';
import { AppSettingsRepository } from '../../domain/repository/AppSettingsRepository';
import { appPreferences } from '../preferences/AppPreferences';
import { PreferenceKeys } from '../preferences/PreferenceKeys';

export class DefaultAppSettingsRepository implements AppSettingsRepository {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  hasAcceptedPrivacyPolicy(): Promise<boolean> {
    return appPreferences.getBoolean(this.context, PreferenceKeys.PrivacyPolicyAccepted, false);
  }

  setPrivacyPolicyAccepted(accepted: boolean): Promise<void> {
    return appPreferences.putBoolean(this.context, PreferenceKeys.PrivacyPolicyAccepted, accepted);
  }
}
