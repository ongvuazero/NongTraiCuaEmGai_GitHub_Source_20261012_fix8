extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	UILocale.initialize()
	if not QARichFixture.requested(): failures.append("Explicit debug rich flag missing")
	if not OS.get_environment("MSF_TEST_SAVE_DIR").is_empty(): failures.append("This test needs the real rich fallback, not env override")
	if GameState.save_service._base_dir != "user://qa_rich/": failures.append("Save root leaked outside QA")
	if UILocale._preferences_path() != "user://qa_rich/ui_preferences.cfg": failures.append("Language preference leaked outside QA")
	QARichFixture.apply()
	if int(GameState.data.inventory.seed_carrot) != 999: failures.append("QA seeds are not999")
	if int(GameState.data.inventory.crop_pumpkin) != 999: failures.append("QA crops are not999")
	if GameState.dragon_energy() != 99: failures.append("Dragon currency must use99 wallet cap")
	if GameState.data.inventory.has("dragon_energy"): failures.append("Phantom Dragon currency stack")
	if not GameState.save("hub"): failures.append("QA autosave path failed")
	var snapshot: Dictionary = GameState.data.inventory.duplicate(true)
	GameState.data.inventory.seed_carrot = -1
	if not GameState.load_slot(3) or GameState.data.inventory != snapshot: failures.append("QA save reload did not restore999")
	UILocale.set_locale("en")
	if not FileAccess.file_exists("user://qa_rich/ui_preferences.cfg"): failures.append("QA locale not persisted")
	GameState.new_state(1, false)
	if int(GameState.data.inventory.seed_carrot) != 6 or int(GameState.data.coins) != 400: failures.append("QA changed production initial values")
	var file := FileAccess.open("res://REPORTS/MASTER_PLAN_V1/QA_ISOLATION_RESULTS.txt", FileAccess.WRITE)
	file.store_line("QA_RICH_ISOLATION_PASS" if failures.is_empty() else "QA_RICH_ISOLATION_FAIL")
	file.store_line("Save root: " + GameState.save_service._base_dir)
	file.store_line("Preferences: " + UILocale._preferences_path())
	for issue in failures: file.store_line(issue)
	file.close()
	print("QA_RICH_ISOLATION_PASS" if failures.is_empty() else "QA_RICH_ISOLATION_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
