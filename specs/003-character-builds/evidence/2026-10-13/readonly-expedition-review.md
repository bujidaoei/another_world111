# 只读跨域与恢复审查

2026-10-13；没有修改Expedition/Inventory/Roster/Migration/Combat或根session/player/UI。独立artifact probe使用真实已实现RefCounted模型、实际配置和已有真实旧档夹具，不使用恶意subclass、假的事务接口或游戏内授予作弊。没有GPU/MCP运行。

证据目录artifacts/readonly-expedition-review：probe.gd、runtime.log、probe-result.json、source-hashes.json。固定Godot4.7.2，脚本exit0、零unexpected failed check/runtime error。210种组合：thief/healer × 起始余数0/18/19 × 0..6登记击杀 × 0..4登记采集；对ACTIVE/FAILURE/ENDED未提交/ENDED已提交完整回读、余数/货物篡改和实际收益计算，共7258个检查，均通过。该数量是独立断言检查，不冒充7258 GdUnit测试或实际PC玩法；这是发现下述问题的未修源码时点，不是修后验收。根随后正式改结算API，旧probe按旧签名保留，其命令不保证对新版源码直接可跑。

当前Inventory.grant→apply_operation和Roster.commit_coin_remainder同步且无signal/await/callback；双域预检后连续提交，在目前根主线程独占约束下未发现自然后半失败。真实CAS冲突/库存overflow拒绝均保两域，解除容量后同ID直接commit可重试，原对象重复commit阻挡。应保持跨域串行约束、全量提交之后才保存同一payload；不能把两次独立保存称磁盘原子。

发现与建议：

1. realm1完整候选可以携带focus CD12/effect4。Migration返回ok，恢复Combat后weapon_damage_multiplier=1.15。HP100、活动基础pulse/barrier合法；此组合违反二阶技能资格。建议恢复协调层预检世界境界与持续状态：realm1时focus冷却/效果、anchor冷却应为0；realm2卸装focus后保剩余效果仍合法。不要以当前loadout未装配为由清除合法二阶持续buff。
2. 结算overflow后模型已ENDED、rewards_committed=false。commit本身可安全重试；实际根_finish_run每次先resolve，第二次返回encounter_not_active，begin又返回settlement_pending。应为未结算ENDED建立独立retry/明确abort路径，重试不能重新resolve、发XP或重建遭遇；需要稳定settlement:<run_id> ID和资源管理/放弃反馈，不能把玩家锁在已结束区域。
3. 取旧未提交Expedition快照、先正常提交、随后把该旧快照恢复到新对象并使用已经提交的同一Inventory/Roster：healer余数不变，旧IDduplicate_operation正确阻挡，但新ID允许币2→4。此探针故意组合不同代域，不是同一SaveRepository整代快照的现玩家复现，也不宣称生产漏洞已利用。建议公开restore/settlement边界按run_id绑定一次奖励journal，而非仅依赖调用者可更换的ID；或明确restore必须与同代世界/库存/roster整体协调。
4. 根_finish_run资源/余数已提交以后，循环inventory.add_equipment并忽略返回。当前合法掉落ID路线通常不会失败，但混合重复/非法批次会部分新增、然后清pending且保存。建议新装备批次预检与资源在Inventory一次delivery操作提交；当前apply_operation只更新已有实例，不可把新掉落伪装updates。需要正式支持additions或独立atomic delivery API，并把其完整预检纳入remainder事务。

HP0：纯Migration已实测接受合法完整payload并原样保0，适合作为等待失败恢复的候选。根告知已加入显式35%失败回营恢复；应共用死亡恢复规则，清buff、保共享CD/经验/已入库资源/余数，丢pending，不以clamp下界1静默复活，也不将合法death候选误报坏档。审查时主场景正在003合并，未运行新场景或冒充此完整路径已验。

复跑：

```powershell
& $env:GODOT_BIN --headless --path game --script D:/bugu_projects/another_world/artifacts/readonly-expedition-review/probe.gd
```
