# 真实业务发布准备（2026-10-09）

状态：已完成准备，等待用户指定店家范围；本轮未执行云端写入。

证据根：`output/业务发布/2026-10-09_补齐原图/`。用户请求为继续后续业务，按既有问题进入真实资料发布准备。

## 当前数据证据

- 只读检查手机 ShopCatalog 目录：612 张图 / 336684698 字节，运营覆盖层引用的 450 个本地图片文件全部存在；`devicectl device copy from` 图片目录退出 0，复制 612 张，450 个引用全部命中。没有修改手机。
- macOS 文件权限拒绝终端直接读取运营容器；改用正常访达复制已保存业务库及当前 staging 子目录，仅操作副本，不改变系统权限、不复制凭证。
- 同时运行两个运营实例：旧实例内存 revision 414，另一个实例及磁盘库 revision 457（均已保存）。以实际较新实例核对的 revision 457 为准；旧实例未用于保存或发布。SQLite 副本 integrity_check=ok，提取唯一当前目录：4 shops / 12 series / 277 products / 282 assets。
- 452 个本地引用文件全部在 Mac staging 副本，0 缺失；450 个与手机原文件逐字节 SHA-256 相同，0 不一致；2 个为 Mac 独有的图片。`business-image-check.json`。
- 完整备份 `current-business-backup.tar`：原目录 JSON + 452 个 images 文件，253706240 字节；`business-archive-check.json` 记录原目录摘要及归档摘要。原草稿没有被替换、没有执行补写。
- 两个真实店家分别 6 系列 / 169 商品和 4 系列 / 94 商品；另两个测试店家分别 1 系列 / 7 商品。用户范围问题已发出，回答前不执行范围筛选后的发布。
- `build_release.py --dry-run` 使用副本原目录、备份 staging、本地空输入目录；退出 0，构建校验通过，435 个去重媒体 / 243479378 字节、1523 条、1 个 shopCatalog 分片。未写线上，也未给其它 pending_review 来源放行。
- `ops_publish_bridge.py --mode pull-catalog` 独立取回 production 当前 seq 6，退出 0，根摘要同阶段 D 最终版；供后续合并比对。初次误写不存在的 mode `pull-content` 退出 2、未调用读写，修正参数后通过。

## 验证命令

```sh
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/build_release.py --input 'output/业务发布/2026-10-09_补齐原图/business-input' --shop-catalog 'output/业务发布/2026-10-09_补齐原图/mac-catalog-before.json' --shop-catalog-media 'output/业务发布/2026-10-09_补齐原图/mac-backup/5EF72441-3EB7-41C5-8594-EF58C7526EB7' --output 'output/业务发布/2026-10-09_补齐原图/offline-release-check' --release-seq 7 --previous-release-seq 6 --dry-run
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode pull-catalog --request 'output/业务发布/2026-10-09_补齐原图/production-current-request.json'
```

两条退出 0，完整结果分别见 `offline-release-check.log` / `production-current-read.ndjson`。本地 seq 7 仅为预检编号，不是实际发布。没有运行构建或新增测试，因为本轮没有修改运行代码。

## 后续边界

范围选定后使用较新目录，完整保留依赖的资产、规格、尺码表和价格事实，严格核对既有线上实体与删除标记，不以简单换序号冒充合并基线。发布前再次读取当前线上状态。真实上传及手机回读尚未完成，不把预检当作上线成功。

2026-10-08 旧包缺 174 张的记录属于历史现场；当前 Mac revision 457 已经不缺文件，本轮是只读核实及备份，不能声称本轮往真实 staging 补写了 174 张。
