# 真实旧进度夹具

`domain1_real_save_slot.json` 原字节来自冻结002 release QA：`artifacts/performance/9dd871aca9fb458c887d80d4fca8945f/isolated-saves/slot_b.json`。

来源Windows PCK SHA256 `2C6AA3FCF54EE79BEC8D8357FC2A6C1EB236827203C96A2049DE340A71A6CAEE`；原槽SHA256 `5C5B755855F235E866E2D9F2E012172E36FD40AA25FFF995716141EF827182A8`，7,388B，envelope2/sequence50/domain1/input schema1。该进度由60秒真实InputEvent玩法产生：4次已结算远征，退出时第5次中断（run_counter5/interrupted_expedition=true）。level21/experience2、已入库币96/废铁36/晶片4；既有规则即时杀怪经验保留，未入库战利品不计入资源。不为迁移测试发奖励或手写世界成长。

夹具仅测试目录，发布排除。测试复制到独立user://tests/build_migration路径，再经实际双槽checksum读取、纯领域迁移、写入另一槽、回读；不访问或改变真实玩家档案。新增域零冷却是一度迁移默认：旧版本没有保存技能剩余冷却，不能恢复或虚构旧历史。
