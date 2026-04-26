import { WardrobeItem } from '../model/WardrobeItem';

export const UNGROUPED_SERIES: string = '其他';

export interface SeriesGroup {
  seriesKey: string;
  itemIds: string[];
  count: number;
  totalBalance: number;
}

/**
 * 按 2-4 字符前缀聚类。取能命中至少 2 件的最长前缀；否则归入「其他」。
 */
export class SeriesAnalyzer {
  static group(items: WardrobeItem[]): SeriesGroup[] {
    const prefixCounts: Map<string, number> = new Map<string, number>();
    for (const item of items) {
      const trimmed: string = item.name.trim();
      for (let len = 2; len <= 4; len++) {
        if (trimmed.length >= len) {
          const p: string = trimmed.substring(0, len);
          prefixCounts.set(p, (prefixCounts.get(p) ?? 0) + 1);
        }
      }
    }

    const buckets: Map<string, WardrobeItem[]> = new Map<string, WardrobeItem[]>();
    for (const item of items) {
      const trimmed: string = item.name.trim();
      let key: string = UNGROUPED_SERIES;
      for (let len = 4; len >= 2; len--) {
        if (trimmed.length < len) {
          continue;
        }
        const p: string = trimmed.substring(0, len);
        if ((prefixCounts.get(p) ?? 0) >= 2) {
          key = p;
          break;
        }
      }
      const existing = buckets.get(key);
      if (existing) {
        existing.push(item);
      } else {
        buckets.set(key, [item]);
      }
    }

    const results: SeriesGroup[] = [];
    buckets.forEach((bucket: WardrobeItem[], key: string) => {
      let totalBalance: number = 0;
      const itemIds: string[] = [];
      for (const it of bucket) {
        totalBalance += it.balance * it.stock;
        itemIds.push(it.id);
      }
      const group: SeriesGroup = {
        seriesKey: key,
        itemIds,
        count: bucket.length,
        totalBalance
      };
      results.push(group);
    });

    results.sort((a: SeriesGroup, b: SeriesGroup) => {
      if (a.seriesKey === UNGROUPED_SERIES) {
        return 1;
      }
      if (b.seriesKey === UNGROUPED_SERIES) {
        return -1;
      }
      return b.count - a.count;
    });

    return results;
  }
}
