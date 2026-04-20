import type common from "@ohos:app.ability.common";
import type { NewWardrobeItem, WardrobeItem } from '../../domain/model/WardrobeItem';
import type { WardrobeRepository } from '../../domain/repository/WardrobeRepository';
import { WardrobeItemDao } from "@bundle:com.pinkhouse.harmony/entry/ets/data/dao/WardrobeItemDao";
import { rdbStoreProvider } from "@bundle:com.pinkhouse.harmony/entry/ets/data/rdb/RdbStoreProvider";
export class RdbWardrobeRepository implements WardrobeRepository {
    private readonly context: common.Context;
    constructor(context: common.Context) {
        this.context = context;
    }
    async getActiveItems(): Promise<WardrobeItem[]> {
        const dao = await this.getDao();
        return dao.queryActiveItems();
    }
    async searchActiveItems(keyword: string): Promise<WardrobeItem[]> {
        const dao = await this.getDao();
        return dao.searchActiveItems(keyword);
    }
    async addItem(item: NewWardrobeItem): Promise<WardrobeItem> {
        const dao = await this.getDao();
        return dao.insertItem(item);
    }
    async addSampleItem(): Promise<WardrobeItem> {
        const dao = await this.getDao();
        return dao.insertSampleItem();
    }
    async softDeleteItem(id: string): Promise<void> {
        const dao = await this.getDao();
        await dao.softDeleteItem(id);
    }
    private async getDao(): Promise<WardrobeItemDao> {
        const store = await rdbStoreProvider.getStore(this.context);
        return new WardrobeItemDao(store);
    }
}
