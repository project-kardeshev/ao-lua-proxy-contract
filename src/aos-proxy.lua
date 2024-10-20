local json = require("json")
StorageProcess = ao.env.Process.Tags.StorageProcess or "INSERT_STORAGE_PROCESS_ID"

function camelCase(str)
	-- Remove any leading or trailing spaces
	str = string.gsub(str, "^%s*(.-)%s*$", "%1")

	-- Convert PascalCase to camelCase
	str = string.gsub(str, "^%u", string.lower)

	-- Handle kebab-case, snake_case, and space-separated words
	str = string.gsub(str, "[-_%s](%w)", function(s)
		return string.upper(s)
	end)

	return str
end
function errorHandler(err)
	return debug.traceback(err)
end

function normalizeProxyMessage(msg)
	local proxiedMsg = ao.normalize(json.decode(msg.Data).msg)
	proxiedMsg.TagArray = proxiedMsg.Tags
	proxiedMsg.Tags = Tab(proxiedMsg)
	return proxiedMsg
end
function createProxyHandler(tagName, tagValue, handler, position)
	assert(type(position) == "string" or type(position) == "nil", errorHandler("Position must be a string or nil"))
	assert(
		position == nil or position == "add" or position == "prepend" or position == "append",
		"Position must be one of 'add', 'prepend', 'append'"
	)
	return Handlers[position or "add"](
		camelCase(tagValue),
		Handlers.utils.continue(function(msg)
			if msg.From == StorageProcess then
				local proxiedMsg = normalizeProxyMessage(msg)
				return Handlers.utils.hasMatchingTag(tagName, tagValue)(proxiedMsg)
			else
				errorHandler("Only the storage process can send messages for this proxy")
			end
		end),
		function(msg)
			local proxiedMsg = normalizeProxyMessage(msg)
			ao.init(json.decode(msg.Data).env)

			print("Handling Action [" .. proxiedMsg.Id .. "]: " .. tagValue)
			local handlerStatus, handlerRes = xpcall(function()
				handler(proxiedMsg)
			end, errorHandler)

			if not handlerStatus then
				ao.send({
					Target = msg.From,
					Action = "Invalid-" .. tagValue .. "-Notice",
					Error = tagValue .. "-Error",
					["Message-Id"] = msg.Id,
					Data = handlerRes,
				})
			end

			return handlerRes
		end
	)
end

Handlers.append("forwardProxyResults", function(msg)
	return true
end, function(msg)
	-- might have ao.outbox.state in it which will update storage process state
	local results = json.encode(ao.outbox)
	ao.clearOutbox()
	ao.send({
		Target = StorageProcess,
		Data = results,
	})
end)
