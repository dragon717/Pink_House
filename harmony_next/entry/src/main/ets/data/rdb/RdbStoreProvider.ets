import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { DatabaseSchema } from './DatabaseSchema';
import { AppLogger } from '../../core/utils/AppLogger';

export class RdbStoreProvider {
  private store?: relationalStore.RdbStore;

  async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (this.store) {
      return this.store;
    }

    const config: relationalStore.StoreConfig = {
      name: DatabaseSchema.name,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    AppLogger.info(`[RDB] opening ${DatabaseSchema.name}, databaseDir=${context.databaseDir}`);
    const store = await relationalStore.getRdbStore(context, config);
    await this.ensureSchema(store);
    this.store = store;
    return store;
  }

  private async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const currentVersion = store.version;
    const targetVersion = DatabaseSchema.version;

    if (currentVersion !== targetVersion) {
      AppLogger.info(`RDB version ${currentVersion} -> ${targetVersion}, rebuilding wardrobe_items + tags`);
      await store.executeSql('DROP TABLE IF EXISTS wardrobe_items');
      await store.executeSql('DROP TABLE IF EXISTS tags');
      await store.executeSql('DROP TABLE IF EXISTS wardrobe_item_tags');
    }

    const statements: string[] = [
      DatabaseSchema.ddl.wardrobeItems,
      DatabaseSchema.ddl.tags,
      DatabaseSchema.ddl.wardrobeItemTags,
      DatabaseSchema.ddl.petStates,
      DatabaseSchema.ddl.walletTransactions,
      DatabaseSchema.ddl.iapOrders
    ];

    for (const statement of statements) {
      await store.executeSql(statement);
    }

    if (currentVersion !== targetVersion) {
      store.version = targetVersion;
    }
    AppLogger.info('RDB schema ensured');
  }
}

export const rdbStoreProvider = new RdbStoreProvider();
