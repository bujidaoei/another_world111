extends RefCounted

const Rules = preload("res://config/rules_config.gd")
const Config = preload("res://config/character_builds_config.gd")
const Presentation = preload("res://config/presentation_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Service = preload("res://features/equipment/equipment_service.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")
const Roster = preload("res://features/characters/character_roster.gd")
const Combat = preload("res://features/combat/combat_state.gd")

static func create(points: int = 10, realm: int = 1) -> Dictionary:
	var rules := Rules.new()
	rules.load_file("res://config/rules.json")
	var presentation: Dictionary = Presentation.load_file().data
	var config := Config.new()
	config.load_file("res://config/character_builds.json", presentation)
	var progress := Progress.new(rules)
	progress.award_experience(points * 20 if realm == 1 else 580, "fixture-world-growth")
	if realm == 2:
		progress.complete_ascension("rain_warden", "fixture-ascension", {"challenge_id": "rain_warden", "outcome": "victory", "run_id": "fixture-challenge", "defeated_enemy_ids": ["rain_warden"]})
	var inventory := Inventory.new(rules)
	var service := Service.new(rules)
	for id: String in ["starter", "material"]:
		var item: Dictionary = service.create_drop(id, 1, "rare", 4, {"location": "rain_court", "level": 1, "acquired_at": "2026-10-13T18:00:00+08:00"}, 27191).data.equipment
		item["affixes"] = [{"id": "power", "value": 25}, {"id": "haste", "value": 25}, {"id": "vitality", "value": 25}, {"id": "stamina", "value": 25}]
		item["equipped"] = id == "starter"
		inventory.add_equipment(item)
	var evaluator := Evaluator.new(config, rules, presentation)
	var roster := Roster.new(config, evaluator)
	roster.initialize("starter", progress, inventory)
	var combat := Combat.new(config)
	return {"rules": rules, "config": config, "presentation": presentation, "progress": progress, "inventory": inventory, "service": service, "evaluator": evaluator, "roster": roster, "combat": combat}

static func vitals(fixture: Dictionary, health_ratio: float = 0.4, stamina: float = 80.0) -> Dictionary:
	var stats: Dictionary = fixture.evaluator.evaluate(fixture.roster.active_build(), fixture.progress, fixture.inventory).data.stats
	return {"health": float(stats.max_health) * health_ratio, "stamina": stamina, "max_health": stats.max_health, "max_stamina": stats.max_stamina}

static func camp() -> Dictionary:
	return {"camp": true, "encounter_ended": true, "session_started": true}

static func combat_context(fixture: Dictionary) -> Dictionary:
	var build: Dictionary = fixture.roster.active_build()
	var item: Dictionary = fixture.inventory.get_equipment(build.weapon_id)
	return {"active_character_id": fixture.roster.active_character_id, "realm": fixture.progress.realm, "weapon_tier": int(item.tier), "skill_loadout": build.skill_loadout.duplicate(), "gameplay_running": true}
