## My simple save manager as autoload singleton godot

### ⚠️ Raw version, not very universal. However, it's MIT — do whatever you want

#### Features:
- [ConfigFile](https://docs.godotengine.org/en/latest/classes/class_configfile.html) format
- global save (for settings, etc)
- slot-based saves (for game saves, etc)
- CRUD save files
- Allow user edit save files, but with confirmation (each time)
- Backups
- Save format versioning
- Migrations -- applies the changes of each version sequentially
- Signals
  - save_started
  - save_completed
  - load_started
  - load_completed
- Check for corrupted save files
- Checksum validation
- Objects ([Dictionary](https://docs.godotengine.org/en/latest/classes/class_dictionary.html)) support inside save files

### TODO:
- [ ] clear this mess...


## Setup:
Add the script in the Autoload tab!

Handle the "global" save (for settings, etc.) inside the `apply_setting()` method.

## "Global" save
`const GLOBAL_VARS_PATH := "user://global.cfg"` -- uses own file. Use case -- settings that not depends on game progress.

Save: `Save.save_global()`

Load: `Save.load_global()` -- check for global. If no global -- create default. Calls `apply_setting()`


## Load:
Use `Save.load_data(slot: int)` for loading data in Save.DATA. Returns [ERR_FILE_CORRUPT](https://docs.godotengine.org/en/latest/classes/class_%40globalscope.html#enum-globalscope-error) or OK

Use now it like `Save.DATA.SINGLE_VAR`

## Get save file:
Use case example: save select page

`Save.get_save(slot: int)`  return Dictionary:
```gdscript
{
	"data": {}, # save data
	"corrupted": false, # if cfg.load != OK
	"error_code": OK, # Error int
}
```

`Save.check_save(slot: int = current_slot) -> bool` -- check if file exists for save

## Save:
`Save.save()` -- save current save file. Returns OK or [Error](https://docs.godotengine.org/en/latest/classes/class_%40globalscope.html#enum-globalscope-error)

## New game:
`Save.new_game()` -- Works in context of current save file. Will replace DATA with DATA_TEMPLATE

## Migration:
Use case: when you want to change the save file structure but still let players use their old files without breaking the game or requiring manual edits

Preparation:

- You **MUST** have a `migrations` folder in the root of the project
- Each migration must be named using the format: `migrate_%d_to_%d.gd` — versions must be integers ⚠️
- Each migration script **MUST** contain a `migrate` method
- Run using: `Save._apply_migrations(data: Dictionary, from_version: int, to_version: int)`

Migration script example:
```gdscript
# migrations/migrate_1_to_2.gd
extends Node

func migrate(data: Dictionary) -> Dictionary:
	if not data.has("TESTTT"):
		data["TESTTT"] = 12
	return data
```

Migration apply example:
```gdscript
	for slot in slots_to_migrate:
		var result := Save.get_save(slot)
		if result.error_code == OK:
			var version := Save.get_save_version(slot)
			var migrated := Save._apply_migrations(result.data, version, Save.SAVE_VERSION)
			var patched := Save.DATA_TEMPLATE.duplicate(true)
			Save._load_dict_from_data(patched, migrated)
			Save.DATA = patched
			Save.save(slot)
```
