export enum ReminderChannel {
  CheckIn = 'check_in',
  FinalPayment = 'final_payment',
  Pet = 'pet'
}

export class ReminderService {
  async schedule(channel: ReminderChannel, timestamp: number): Promise<void> {
    // TODO(M4): Integrate @ohos.reminderAgentManager with PRD channel mapping.
    void channel;
    void timestamp;
  }

  async cancel(channel: ReminderChannel): Promise<void> {
    // TODO(M4): Cancel reminders by persisted reminder id.
    void channel;
  }
}
