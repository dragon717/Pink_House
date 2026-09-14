# -*- coding: utf-8 -*-
"""仲夏物语种子数据：把「同一系列的多条独立链接」归集为一个商品。

背景：樱花小羊做了归集（5 条 → 1 个商品，款式 × 颜色 × 尺码 + SKU 表），
但其余系列还是「一个款一条记录」，同一个淘宝链接下的多款被拆成多条展示，
于是「已入库 / 已收藏」判断失真，价格区间也无处安放。

本脚本把每个多单品系列归集为一个商品：
  · 原来的**每条单品**降级为「款式」组的一个选项（这是最贴合原始数据的粒度：
    一条记录 = 一个链接 / 一款，不凭空再切分）
  · 颜色分类、尺码沿用各款**自己**登记的范围，不假装有全交叉
  · 价格挪进 SKU 表逐款标注，并带上口径（`priceKind`）
  · 定金无法归到某一款，留在系列级 `depositMin` / `depositMax`

只改数据，不改代码——模型与 resolver 在樱花小羊那轮已经支持 `variant`。
"""
import json
import collections

PATH = 'ItemManager/Resources/Midsummer/midsummer-series.json'
CAPTURE_FALLBACK = '2026-09-15'

COLOR_SLUG = {
    '粉色': 'pink', '浅青色': 'light-cyan', '奶白色': 'cream', '米色': 'beige',
    '蓝色': 'blue', '白色': 'white', '生成色': 'ecru', '酒红': 'wine',
    '红色': 'red', '绿色': 'green',
}
SIZE_SLUG = {'XS': 'xs', 'S': 's', 'M': 'm', 'L': 'l', 'XL': 'xl', '均码': 'onesize'}

# 款式名：默认去掉系列名前缀；前缀对不上（系列名与单品命名不一致）时在这里显式指定
STYLE_NAME_OVERRIDES = {
    'midsummer-2026-bear-museum-op': '切替 OP',
    'midsummer-2026-bear-museum-jsk': 'JSK',
    'midsummer-2025-wild-strawberry-2-set': 'JSK / 针织开衫 / 针织内搭',
    'midsummer-2025-wild-strawberry-2-accessory': '刺绣胸针 / 毛绒兔耳帽',
    'midsummer-2025-wild-strawberry-original': '初代（中长 OP 围裙 / JSK 针织内搭）',
    'midsummer-2022-peter-rabbit-op-solid': 'OP 纯色款',
    'midsummer-2022-peter-rabbit-op-sailor': 'OP 海军领款',
    'midsummer-2022-peter-rabbit-op-check': 'OP 格纹款',
    'midsummer-2022-peter-rabbit-op-apron': 'OP 围裙款',
    'midsummer-2022-peter-rabbit-op-doll': 'OP 娃娃领款',
    'midsummer-2022-peter-rabbit-jsk': 'JSK（Y0619）',
}

# 归集后需要交代的口径说明（写在商品 `priceNote` 里）
PRICE_NOTES = {
    'midsummer-2026-bear-museum':
        '两款（切替 OP / JSK）公开渠道均未查到价格，按「同一系列 = 同一商品」归集为一个链接；'
        '等拿到真实商品页再补逐款价。',
    'midsummer-2025-bow-eternal-garden':
        '逐款价来自品牌微博与第三方比价页：只有正腰 OP 查到现货参考价 499，'
        'JSK / 内搭 / 小物的公开渠道只给定金（¥388–399，见系列定金口径），故这三款在 SKU 表里不填价，'
        '不能拿定金去冒充全款。',
    'midsummer-2025-loire-vineyard-3':
        '两款的公开渠道价格都是**尾款**（OP 400 / 内搭·开衫 160），SKU 逐款标注口径为「尾款」，'
        '不要按全款估预算。',
    'midsummer-2025-bear-birthday':
        '两款的公开渠道价格都是**尾款**（裙装 152 / 小物 28）；裙装那条来源把切替 JSK、'
        '斜襟 OP、蛋糕开衫三型并在一个价里，本表不替它拆开。',
    'midsummer-2025-wild-strawberry-2':
        '2.0 两条的公开渠道价格是**尾款**（套装 160 / 小物 28）；初代一条是**定金** 47，'
        '无法归到某一款，故登记在系列级定金区间。'
        '⚠️ 初代与 2.0 是两代，淘宝侧可能仍是两个链接；这里按「同一系列」归集，'
        '拿到真实链接后再决定是否拆开。',
    'midsummer-2023-strawberry-chirp':
        '五款中只有小高腰 JSK 查到参考价 399（Lo 研社图鉴），其余四款来源只登记了款名，'
        '因此 SKU 表里不填价，避免拿别款的价格冒充。',
    'midsummer-2022-peter-rabbit':
        '逐款参考价来自什么值得买品牌页（¥160–554）；JSK 另有定金 75，'
        '无法归到某一款，登记在系列级定金区间（同一来源另记翻领蛋糕 OP 定金 99，未单列）。',
}

# 归集后系列级定金区间（原单品级定金无法归到某一款）
SERIES_DEPOSIT = {
    'midsummer-2025-wild-strawberry-2': (47, 47),
    'midsummer-2022-peter-rabbit': (75, 75),
}

SERIES_PRICE_SOURCE = {
    'midsummer-2025-wild-strawberry-2':
        '京东查查店铺比价页：2.0 尾款 ¥28–160；初代定金 ¥47',
    'midsummer-2022-peter-rabbit':
        '什么值得买品牌页（逐款参考价 ¥160–554）；京东查查比价页（JSK 定金 ¥75，'
        '另记翻领蛋糕 OP 定金 ¥99 未单列）',
}


def style_name(item, series_name):
    if item['id'] in STYLE_NAME_OVERRIDES:
        return STYLE_NAME_OVERRIDES[item['id']]
    name = item['name']
    for prefix in (series_name, series_name.replace('系列', '')):
        if prefix and name.startswith(prefix):
            return name[len(prefix):].strip()
    return name


def style_id(item, used):
    base = item['id'].rsplit('-', 1)[-1]
    candidate = base
    n = 2
    while candidate in used:
        candidate = f'{base}-{n}'
        n += 1
    used.add(candidate)
    return candidate


def money_and_kind(item):
    """把原单品的价格挪到 SKU 上，并给出口径。"""
    if item.get('price') is not None:
        return item['price'], (item.get('priceKind') or 'reference')
    if item.get('balance') is not None:
        # 来源是尾款就按尾款记，不要塞进「参考价」里冒充全款
        return item['balance'], 'balance'
    return None, None


def dedup(seq):
    return list(dict.fromkeys(seq))


def consolidate(series):
    items = series['items']
    if len(items) < 2:
        return series

    name = series['name']
    used = set()
    styles = []
    for it in items:
        styles.append({
            'sid': style_id(it, used),
            'name': style_name(it, name),
            'item': it,
        })

    colors = dedup([c for it in items for c in it.get('colors') or []])
    sizes = dedup([s for it in items for s in it.get('sizes') or []])

    groups = [{
        'id': 'style',
        'name': '款式',
        'role': 'variant',
        'options': [{'id': s['sid'], 'name': s['name'], 'image': None} for s in styles],
    }]
    if colors:
        groups.append({
            'id': 'color',
            'name': '颜色分类',
            'role': 'color',
            'options': [{'id': COLOR_SLUG.get(c, c), 'name': c, 'image': None} for c in colors],
        })
    if sizes:
        groups.append({
            'id': 'size',
            'name': '尺码',
            'role': 'size',
            'options': [{'id': SIZE_SLUG.get(s, s.lower()), 'name': s, 'image': None} for s in sizes],
        })

    # SKU 只在该款**自己**登记的颜色 / 尺码范围内生成，不假装有全交叉
    skus = []
    for s in styles:
        it = s['item']
        amount, kind = money_and_kind(it)
        item_colors = it.get('colors') or []
        item_sizes = it.get('sizes') or []
        for color in (item_colors or [None]):
            for size in (item_sizes or [None]):
                options = {'style': s['sid']}
                parts = [s['sid']]
                if color:
                    options['color'] = COLOR_SLUG.get(color, color)
                    parts.append(options['color'])
                if size:
                    options['size'] = SIZE_SLUG.get(size, size.lower())
                    parts.append(options['size'])
                skus.append({
                    'id': '-'.join(parts),
                    'options': options,
                    'image': None,
                    'price': amount,
                    'priceKind': kind,
                })

    captured = dedup(
        [it.get('priceCapturedOn') for it in items if it.get('priceCapturedOn')]
    )
    captured_on = captured[0] if captured else CAPTURE_FALLBACK

    notes = dedup([it.get('note') for it in items if it.get('note')])
    src = next((it.get('sourceURL') for it in items if it.get('sourceURL')), '')
    extra_sources = dedup([
        it['sourceURL'] for it in items
        if it.get('sourceURL') and it['sourceURL'] != src
    ])

    note_bits = ['按「同一系列 = 同一商品链接」归集为 1 个商品，'
                 f'含 {len(styles)} 个款式（款式 × 颜色分类 × 尺码）']
    if extra_sources:
        note_bits.append('其余来源：' + '、'.join(extra_sources))
    note = '；'.join(note_bits) + '。'

    # 各款自己的原始备注不能丢：那是「这一款为什么缺价 / 缺码」的唯一凭据
    per_style = []
    for s in styles:
        n = s['item'].get('note')
        if n:
            per_style.append(f"{s['name']}：{n}")
    if per_style:
        note += ' 各款备忘：' + ' | '.join(per_style)

    merged = {
        'id': series['id'],
        'seriesID': series['id'],
        'name': name,
        # 一个链接含多款 → 归类为 set，与樱花小羊口径一致；
        # 具体款数由卡片上的「含 N 个款式」承担，「套装」只是便于筛选的归类
        'kind': 'set',
        'price': None,
        'deposit': None,
        'balance': None,
        'priceKind': None,
        'priceCapturedOn': captured_on if any(sk['price'] for sk in skus) else None,
        'priceNote': PRICE_NOTES.get(series['id']),
        'sizes': sizes,
        'colors': colors,
        'coverImage': None,
        'itemURL': None,
        'sourceURL': src,
        'note': note,
        'specGroups': groups,
        'skus': skus,
    }

    series = dict(series)
    series['items'] = [merged]
    if series['id'] in SERIES_DEPOSIT:
        low, high = SERIES_DEPOSIT[series['id']]
        series['depositMin'] = low
        series['depositMax'] = high
    if series['id'] in SERIES_PRICE_SOURCE:
        series['priceSource'] = SERIES_PRICE_SOURCE[series['id']]
    if series.get('summary'):
        series['summary'] = series['summary'].rstrip('。') + '。'
    return series


def main():
    with open(PATH, encoding='utf-8') as f:
        data = json.load(f)

    # 樱花小羊已归集，只补 SKU 口径与采集日（有价必带口径，这条规则对 SKU 同样成立）
    for series in data['series']:
        if series['id'] != 'midsummer-2026-sakura-lamb':
            continue
        for it in series['items']:
            for sku in it.get('skus') or []:
                if sku.get('price') is not None:
                    sku['priceKind'] = 'reference'
            it['priceCapturedOn'] = it.get('priceCapturedOn') or CAPTURE_FALLBACK

    before = sum(len(s['items']) for s in data['series'])
    data['series'] = [consolidate(s) for s in data['series']]
    after = sum(len(s['items']) for s in data['series'])

    with open(PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')

    print(f'商品数 {before} → {after}')
    for s in data['series']:
        it = s['items'][0]
        kinds = collections.Counter(
            sk.get('priceKind') for sk in (it.get('skus') or []) if sk.get('price') is not None
        )
        print(f"  {s['id']:<42} 商品={len(s['items'])} 款式={it.get('variantCount', 1)} "
              f"SKU={len(it.get('skus') or [])} 价口径={dict(kinds) or '-'} "
              f"deposit={s.get('depositMin')}~{s.get('depositMax')}")


if __name__ == '__main__':
    main()
