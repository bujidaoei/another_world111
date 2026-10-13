extends RefCounted
class_name AWRuleResult

static func success(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": "ok", "message": "", "data": data}

static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "data": {}}
