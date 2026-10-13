# 冻结本地契约
统一result {ok,code,message,data}；Save可额外sequence/schema_version/recovered/migrated。
AWGameRules.new().load_file(path)；
AWWorldProgress.new(rules).award_experience(amount,operation_id),complete_ascension(challenge_id,operation_id,victory),snapshot/restore；
AWInventoryLedger.new(rules).can_apply_operation/apply_operation/grant(resources,operation_id),add_equipment/get_equipment/equipment_ids/count/snapshot/restore；
AWExpeditionState.new(rules).begin(run_id,region_id,challenge=false,realm=1,world_level=1),record_kill(enemy_id,progress),gather(node_id),complete_objective(progress),resolve(outcome,progress),reset,commit_rewards(operation_id,inventory),snapshot/restore；
AWEquipmentService.new(rules).create_drop(instance_id,tier,quality,slots,origin,seed),preview_fusion/fuse(inventory,IDs,locks,realm,in_camp,ended,...),preview_expansion/expand_slot,preview_ascension/ascend；
SaveRepository.configure(directory),save(payload),load()。
表现实体命中/采集真实发生才调用核心，不用eval直接授权晋阶或发资源代替完整验证。
相机自由/固定、输入UI消费、音频与VFX由表现层处理；各角色配置/冷却产品规则后续完整切片验证。
