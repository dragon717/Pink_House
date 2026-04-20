import relationalStore from "@ohos:data.relationalStore";
import type common from "@ohos:app.ability.common";
import { DatabaseSchema } from "@bundle:com.pinkhouse.harmony/entry/ets/data/rdb/DatabaseSchema";
import { AppLogger } from "@bundle:com.pinkhouse.harmony/entry/ets/core/utils/AppLogger";
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
        const store = await relationalStore.getRdbStore(context, config);
        await this.ensureSchema(store);
        this.store = store;
        return store;
    }
    private async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
        const statements: string[] = [
            DatabaseSchema.ddl.wardrobeItems,
            DatabaseSchema.ddl.petStates,
            DatabaseSchema.ddl.walletTransactions,
            DatabaseSchema.ddl.iapOrders
        ];
        for (const statement of statements) {
            await store.executeSql(statement);
        }
        AppLogger.info('RDB schema ensured');
    }
}
export const rdbStoreProvider = new RdbStoreProvider();
