# 时光馆门店主题素材来源

三套皮肤均使用可核实的 PINK HOUSE 实体门店公开照片，经背景分离后仅用于时光馆商家选择入口。处理方式为保留门店主体、移除周边环境并生成透明 PNG；未修改编年史或图鉴数据。

| 主题 | 门店依据 | 原图 | 视觉方向 |
|---|---|---|---|
| Timeless 表参道 | [MELROSE 官方门店专题](https://www.melrose.co.jp/special/timeless_pinkhouse/) | [官方外观图](https://pinkhouse-webshop.jp/photo/page/TPH/image3.jpg) | 绿色屋顶、白色外墙、石材与黄色入口 |
| 名古屋松坂屋 | [PINK HOUSE 官方焕新公告](https://pinkhouse-webshop.jp/pinkhouse/news/839) | [官方店内图](https://pinkhouse-webshop.jp/photo/news/e1a4cbc517b6fb11f613c9628fcf031e.jpg) | 酒红陈列墙、象牙白与金属衣架 |
| 鹿儿岛山形屋 | [PINK HOUSE 官方焕新公告](https://pinkhouse-webshop.jp/pinkhouse/news/776) | [官方店内图](https://pinkhouse-webshop.jp/photo/news/open1.jpg) | 深木陈列、暖白灯光与开敞入口 |

抠图由内置图像编辑流程基于上述原图生成，再以纯色键控移除背景。素材只保留在 `ItemManager/Assets.xcassets/TimeHallStoreSkins/`，没有替换或删除既有图片。

## 品牌档案代表门店

以下素材只用于“选择品牌”页。Angelic Pretty 东京/大阪的当前门店页不再内嵌原图，处理时使用此前从对应官方页面保存的原始 JPEG；其余四张可由官方页面直接恢复。所有输出均只提取原图中的门店/店内主体，不新增门店、招牌、商品、人物或文字。

| 据点 | 官方页面 | 原图 | 输出 |
|---|---|---|---|
| Angelic Pretty 东京 | [原宿店](https://angelicpretty.com/Page/shop_harajuku.aspx) | 官方页面此前公开的店内原图（984×505，本地留存） | `store-angelic-pretty-tokyo.png` |
| Angelic Pretty 大阪 | [大阪店](https://angelicpretty.com/Page/shop_osaka.aspx) | 官方页面此前公开的门头原图（333×250，本地留存；确定性前景分割） | `store-angelic-pretty-osaka.png` |
| Angelic Pretty 巴黎 | [巴黎店](https://angelicpretty-paris.com/gb/page/7-the-angelic-pretty-paris-shop) | [官方门头原图](https://angelicpretty-paris.com/img/cms/000/Others/DSC01011%20copie%202.jpg) | `store-angelic-pretty-paris.png` |
| BABY 原宿本店 | [本店](https://www.babyssb.co.jp/locations/honten/) | [官方店内原图](https://www.babyssb.co.jp/wp-content/uploads/2021/11/shoplist_honten_photo.jpg) | `store-baby-honten.png` |
| BABY 大阪 | [大阪店](https://www.babyssb.co.jp/locations/osaka/) | [官方店内原图](https://www.babyssb.co.jp/wp-content/uploads/2021/11/shoplist_oosaka_photo.jpg) | `store-baby-osaka.png` |
| BABY 横滨 | [横滨店](https://www.babyssb.co.jp/locations/yokohama_baby/) | [官方店内原图](https://www.babyssb.co.jp/wp-content/uploads/2021/12/shoplist_yokohama_photo.jpg) | `store-baby-yokohama.png` |

输出目录：`ItemManager/Resources/TimeHall/images/`。除大阪低分辨率原图采用本地确定性前景分割外，其余五张使用内置图像编辑生成纯色键背景，再通过固定色键脚本输出透明 PNG。
