local Client = {}

local discordia = require("discordia")
require("discordia-interactions")

local API = require("./API")
local Cache = discordia.class.classes.Cache
local ApplicationCommand = require("containers/ApplicationCommand")

function Client:getGuildApplicationCommands(guild_id)
	local data, err = self._api:getGuildApplicationCommands(self:getApplicationInformation().id, guild_id)

	if data then
		return Cache(data, ApplicationCommand, self)
	else
		return nil, err
	end
end

function Client:createGuildApplicationCommand(guild_id, id, payload)
	local data, err = self._api:createGuildApplicationCommand(self:getApplicationInformation().id, guild_id, id)

	if data then
		return ApplicationCommand(data, self)
	else
		return nil, err
	end
end

function Client:getGuildApplicationCommand(guild_id, id)
	local data, err = self._api:getGuildApplicationCommand(self:getApplicationInformation().id, guild_id, id)

	if data then
		return ApplicationCommand(data, self)
	else
		return nil, err
	end
end

function Client:editGuildApplicationCommand(guild_id, id, payload)
	local data, err = self._api:editGuildApplicationCommand(self:getApplicationInformation().id, guild_id, id, payload)

	if data then
		return ApplicationCommand(data, self)
	else
		return nil, err
	end
end

function Client:deleteGuildApplicationCommand(guild_id, id)
	local data, err = self._api:deleteGuildApplicationCommand(self:getApplicationInformation().id, guild_id, id)

	if data then
		return data
	else
		return nil, err
	end
end

function Client:getGuildApplicationCommandPermissions(guild_id)
	local data, err = self._api:getGuildApplicationCommandPermissions(self:getApplicationInformation().id, guild_id)

	if data then
		return data
	else
		return nil, err
	end
end

function Client:getApplicationCommandPermissions(guild_id, id)
	local data, err = self._api:getApplicationCommandPermissions(self:getApplicationInformation().id, guild_id, id)

	if data then
		return data
	else
		return nil, err
	end
end

function Client:editApplicationCommandPermissions(guild_id, id, payload)
	local data, err = self._api:editApplicationCommandPermissions(self:getApplicationInformation().id, guild_id, id, payload)

	if data then
		return data
	else
		return nil, err
	end
end

local function AugmentResolved(ia)
	local resolved = ia.data.resolved

	if not resolved then return end

	local guild = ia.guild
	local client = ia.client

	do
		local members = resolved.members

		if members then
			for k, v in pairs(members) do
				members[k] = guild:getMember(k)
			end
		end
	end

	do
		local channels = resolved.channels

		if channels then
			for k, v in pairs(channels) do
				channels[k] = guild:getChannel(k)
			end
		end
	end

	do
		local users = resolved.users

		if users then
			for k, v in pairs(users) do
				users[k] = client._users:_insert(v)
			end
		end
	end

	do
		local roles = resolved.roles

		if roles then
			for k, v in pairs(roles) do
				roles[k] = guild._roles:_insert(v)
			end
		end
	end
end

local subCommandOptionType = discordia.enums.appCommandOptionType.subCommand
local subCommandGroupOptionType = discordia.enums.appCommandOptionType.subCommandGroup
local userOptionType = discordia.enums.appCommandOptionType.user
local channelOptionType = discordia.enums.appCommandOptionType.channel
local roleOptionType = discordia.enums.appCommandOptionType.role
local mentionableOptionType = discordia.enums.appCommandOptionType.mentionable
local attachmentOptionType = discordia.enums.appCommandOptionType.attachment

local function ParseOptions(options, resolved)
	local parsed_options = {}

	for k, v in ipairs(options) do
		local type = v.type
		local name = v.name
		local value = v.value

		if type == subCommandOptionType or type == subCommandGroupOptionType then
			parsed_options[name] = ParseOptions(v.options)
		elseif type == userOptionType then
			parsed_options[name] = resolved.members[value]
		elseif type == channelOptionType then
			parsed_options[name] = resolved.channels[value]
		elseif type == roleOptionType then
			parsed_options[name] = resolved.roles[value]
		elseif type == mentionableOptionType then
			parsed_options[name] = resolved.members[value] or resolved.roles[value]
		elseif type == attachmentOptionType then
			parsed_options[name] = resolved.attachments[value]
		else
			parsed_options[name] = v.value
		end
	end

	return parsed_options
end

local function FindFocused(options)
	local focused = {}
	local focused_object

	for k, v in ipairs(options) do
		local type = v.type
		local name = v.name

		if type == subCommandOptionType or type == subCommandGroupOptionType then
			focused[name], focused_object = FindFocused(v.options)

			if focused_object then
				break
			end 
		elseif v.focused then
			-- Autocomplete is made only for primitive types, so we just use v.value
			focused[name] = v.value
			focused_object = v
			break
		end
	end

	return focused, focused_object
end

do
	local chatInputType = discordia.enums.appCommandType.chatInput
	local userType = discordia.enums.appCommandType.user
	local messageType = discordia.enums.appCommandType.message

	local function AugmentInteractionData(ia)
		local data = ia.data

		AugmentResolved(ia)

		if data.type == chatInputType then
			data.parsed_options = ParseOptions(data.options, data.resolved)

		elseif data.type == messageType then

		end

		return data
	end

	local applicationCommandType = discordia.enums.interactionType.applicationCommand
	local autocompleteType = discordia.enums.interactionType.applicationCommandAutocomplete

	function Client:useSlashCommands()
		self:on("interactionCreate", function(ia)
			if ia.type == applicationCommandType then
				local data = AugmentInteractionData(ia)

				ia.client:emit("applicationCommand", ia, data, data.parsed_options)
			elseif ia.type == autocompleteType then
				local data = AugmentInteractionData(ia)
				data.focused, data.focused_option = FindFocused(data.options)

				ia.client:emit("applicationAutocomplete", ia, data, data.focused, data.parsed_options)
			end
		end)
	end
end

return Client