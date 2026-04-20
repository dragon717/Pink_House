export interface AppSettingsRepository {
  hasAcceptedPrivacyPolicy(): Promise<boolean>;
  setPrivacyPolicyAccepted(accepted: boolean): Promise<void>;
}
