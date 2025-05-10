
# Migratus Orchestrus
### For Factorio

This mod is micro auxilary library with purpose of simplifying *Lua state* migrations (upgrades) between mod versions.

While default Factorio has built-in migration mechanism, it was designed specifically for migrating (adjusting) save state's
to fit mod's changes to content, or mod content changes between its versions. This one is designed **specifically** for migrating
Lua state.

Another difference between this library and built-in migrations is that migrations are not executed upon adding the mod to
existing save, because there is nothing to migrate, as all data structures will be populated inside `script.on_init` callback,
which will be already on latest data version.

# Using the Library

**It is assumed that you posess intermediate Lua knowledge, if you do not, this library is not for you.**

## Importing the library

For starters, you need to import *builder* entry point of this library into your script:

```lua
local migratus_factory = require('__migratus-orchestrus__/init.lua')
```

In code piece above, `migratus_factory` will end up being a function, which you must call before you can use the library,
like so:

```lua
local migrations = migratus_factory()
```

This is done for purpose for allowing multiple independent migration controllers to be active at the same time inside
single Lua state/mod (since `requrie` executes every script only once per Lua state and caches return value).

*This allows you to depend on Migratus Orchestrus inside auxilary library mods* and not be concerned with interfering with migrations
declared by mods which depend on both your library and Migratus.

If you will ever need only one migration list in your code (which is often the case), code blocks above can be simplified to:

```lua
local migrations = require('__migratus-orchestrus__/init.lua')()
```

## Declaring migrations

To make actual use of library, you first need to declare migration(s) to be applied,
using `add_migration_path` (for easily attaching scripts) and `add_migration_function`
(for attaching plain Lua functions).

When using `add_migration_path`, path supplied **must** point to file, which has `return function() ... end`
as its final statement (think of every Lua file in your mod being just a big function, from which you can return),
for example:

In your main control file:
```lua
-- Syntax:
-- add_migration_path(version: integer, path: string)
-- __my-mod__/ can be omitted (INCLUDING the slash, if you do), as Migratus will prepend it for you if you don't put it in
migrations.add_migration_path(1, '__my-mod__/runtime_migrations/initial.lua')
```

In `__my-mod__/runtime_migrations/initial.lua`:
```lua
-- here you can put any extra code at top, just make sure it *does not*
-- affect anything (unless you CERTAINLY KNOW what you are doing!),
-- because every single migration file will be require()'d inside add_migration_path()
-- for example:
local function helperMethod(...) -- correct
	-- do stuff
end

local thing = { ... } -- also correct

script.on_event(..., function() end) -- INCORRECT! don't do this unless you understand what you are doing

-- function returned from this file will be called if migration needs to be applied
return function()
	storage.b = storage.a
	-- more migrations...
end
```

Alternatively, `add_migration_function` can be used, for example:

```lua
-- Syntax:
-- add_migration_function(version: integer, callback: function)
migrations.add_migration_function(1, function()
	-- body of this function will be called if "initial" migration wasn't applied
	storage.b = storage.a
	-- more migrations...
end)
```

`version` of migration, as name says, is a *positive integer*, representing mod version.
The only requirenment for `version` is to be continuous at every given moment in mod's codebase lifetime.
In other words:

```lua
-- correct
migrations.add_migration_path(1, ...)
migrations.add_migration_path(2, ...)
migrations.add_migration_function(3, ...)
migrations.add_migration_path(4, ...)

-- ALSO correct! read further on Migratus behavior in this case
migrations.add_migration_path(3, ...)
migrations.add_migration_function(4, ...)
migrations.add_migration_path(5, ...)
migrations.add_migration_path(6, ...)

-- this is also allowed, but generally discouraged because you may get quickly lost
migrations.add_migration_path(4, ...)
migrations.add_migration_path(1, ...)
migrations.add_migration_path(3, ...)
migrations.add_migration_path(2, ...)

-- incorrect! will throw an error inside on_init/on_configuration_changed/on_load call
migrations.add_migration_path(1, ...)
-- missing 2nd migration
migrations.add_migration_path(3, ...)
migrations.add_migration_path(4, ...)

-- also incorrect
migrations.add_migration_path(1, ...)
migrations.add_migration_path(2, ...)
migrations.add_migration_path(3, ...)
migrations.add_migration_path(3, ...) -- with throw an error here immediately
migrations.add_migration_path(4, ...)
```

Migrations are applied order of their respective version number,
so `add_migration_path`/`add_migration_function` can be called in any order,
as demonstrated by code above.

---

**Important:** by default, applied migrations are stored inside `storage['migratus-orchestrus']`.
If you are a library developer, or you need multiple migration lists inside your mod, make sure to call `set_storage_key`
with your unique name of choice, for example:

```lua
-- Initially, it is implicit that this was called:
-- migrations.set_storage_key('migratus-orchestrus')
migrations.set_storage_key('flib_migrations')
```

`set_storage_key` can be called at any time before `on_init/on_configuration_changed/on_load` call.

---

## Tying code together

To apply migrations, Migratus Orchestrus exposes next functions which correspond to hooks
provided by Factorio engine:

```lua
migrations.on_init() -- to be called inside script.on_init() callback
migrations.on_load() -- *conditionally* to be called inside script.on_load() callback
migrations.on_configuration_changed() -- to be called inside script.on_configuration_changed() callback
```

In most basic scenario, your mod `control.lua` may look like this:

```lua
script.on_init(function()
	migrations.on_init()
end)

script.on_load(function()
	migrations.on_load()
end)

script.on_configuration_changed(function(event)
	migrations.on_configuration_changed()
end)
```

However, considering you use this library in first place, means you already have some code
which declare some variables in `storage` table, and maybe doing basic migrations inside `if` blocks in `on_configuration_changed`.

For example, consider your mod looking like this:

```lua
script.on_init(function()
	-- assume storage.thingies was {players = {}} upon mod initial release,
	-- and now it also contains bars = {}
	storage.thingies = {
		players = {},
		bars = {}
	}

	storage.bars_added = true
end)

script.on_configuration_changed(function(event)
	if not storage.bars_added then
		storage.bars_added = true
		storage.thingies.bars = {}
	end
end)
```

Not ideal. And as mod structures evolve, it will get more convoluted, and harder to maintain.

With this library, with most basic integration, code above will turn into:

```lua
local migrations = require('__migratus-orchestrus__/init.lua')()

migrations.add_migration_function(1, function()
	storage.thingies.bars = {}
end)

script.on_init(function()
	-- assume storage.thingies was {players = {}} upon mod initial release,
	-- and now it also contains bars = {}
	storage.thingies = {
		players = {},
		bars = {}
	}

	migrations.on_init()
end)

-- next call can be omitted, because in our case it does no useful work
-- read further to know when this should be called
script.on_load(function()
	migrations.on_load()
end)

script.on_configuration_changed(function(event)
	migrations.on_configuration_changed()
end)
```

And just like that, `bars` will be added to `thingies`.

## Taming `on_load`

If your mod makes use of `on_load` script callback, be it for setting up locals,
re-attaching metatables, or both, we get a problem: when we update to new mod version,
data structures might have been changed, and `on_load` expects new data structure, but save
file contains outdated data strcutures!

For such case, Migratus Orchestrus provides next functions, which will make it painless
to use `on_load` again:

```lua
-- to be called inside `script.on_load` function,
-- which may as well be replaced with `script.on_load(migrations.on_load)` in very simple case
migrations.on_load()

-- The new entry point for mod's `on_load` code
-- this function is substitude for `script.on_load`
migrations.on_setup_globals(callback)

-- Returns whenever data structures were migrated to latest version
migrations.is_up_to_date()
```

Let's consider example mod's code from above again, but this time, with `on_load` function:

```lua
-- store globals inside local variables for way faster lookup
local players, bars

script.on_init(function()
	-- assume storage.thingies was {players = {}} upon mod initial release,
	-- and now it also contains bars = {}
	storage.thingies = {
		players = {},
		bars = {}
	}

	storage.bars_added = true
	-- duplicating on_load logic!
	players = storage.thingies.players
	bars = storage.thingies.bars
end)

script.on_load(function()
	players = storage.thingies.players
	bars = storage.thingies.bars
end)

script.on_configuration_changed(function(event)
	if not storage.bars_added then
		storage.bars_added = true
		storage.thingies.bars = {}
		bars = storage.thingies.bars -- duplicating on_load logic!
	end
end)
```

Surely, we could move `on_load` body into separate function, and call it from both `on_init` and `on_load`,
but this does not fix the issue with `on_configuration_changed` duplicating `on_load` logic, because
after mod update, `storage.thingies.bars` will be `nil` the moment `on_load` is called, so we have to assign
it again inside `on_configuration_changed`, after we migrated.

With Migratus Orchestrus, the following code will become much cleaner and straightforward:

```lua
local migrations = require('__migratus-orchestrus__/init.lua')()

migrations.add_migration_function(1, function()
	storage.thingies.bars = {}
end)

-- store globals inside local variables for way faster lookup
local players, bars

-- on_setup_globals will be called either inside `on_init` or `on_load` if there is no migrations to apply
-- or `on_configuration_changed` after all migrations have been applied
migrations.on_setup_globals(function()
	players = storage.thingies.players
	bars = storage.thingies.bars
end)

script.on_init(function()
	-- assume storage.thingies was {players = {}} upon mod initial release,
	-- and now it also contains bars = {}
	storage.thingies = {
		players = {},
		bars = {}
	}

	migrations.on_init()
end)

script.on_load(migrations.on_load)
script.on_configuration_changed(migrations.on_configuration_changed)
```

`on_setup_globals` can be called multiple times (this won't overwrite),
and all functions will be called in the same order as they were added by `migrations.on_setup_globals`.

## Advanced usage

For advanced users there are a few extra things which have their use, but generally you wouldn't use them.

### `bump_version` function

This function is generally used when migrating from other migration systems (such as from Factorio Library,
or in-house solution), to mark migration(s) as already applied, like so:

```lua
-- Syntax: migrations.bump_version(version: integer)
migrations.bump_version(3)
```

`version` can be any version declared by `add_migration_path` and `add_migration_function`, going outside that
range will throw an error.

The function itself **must** be called in context where `storage` is available, such as inside `script.on_configuration_changed`,
right before `on_configuration_changed` of Migratus' call, example:

```lua
script.on_configuration_changed(function(event)
	if storage.my_own_migrations then
		-- determine current version --
		migrations.bump_version(12)
		storage.my_own_migrations = nil
	end

	migrations.on_configuration_changed()
end)
```

### Declaring migrations with version not starting from `1`

Usually, you declare migrations starting from number `1`,
but during mod lifetime evolution, it may happen that old migrations are no longer feasiable due to
engine and/or mod changes, or straight up impossible. In such case, older migrations can be removed from
mod codebase. If user will try to load save which require removed migrations to be applied, they
will be greeted with error message explaining that to migrate the save they must load it with older
version of the mod installed, and then update to more recent mod version.
