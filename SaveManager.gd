extends Node

signal save_started(slot: int)
signal save_completed(slot: int, error_code: int)
signal load_started(slot: int)
signal load_completed(slot: int, error_code: int)

const MAX_BACKUPS := 10
const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const SAVE_TEMPLATE := SAVE_DIR + "/save_%d.cfg"
const GLOBAL_VARS_PATH := "user://global.cfg"
const ignore_description = 'To edit the save file, set ignore_checksum_check to true; otherwise, the file will be perceived as corrupted'
var current_slot := 0

const GLOBAL_VARS_TEMPLATE := {
	'OPTIONS': {
		'FULLSCREEN': false,
		'SFX': 0.5,
		'MUSIC': 0.5,
	}
}
var GLOBAL_VARS := GLOBAL_VARS_TEMPLATE.duplicate(true)

const DATA_TEMPLATE := {
	'SINGLE_VAR': false,
	'OBJECT': {
		'EXAMPLE': 1,
	},
}
var DATA := DATA_TEMPLATE.duplicate(true)

func _ready():
	load_global()

func new_game():
	DATA = DATA_TEMPLATE.duplicate(true)
	prints('[SAVE]', 'new game')
	var err = save()
	if err != OK:
		prints('[SAVE]', 'new_game save failed: %d' % err)

func get_save_path(slot := current_slot) -> String:
	return SAVE_TEMPLATE % slot

func get_save_version(slot := current_slot) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(get_save_path(slot)) == OK:
		return cfg.get_value("METADATA", "version", 0)
	return 0

func save(slot := current_slot) -> int:
	save_started.emit(slot)
	current_slot = slot
	var dir = DirAccess.open("user://")
	prints('[SAVE]', 'Saving slot %d' % slot)
	if dir == null:
		prints('[SAVE]', 'Failed to open user directory for saves')
		save_completed.emit(slot, ERR_CANT_OPEN)
		return ERR_CANT_OPEN
	var err = dir.make_dir_recursive("saves")
	if err != OK and err != ERR_ALREADY_EXISTS:
		prints('[SAVE]', 'Error creating save dir: %d' % err)
		save_completed.emit(slot, err)
		return err
	var cfg = ConfigFile.new()
	cfg.set_value('METADATA', 'version', SAVE_VERSION)
	cfg.set_value('METADATA', '_ignore_description', ignore_description)
	cfg.set_value('METADATA', 'ignore_checksum_check', false)

	var to_save = DATA.duplicate(true)

	var checksum = _compute_checksum(to_save)

	cfg.set_value('METADATA', 'version', SAVE_VERSION)
	cfg.set_value('METADATA', '_ignore_description', ignore_description)
	cfg.set_value('METADATA', 'ignore_checksum_check', false)
	cfg.set_value('METADATA', 'checksum', checksum)

	_save_dict(cfg, 'DATA', to_save)

	var tmp_path = SAVE_DIR + "/save_%d.tmp.cfg" % slot
	var final_path = get_save_path(slot)
	err = cfg.save(tmp_path)
	if err != OK:
		prints('[SAVE]', 'Error saving temp file "%s": %d' % [tmp_path, err])
		save_completed.emit(slot, err)
		return err
	if dir.file_exists(final_path):
		dir.remove(final_path)
	err = dir.rename(tmp_path, final_path)
	if err != OK:
		prints('[SAVE]', 'Error renaming temp file: %d' % err)
		save_completed.emit(slot, err)
		return err

	var backup_dir := "user://backups/slot_%d" % slot
	err = dir.make_dir_recursive(backup_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		prints('[SAVE]', 'Failed to create backup dir: %d' % err)
	else:
		var timestamp := Time.get_datetime_string_from_system().replace(":", "").replace(" ", "_")
		var backup_path := backup_dir + "/save_%s.cfg" % timestamp
		var copy_err := dir.copy(final_path, backup_path)
		if copy_err != OK:
			prints("[SAVE]", "Backup copy failed: %d" % copy_err)

		var backups := DirAccess.get_files_at(backup_dir)
		backups.sort()
		while backups.size() > MAX_BACKUPS:
			var old_backup := backup_dir + "/" + backups[0]
			backups.remove_at(0)
			DirAccess.remove_absolute(old_backup)

	save_completed.emit(slot, OK)
	return OK

func save_global() -> int:
	var cfg := ConfigFile.new()
	_save_dict(cfg, "GLOBAL_VARS", GLOBAL_VARS)
	var err := cfg.save(GLOBAL_VARS_PATH)
	if err != OK:
		prints("[SAVE]", "Error saving global vars: %d" % err)
		return err
	return OK

func get_save(slot := current_slot) -> Dictionary:
	var result := {
		"data": {},
		"corrupted": false,
		"error_code": OK,
	}

	var cfg := ConfigFile.new()
	var err := cfg.load(get_save_path(slot))
	if err == ERR_FILE_NOT_FOUND:
		result.error_code = err
		return result
	elif err != OK:
		result.corrupted = true
		result.error_code = err
		return result

	var version = cfg.get_value("METADATA", "version", 0)
	if version != SAVE_VERSION:
		prints("[SAVE]", "get_save version mismatch: %d vs %d" % [version, SAVE_VERSION])

	var ignore = cfg.get_value("METADATA", "ignore_checksum_check", false)
	var raw := {}

	if version == SAVE_VERSION:
		_load_dict(cfg, "DATA", raw, DATA_TEMPLATE)

		var saved_checksum = cfg.get_value("METADATA", "checksum", "")
		var actual_checksum := _compute_checksum(raw)
		# prints(saved_checksum, actual_checksum)
		if saved_checksum != actual_checksum and not ignore:
			result.corrupted = true
			result.error_code = ERR_FILE_CORRUPT
			return result
	else:
		var section := "DATA"
		for key in cfg.get_section_keys(section):
			raw[key] = cfg.get_value(section, key)

	result.data = raw
	return result

func load_data(slot := current_slot) -> int:
	load_started.emit(slot)
	current_slot = slot
	var cfg = ConfigFile.new()
	var err = cfg.load(get_save_path())
	prints('[SAVE]', 'Loading slot %d' % slot)

	var raw := {}
	var valid := false

	if err == ERR_FILE_NOT_FOUND:
		prints('[SAVE]', 'Save not found, using defaults')
	elif err != OK:
		prints('[SAVE]', 'Load failed (%d), using defaults' % err)
	else:
		var version = cfg.get_value('METADATA', 'version', 0)
		if version != SAVE_VERSION:
			prints('[SAVE]', 'Save version mismatch: %d vs %d' % [version, SAVE_VERSION])

		var ignore = cfg.get_value('METADATA', 'ignore_checksum_check', false)
		_load_dict(cfg, 'DATA', raw, DATA_TEMPLATE)

		if not ignore:
			var loaded = cfg.get_value('METADATA', 'checksum', '')
			var actual = _compute_checksum(raw)
			if loaded != actual:
				prints('[SAVE]', 'Checksum mismatch: %s vs %s' % [loaded, actual])
				load_completed.emit(slot, ERR_FILE_CORRUPT)
				return ERR_FILE_CORRUPT

		valid = true

	DATA = raw if valid else DATA_TEMPLATE.duplicate(true)

	load_completed.emit(slot, OK)
	return OK

func check_save(slot: int = current_slot) -> bool:
	return FileAccess.file_exists(get_save_path(slot))

func delete_save(slot: int = current_slot):
	prints('[SAVE]', 'Removing slot %d' % slot)
	var save_path := get_save_path(slot)
	if not FileAccess.file_exists(save_path):
		push_warning("[SAVE] Save file not found: %s" % save_path)
	else:
		if DirAccess.remove_absolute(save_path) != OK:
			push_warning("[SAVE] Could not delete save file at %s" % save_path)

	var backup_dir := "user://backups/slot_%d" % slot
	if DirAccess.dir_exists_absolute(backup_dir):
		var files := DirAccess.get_files_at(backup_dir)
		for file in files:
			var file_path := backup_dir + "/" + file
			var remove_err := DirAccess.remove_absolute(file_path)
			if remove_err != OK:
				push_warning("[SAVE] Failed to delete backup file: %s (err %d)" % [file_path, remove_err])

		var err := DirAccess.remove_absolute(backup_dir)
		if err != OK:
			push_warning("[SAVE] Could not delete backup directory at %s (err %d)" % [backup_dir, err])

func load_global() -> int:
	var cfg := ConfigFile.new()
	var err := cfg.load(GLOBAL_VARS_PATH)
	if err == OK:
		GLOBAL_VARS = {}
		_load_dict(cfg, "GLOBAL_VARS", GLOBAL_VARS, GLOBAL_VARS_TEMPLATE)
		apply_setting()
		return OK

	if err != ERR_FILE_NOT_FOUND:
		prints("[SAVE]", "Load global vars failed: %d" % err)

	GLOBAL_VARS = GLOBAL_VARS_TEMPLATE.duplicate(true)
	apply_setting()
	return err

func apply_setting():
	# Handle your settings here
	pass

func _save_dict(cfg: ConfigFile, section: String, data: Dictionary) -> void:
	for k in data.keys():
		var v = data[k]
		if typeof(v) == TYPE_DICTIONARY:
			_save_dict(cfg, section + '/' + k, v)
		else:
			cfg.set_value(section, k, v)

func _load_dict(cfg: ConfigFile, section: String, out: Dictionary, tpl: Dictionary) -> void:
	for k in tpl.keys():
		var d = tpl[k]
		if typeof(d) == TYPE_DICTIONARY:
			var sub := {}
			_load_dict(cfg, section + '/' + k, sub, d)
			for sub_key in cfg.get_section_keys(section + '/' + k):
				if not sub.has(sub_key):
					sub[sub_key] = cfg.get_value(section + '/' + k, sub_key)
			out[k] = sub

		else:
			out[k] = cfg.get_value(section, k, d)

func _compute_checksum(data: Dictionary) -> String:
	var json_str = JSON.stringify(data)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(json_str.to_utf8_buffer())
	var digest = ctx.finish()
	return digest.hex_encode()

func _apply_migrations(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	for v in range(from_version, to_version):
		var script_path := "res://migrations/migrate_%d_to_%d.gd" % [v, v + 1]
		if ResourceLoader.exists(script_path):
			var migration = load(script_path).new()
			if migration.has_method("migrate"):
				data = migration.migrate(data)
				prints("[MIGRATION]", "Applied migration: %d → %d" % [v, v + 1])
			else:
				push_error("[MIGRATION] Migration script %s missing 'migrate' method" % script_path)
		else:
			push_warning("[MIGRATION] Missing migration script: %s" % script_path)
	return data

func _load_dict_from_data(out: Dictionary, src: Dictionary) -> void:
	for k in out.keys():
		if typeof(out[k]) == TYPE_DICTIONARY and k in src and typeof(src[k]) == TYPE_DICTIONARY:
			_load_dict_from_data(out[k], src[k])
		elif k in src:
			out[k] = src[k]
