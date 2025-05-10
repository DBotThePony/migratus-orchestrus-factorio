
return function()
	local lib = {}
	local storage_key = 'migratus-orchestrus'
	local migrations = {}
	local __setup_globals = {}
	local lowest_version = math.huge
	local highest_version = 0

	local function assertArgument(num, fnname, argument, expected, default)
		if argument == nil and default ~= nil then return default end
		local t = type(argument)

		if t ~= expected then
			error(string.format('bad argument #%d to %s: %s expected, got %s', num, fnname, expected, t))
		end

		return argument
	end

	function lib.set_storage_key(_storage_key)
		assertArgument(1, 'set_storage_key', _storage_key, 'string')
		storage_key = _storage_key
	end

	local function hasMigration(version)
		for _, data in ipairs(migrations) do
			if data.version == version then return true end
		end

		return false
	end

	function lib.add_migration_path(version, path)
		assertArgument(1, 'add_migration_path', version, 'number')
		assertArgument(2, 'add_migration_path', path, 'string')
		assert(not hasMigration(version), 'duplicate migration version: ' .. version)
		assert(math.floor(version) == version, 'version must be whole number')
		assert(version > 0, 'version must be positive')

		if string.sub(path, 1, 2) ~= '__' then
			path = string.format('__%s__/%s', script.mod_name, path)
		end

		local func = require(path)

		if type(func) ~= 'function' then
			error('Migration script must return a function to be executed (problematic script: ' .. path .. ' for migration version ' .. version .. ')')
		end

		table.insert(migrations, {version = version, func = func})
		lowest_version = math.min(lowest_version, version)
		highest_version = math.max(highest_version, version)
	end

	function lib.add_migration_function(version, func)
		assertArgument(1, 'add_migration_function', version, 'number')
		assertArgument(2, 'add_migration_function', func, 'function')
		assert(not hasMigration(version), 'duplicate migration version: ' .. version)
		assert(math.floor(version) == version, 'version must be whole number')
		assert(version > 0, 'version must be positive')

		table.insert(migrations, {version = version, func = func})
		lowest_version = math.min(lowest_version, version)
		highest_version = math.max(highest_version, version)
	end

	function lib.is_up_to_date()
		return (storage[storage_key] or 0) >= highest_version
	end

	local function callSetup()
		assert(__setup_globals, 'on_load already called')

		for _, fn in ipairs(__setup_globals) do
			fn()
		end

		__setup_globals = nil
	end

	local function sortMigrations()
		table.sort(migrations, function(a, b)
			return a.version < b.version
		end)

		for i = 2, #migrations do
			if migrations[i].version - 1 ~= migrations[i - 1].version then
				error(string.format('Migrations defined for mod %s are not continuous, after version %d comes version %d', script.mod_name, migrations[i - 1].version, migrations[i].version))
			end
		end
	end

	function lib.on_init()
		sortMigrations()
		storage[storage_key] = highest_version
		migrations = nil
		callSetup()
	end

	function lib.on_load()
		assert(__setup_globals ~= nil, 'on_init/on_load/on_configuration_changed already called')
		if not lib.is_up_to_date() then return end
		sortMigrations()
		callSetup()
	end

	function lib.on_configuration_changed()
		if __setup_globals == nil and lib.is_up_to_date() then
			return
		end

		assert(__setup_globals ~= nil, 'on_init/on_load/on_configuration_changed already called')
		storage[storage_key] = storage[storage_key] or 0

		if storage[storage_key] > 0 and storage[storage_key] < lowest_version then
			error('Mod ' .. script.mod_name .. ' can not be migrated, save file is too old. Please load previous mod version(s) until save file can be properly migrated.')
		end

		sortMigrations()

		for i = storage[storage_key] - lowest_version + 2, #migrations do
			local data = migrations[i]
			log(string.format('%s: Applying migration for version %d', script.mod_name, data.version))
			data.func()
		end

		storage[storage_key] = highest_version
		migrations = nil
		callSetup()
	end

	function lib.on_setup_globals(callback)
		assert(__setup_globals, 'on_load already called')
		table.insert(__setup_globals, callback)
	end

	function lib.bump_version(version)
		assertArgument(1, 'bump_version', version, 'number')
		assert(version >= lowest_version, 'provided version (' .. version .. ') is lower than lowest possible version: ' .. lowest_version)
		assert(version <= highest_version, 'provided version (' .. version .. ') is higher than highest possible version: ' .. highest_version)

		if (storage[storage_key] or 0) < version then
			storage[storage_key] = version
		end
	end

	return lib
end
