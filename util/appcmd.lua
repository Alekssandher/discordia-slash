local dia = require("discordia")

local tools = require("./tools.lua")

local function PrintPermissionValue(value)
	return value and "**allowed**" or "**disallowed**"
end

local function DumpPermissions(perms)
	local result = {}

	for k, v in ipairs(perms.permissions) do
		result[k] = (v.type == dia.enums.appCommandPermissionType.role and "<@&" or "<@") .. v.id
			.. ">: " .. PrintPermissionValue(v.permission)
	end

	return table.concat(result, "\n")
end

local function DumpPermissionsList(list, client, guild_id)
	local result = {}
	local cmds = client:getGuildApplicationCommands(guild_id)

	for k, v in ipairs(list) do
		local cmd = cmds:get(v.id)
		result[#result + 1] = tools.serializeApplicationCommand(cmd)
		result[#result + 1] = "Everyone: " .. PrintPermissionValue(cmd.default_permission)
		result[#result + 1] = DumpPermissions(v)
		result[#result + 1] = ""
	end

	return table.concat(result, "\n")
end

local function FindLevel(ia, root_options, path)
	for level in string.gmatch(path, "[^.]+") do
		local option

		for k, v in ipairs(root_options) do
			if v.name == level then
				if v.type ~= dia.enums.appCommandOptionType.subCommand
					and v.type ~= dia.enums.appCommandOptionType.subCommandGroup then
					return tools.argError(ia, "where", level .. "is not a subcommand/group")
				end

				if not v.options then
					v.options = {}
				end

				option = v.options
				break
			end
		end

		if not option then
			return tools.argError(ia, "where", "Subcommand/Group " .. level .. " doesn't exist")
		end

		root_options = option
	end

	return root_options
end

local endpoints = {}

endpoints["permissions.get"] = function(ia, cmd, args)
	local id = args.id

	if not id then
		local perms, err = ia.client:getGuildApplicationCommandPermissions(ia.guild.id)

		if not perms then
			return tools.userError(ia, err)
		end

		local result = DumpPermissionsList(perms, ia.client, ia.guild.id)

		local success, error = ia:reply(result, true)

		if not success then
			print(result)

			ia:reply("See console", true)
		end
	else
		local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, id)

		if not cmd then
			return tools.argError(ia, "id", err)
		end

		local result = tools.serializeApplicationCommand(cmd)
			.. "\nEveryone: " .. PrintPermissionValue(cmd.default_permission)
		local perms = cmd:getPermissions()

		if perms then
			result = result .. "\n" .. DumpPermissions(perms)
		end

		ia:reply(result, true)
	end
end

local rolePermissionType = dia.enums.appCommandPermissionType.role
local userPermissionType = dia.enums.appCommandPermissionType.user

endpoints["permissions.set"] = function(ia, cmd, args)
	local id, what, value = args.id, args.what, args.value
	local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, id)

	if not cmd then
		return tools.argError(ia, "id", err)
	end

	local perms = cmd:getPermissions() or {
		permissions = {}
	}

	if value == 2 then
		for k, v in ipairs(perms.permissions) do
			if v.id == what.id then
				table.remove(perms.permissions, k)

				break
			end
		end
	else
		perms.permissions[#perms.permissions + 1] = {
			id = what.id,
			type = what.__name == "Role" and rolePermissionType or userPermissionType,
			permission = value == 0
		}
	end

	local data, err = cmd:editPermissions(perms)

	if not data then
		return tools.userError(ia, err)
	end

	ia:reply("Changed " .. (what.__name == "Role" and "<@&" or "<@") .. what.id .. "> permission to "
		.. (value == 2 and "**default**" or PrintPermissionValue(value == 0))
		.. " for " .. tools.serializeApplicationCommand(cmd), true)
end

function endpoints.create(ia, cmd, args)
	if args.type and args.type ~= dia.enums.appCommandType.chatInput then
		args.description = nil
	end

	local cmd, err = ia.client:createGuildApplicationCommand(ia.guild.id, {
		name = args.name,
		description = args.description,
		type = args.type,
		default_permission = args.default_permission
	})

	if not cmd then
		return tools.userError(ia, err)
	end

	ia:reply("Successfully created " .. tools.serializeApplicationCommand(cmd), true)
end

function endpoints.delete(ia, cmd, args)
	local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, args.id)

	if not cmd then
		return tools.argError(ia, "id", err)
	end

	local data, err = cmd:delete()

	if not data then
		return tools.userError(ia, err)
	end

	ia:reply("Successfully deleted " .. tools.serializeApplicationCommand(cmd), true)
end

function endpoints.code(ia, cmd, args)
	local data, err = ia.client._api:getGuildApplicationCommand(ia.client:getApplicationInformation().id,
		ia.guild.id, args.id)

	if not data then
		return tools.argError(ia, "id", err)
	end

	local json = require("json").encode(data)

	if #json > 2000 then
		p(data)

		json = "See console"
	end

	tools.tryReply(ia, json, true)
end

local printableOptionType = {
	[dia.enums.appCommandOptionType.subCommand] = "Subcommand",
	[dia.enums.appCommandOptionType.subCommandGroup] = "Subcommand Group",
	[dia.enums.appCommandOptionType.string] = "String",
	[dia.enums.appCommandOptionType.integer] = "Integer",
	[dia.enums.appCommandOptionType.boolean] = "Boolean",
	[dia.enums.appCommandOptionType.user] = "User",
	[dia.enums.appCommandOptionType.channel] = "Channel",
	[dia.enums.appCommandOptionType.role] = "Role",
	[dia.enums.appCommandOptionType.mentionable] = "Mentionable",
	[dia.enums.appCommandOptionType.number] = "Number",
	[dia.enums.appCommandOptionType.attachment] = "Attachment",
}

local function PrintOptions(options, inserter, indent)
	indent = indent or ""

	local last = #options

	for k, v in ipairs(options) do
		local attributes = {}

		if v.required then
			attributes[#attributes + 1] = "required"
		end

		if v.choices then
			attributes[#attributes + 1] = "choices:" .. #v.choices
		end

		if v.channel_types then
			attributes[#attributes + 1] = "channel_types:" .. table.concat(v.channel_types, "+")
		end

		if v.min_value then
			attributes[#attributes + 1] = "min_value:" .. v.min_value
		end

		if v.max_value then
			attributes[#attributes + 1] = "max_value:" .. v.max_value
		end

		if v.autocomplete then
			attributes[#attributes + 1] = "autocomplete"
		end

		inserter(indent .. (k == last and "└─" or "├─") .. " `" .. v.name .. "` ("
			.. printableOptionType[v.type] .. ") – *" .. v.description .. "*"
			.. (#attributes == 0 and "" or (" [" .. table.concat(attributes, ", ") .. "]")))

		if v.options then
			PrintOptions(v.options, inserter, k == last and indent .. "      " or indent .. "│     ")
		end
	end
end

function endpoints.get(ia, cmd, args)
	local result = {}

	local function insert(v)
		result[#result + 1] = v
	end

	if args.id then
		local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, args.id)

		if not cmd then
			return tools.argError(ia, "id", err)
		end

		insert(tools.serializeApplicationCommand(cmd))

		if cmd.description ~= "" then
			insert("*" .. cmd.description .. "*")
		end

		insert("Allowed for everyone: " .. PrintPermissionValue(cmd.default_permission))

		if cmd.options then
			insert("│")

			PrintOptions(cmd.options, insert)
		end

		result = table.concat(result, "\n")

		if #result > 2000 then
			print(result)

			result = "See console"
		end

		tools.tryReply(ia, result, true)

		return
	end

	insert("Application commands in this guild:")

	local slash, user, message = {}, {}, {}

	for k, v in pairs(ia.client:getGuildApplicationCommands(ia.guild.id)) do
		if v.type == dia.enums.appCommandType.chatInput then
			slash[#slash + 1] = v
		elseif v.type == dia.enums.appCommandType.user then
			user[#user + 1] = v
		elseif v.type == dia.enums.appCommandType.message then
			message[#message + 1] = v
		end
	end

	local function sorter(left, right)
		return left.name < right.name
	end

	table.sort(slash, sorter)
	table.sort(user, sorter)
	table.sort(message, sorter)

	if #slash ~= 0 then
		insert("Slash commands:")

		for k, v in ipairs(slash) do
			insert("`" .. v.name .. "` (" .. v.id .. ") – *" .. v.description .. "*")
		end

		insert("")
	end

	if #user ~= 0 then
		insert("User commands:")

		for k, v in ipairs(user) do
			insert("`" .. v.name .. "` (" .. v.id .. ")")
		end

		insert("")
	end

	if #message ~= 0 then
		insert("Message commands:")

		for k, v in ipairs(message) do
			insert("`" .. v.name .. "` (" .. v.id .. ")")
		end
	end

	result = table.concat(result, "\n")

	if #result > 2000 then
		print(result)

		result = "See console"
	end

	tools.tryReply(ia, result, true)
end

function endpoints.edit(ia, cmd, args)
	local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, args.id)

	if not cmd then
		return tools.argError(ia, "id", err)
	end

	local data, err = ia.client:editGuildApplicationCommand(ia.guild.id, cmd.id, {
		name = args.name,
		description = args.description,
		default_permission = args.default_permission,
	})

	if not data then
		return tools.argError(ia, "value", err)
	end

	ia:reply("Changed fields in " .. tools.serializeApplicationCommand(cmd), true)
end

local option_actions = {
	create = function(ia, where, args)
		local place = #where + 1

		if args.required then
			for k, v in ipairs(where) do
				if not v.required then
					place = k

					break
				end
			end
		end

		if args.channel_types then
			local types = args.channel_types

			if types == 0 then
				args.channel_types = {0, 5, 6}
			elseif types == 1 then
				args.channel_types = {2}
			elseif types == 2 then
				args.channel_types = {0, 5, 6, 2}
			elseif types == 3 then
				args.channel_types = {4}
			elseif types == 4 then
				args.channel_types = {13}
			elseif types == 5 then
				args.channel_types = {2, 13}
			elseif types == 6 then
				args.channel_types = {10, 11, 12}
			elseif types == 7 then
				args.channel_types = {10, 11, 12, 0, 5, 6}
			end
		end

		local option = {
			type = args.type,
			name = args.name,
			description = args.description,
			options = (args.type == dia.enums.appCommandOptionType.subCommand or args.type == dia.enums.appCommandOptionType.subCommandGroup) and {} or nil,
			required = args.required,
			min_value = args.min_value,
			max_value = args.max_value,
			autocomplete = args.autocomplete,
			channel_types = args.channel_types
		}

		if args.replace then
			for k, v in ipairs(where) do
				if v.name == args.name then
					where[k] = option
				end
			end
		else
			table.insert(where, place, option)
		end

		return true
	end,
	edit = function(ia, where, args)
		local found = false

		for k, v in ipairs(where) do
			if v.name == args.what then
				where = v

				found = true
			end
		end

		if not found then
			return tools.argError(ia, "what` or `where", "Option `" .. (args.where and (args.where .. ".") or "") .. args.what .. "` not found")
		end

		if args.type then
			where.type = args.type
		end

		if args.name then
			where.name = args.name
		end

		if args.description then
			where.description = args.description
		end

		if args.required ~= nil then
			where.required = args.required
		end

		if args.min_value then
			where.min_value = args.min_value
		end

		if args.max_value then
			where.max_value = args.max_value
		end

		if args.autocomplete ~= nil then
			where.autocomplete = args.autocomplete
		end

		if args.channel_types then
			local channel_types = {}

			for type in string.gmatch(args.channel_types, "%d+") do
				channel_types[#channel_types + 1] = tonumber(type)
			end

			where.channel_types = channel_types
		end

		return true
	end,
	delete = function(ia, where, args)
		if args.what == "/all" then
			for k in ipairs(where) do
				where[k] = nil
			end
		else
			local found = false

			for k, v in ipairs(where) do
				if v.name == args.what then
					table.remove(where, k)
					found = true

					break
				end
			end

			if not found then
				return tools.argError(ia, "what` or `where", "Option `" .. (args.where and (args.where .. ".") or "") .. args.what .. "` not found")
			end
		end

		return true
	end,
	move = function(ia, where, args)
		for k, v in ipairs(where) do
			if v.name == args.what then
				table.insert(where, args.place, table.remove(where, k))

				break
			end
		end

		return true
	end,
	choice = function(ia, where, args)
		local option

		for k, v in ipairs(where) do
			if v.name == args.what then
				option = v

				break
			end
		end

		if not option then
			return tools.argError(ia, "what` or `where", "Option `" .. (args.where and (args.where .. ".") or "") .. args.what .. "` not found")
		end

		local value = args.choice_value

		if option.type == dia.enums.appCommandOptionType.integer then
			local number = tonumber(value)

			if not number then
				return tools.argError(ia, "choice_value", "Choice value `" .. value .. "` can't be casted to number")
			end

			value = math.floor(number)
		elseif option.type == dia.enums.appCommandOptionType.number then
			local number = tonumber(value)

			if not number then
				return tools.argError(ia, "choice_value", "Choice value `" .. value .. "` can't be casted to number")
			end

			value = number
		end

		local choice = {
			name = args.choice_name,
			value = value
		}

		local choices = option.choices or {}

		choices[#choices + 1] = choice

		option.choices = choices

		return true
	end
}

function endpoints.option(ia, cmd, args, action, action_report)
	local cmd, err = ia.client:getGuildApplicationCommand(ia.guild.id, args.id)

	if not cmd then
		return tools.argError(ia, "id", err)
	end

	local options = cmd.options or {}

	local where = options

	if args.where then
		where = FindLevel(ia, options, args.where)
	end

	if not option_actions[action](ia, where, args) then
		return
	end

	local data, err = ia.client:editGuildApplicationCommand(ia.guild.id, cmd.id, {options = options})

	if not data then
		return tools.userError(ia, err)
	end

	ia:reply(action_report .. (args.where and (args.where .. ".") or "") .. (args.name or args.what) .. "` option in " .. tools.serializeApplicationCommand(cmd), true)
end

endpoints["option.create"] = function(ia, cmd, args)
	return endpoints.option(ia, cmd, args, "create", "Added `")
end

endpoints["option.edit"] = function(ia, cmd, args)
	return endpoints.option(ia, cmd, args, "edit", "Edited `")
end

endpoints["option.delete"] = function(ia, cmd, args)
	return endpoints.option(ia, cmd, args, "delete", "Removed `")
end

endpoints["option.move"] = function(ia, cmd, args)
	return endpoints.option(ia, cmd, args, "move", "Moved `")
end

endpoints["option.choice"] = function(ia, cmd, args)
	return endpoints.option(ia, cmd, args, "choice", "Added choice for `")
end

local function entry(CLIENT, GUILD)
	if not CLIENT or not GUILD then
		error("Client and Guild must be provided")
	end

	CLIENT:on("slashCommand", function(ia, cmd, args)
		if cmd.name == "appcmd" then
			local subcmd_args, path = tools.getSubCommand(cmd)

			local endpoint = endpoints[path]

			if endpoint then
				return endpoint(ia, cmd, subcmd_args)
			end

			return tools.userError(ia, "Unhandled request for /appcmd")
		end
	end)

	CLIENT:on("slashCommandAutocomplete", function(ia, cmd, focused)
		if cmd.name == "appcmd" then
			if cmd.focused_option.name == "id" then
				local cmds = CLIENT:getGuildApplicationCommands(ia.guild.id)
				local ac = {}
				local value = cmd.focused_option.value

				for k, v in pairs(cmds) do
					if value == "" or string.find(v.name, value, 1, true) or string.find(v.id, value, 1, true) then
						if #ac == 25 then
							break
						end

						ac[#ac + 1] = tools.choice(tools.serializeApplicationCommand(v), k)
					end
				end

				ia:autocomplete(ac)
			end
		end
	end)

	CLIENT:on("ready", function()
		local appcmd, err = CLIENT:createGuildApplicationCommand(GUILD, {
			name = "appcmd",
			description = "Utility to edit application commands from discord",
			type = dia.enums.appCommandType.chatInput,
			options = {
				{
					type = dia.enums.appCommandOptionType.subCommandGroup,
					name = "permissions",
					description = "Edit command permissions",
					options = {
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "get",
							description = "See permissions of all commands or specific one",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									autocomplete = true,
								}
							}
						},
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "set",
							description = "Set permission for a command",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.mentionable,
									name = "what",
									description = "What should have different permission",
									required = true,
								},
								{
									type = dia.enums.appCommandOptionType.integer,
									name = "value",
									description = "Value to set",
									required = true,
									choices = {
										tools.choice("Allow", 0),
										tools.choice("Disallow", 1),
										tools.choice("Default", 2)
									}
								},
							}
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommand,
					name = "create",
					description = "Create new command",
					options = {
						{
							type = dia.enums.appCommandOptionType.string,
							name = "name",
							description = "Command name",
							required = true
						},
						{
							type = dia.enums.appCommandOptionType.string,
							name = "description",
							description = "Command description (ignored for user and message commands)",
							required = true
						},
						{
							type = dia.enums.appCommandOptionType.integer,
							name = "type",
							description = "Command type (Slash command by default)",
							choices = {
								tools.choice("chatInput (Slash Command)", dia.enums.appCommandType.chatInput),
								tools.choice("user (User Command)", dia.enums.appCommandType.user),
								tools.choice("message (Message Command)", dia.enums.appCommandType.message)
							},
						},
						{
							type = dia.enums.appCommandOptionType.boolean,
							name = "default_permission",
							description = "Command default permission (true by default)",
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommand,
					name = "delete",
					description = "Delete command",
					options = {
						{
							type = dia.enums.appCommandOptionType.string,
							name = "id",
							description = "ApplicationCommand ID",
							required = true,
							autocomplete = true,
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommand,
					name = "get",
					description = "Get all commands or information about specific command",
					options = {
						{
							type = dia.enums.appCommandOptionType.string,
							name = "id",
							description = "ApplicationCommand ID",
							autocomplete = true,
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommand,
					name = "code",
					description = "Get command code",
					options = {
						{
							type = dia.enums.appCommandOptionType.string,
							name = "id",
							description = "ApplicationCommand ID",
							required = true,
							autocomplete = true,
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommand,
					name = "edit",
					description = "Edit first-level fields",
					options = {
						{
							type = dia.enums.appCommandOptionType.string,
							name = "id",
							description = "ApplicationCommand ID",
							required = true,
							autocomplete = true,
						},
						{
							type = dia.enums.appCommandOptionType.string,
							name = "name",
							description = "Command name",
						},
						{
							type = dia.enums.appCommandOptionType.string,
							name = "description",
							description = "Command description (slash commands only)",
						},
						{
							type = dia.enums.appCommandOptionType.boolean,
							name = "default_permission",
							description = "Command default permission (true by default)",
						}
					}
				},
				{
					type = dia.enums.appCommandOptionType.subCommandGroup,
					name = "option",
					description = "Option related category",
					options = {
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "create",
							description = "Create option",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.integer,
									name = "type",
									description = "Option type",
									required = true,
									choices = {
										tools.choice("Subcommand", dia.enums.appCommandOptionType.subCommand),
										tools.choice("Subcommand group", dia.enums.appCommandOptionType.subCommandGroup),
										tools.choice("String", dia.enums.appCommandOptionType.string),
										tools.choice("Integer", dia.enums.appCommandOptionType.integer),
										tools.choice("Boolean", dia.enums.appCommandOptionType.boolean),
										tools.choice("User", dia.enums.appCommandOptionType.user),
										tools.choice("Channel", dia.enums.appCommandOptionType.channel),
										tools.choice("Role", dia.enums.appCommandOptionType.role),
										tools.choice("Mentionable", dia.enums.appCommandOptionType.mentionable),
										tools.choice("Number", dia.enums.appCommandOptionType.number),
										tools.choice("Attachment", dia.enums.appCommandOptionType.attachment)
									}
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "name",
									description = "Option name",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "description",
									description = "Option description",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "where",
									description = "Place to insert (example: option.create) (root level by default)",
								},
								{
									type = dia.enums.appCommandOptionType.boolean,
									name = "required",
									description = "Is option required? (false by default)",
								},
								{
									type = dia.enums.appCommandOptionType.number,
									name = "min_value",
									description = "Minimum value for the option (Only for integer and number types)",
								},
								{
									type = dia.enums.appCommandOptionType.number,
									name = "max_value",
									description = "Maximum value for the option (Only for integer and number types)",
								},
								{
									type = dia.enums.appCommandOptionType.boolean,
									name = "autocomplete",
									description = "Autocompletion feature (only for string, integer and number types, false by default)",
								},
								{
									type = dia.enums.appCommandOptionType.integer,
									name = "channel_types",
									description = "Channel types allowed to pick (Only for channel type)",
									choices = {
										tools.choice("Text channels", 0),
										tools.choice("Voice channels", 1),
										tools.choice("Text and voice channels", 2),
										tools.choice("Categories", 3),
										tools.choice("Stage voice channels", 4),
										tools.choice("Voice and stage channels", 5),
										tools.choice("Threads", 6),
										tools.choice("Text channels and threads", 7),
									}
								},
								{
									type = dia.enums.appCommandOptionType.boolean,
									name = "replace",
									description = "Replace existing option"
								}
							}
						},
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "edit",
							description = "Edit option",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "what",
									description = "Option name",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "where",
									description = "Option location (example: option.create) (root level by default)",
								},
								{
									type = dia.enums.appCommandOptionType.integer,
									name = "type",
									description = "Option type",
									choices = {
										tools.choice("Subcommand", dia.enums.appCommandOptionType.subCommand),
										tools.choice("Subcommand group", dia.enums.appCommandOptionType.subCommandGroup),
										tools.choice("String", dia.enums.appCommandOptionType.string),
										tools.choice("Integer", dia.enums.appCommandOptionType.integer),
										tools.choice("Boolean", dia.enums.appCommandOptionType.boolean),
										tools.choice("User", dia.enums.appCommandOptionType.user),
										tools.choice("Channel", dia.enums.appCommandOptionType.channel),
										tools.choice("Role", dia.enums.appCommandOptionType.role),
										tools.choice("Mentionable", dia.enums.appCommandOptionType.mentionable),
										tools.choice("Number", dia.enums.appCommandOptionType.number),
										tools.choice("Attachment", dia.enums.appCommandOptionType.attachment)
									}
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "name",
									description = "New option name",
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "description",
									description = "Option description",
								},
								{
									type = dia.enums.appCommandOptionType.boolean,
									name = "required",
									description = "Is option required? (false by default)",
								},
								{
									type = dia.enums.appCommandOptionType.number,
									name = "min_value",
									description = "Minimum value for the option (Only for integer and number types)",
								},
								{
									type = dia.enums.appCommandOptionType.number,
									name = "max_value",
									description = "Maximum value for the option (Only for integer and number types)",
								},
								{
									type = dia.enums.appCommandOptionType.boolean,
									name = "autocomplete",
									description = "Autocompletion feature (only for string, integer and number types, false by default)",
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "channel_types",
									description = "Channel types allowed to pick separated by space (Only for channel type) ",
								},
							}
						},
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "delete",
							description = "Delete option",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "what",
									description = "Option name",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "where",
									description = "Place where the option is (example: option.create) (root level by default)",
								},
							}
						},
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "move",
							description = "Move option",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "what",
									description = "Option name",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.integer,
									name = "place",
									description = "Order",
									required = true,
									min_value = 1
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "where",
									description = "Place where the option is (example: option.create) (root level by default)",
								},
							}
						},
						{
							type = dia.enums.appCommandOptionType.subCommand,
							name = "choice",
							description = "Add choice to option",
							options = {
								{
									type = dia.enums.appCommandOptionType.string,
									name = "id",
									description = "ApplicationCommand ID",
									required = true,
									autocomplete = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "what",
									description = "Option name",
									required = true
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "choice_name",
									description = "Choice visible name",
									required = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "choice_value",
									description = "Choice value",
									required = true,
								},
								{
									type = dia.enums.appCommandOptionType.string,
									name = "where",
									description = "Place where the option is (example: option.create) (root level by default)",
								},
							}
						}
					}
				},
			},
			default_permission = false
		})

		appcmd:editPermissions({
			permissions = {
				{
					id = CLIENT.owner.id,
					type = dia.enums.appCommandPermissionType.user,
					permission = true
				}
			}
		})
	end)
end

return entry
