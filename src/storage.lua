local json = require("json")
local process = {
	_version = "0.0.0",
	proxy = nil,
	state = {},
}

function process.createResult(partialResult)
	return {
		Output = partialResult.Output or {},
		Messages = partialResult.Messages or {},
		Spawns = partialResult.Spawns or {},
		Assignments = partialResult.Assignments or {},
		Error = partialResult.Error or nil,
	}
end

function process.stdin(msg, env)
	local proxyMsg = {
		Data = json.encode({ msg = msg, env = env, state = process.state }),
		Target = process.proxy,
	}
	return process.createResult({
		Messages = { proxyMsg },
	})
end

function process.stdout(msg)
	local results = json.decode(msg.Data)

	if results.state then
		process.state = results.state
	end

	return process.createResult(results)
end
function process.handle(msg, ao)
	local env
	if ao.Process then
		env = ao
	else
		env = ao.env
	end
	process.state.Owner = process.state.Owner or ao.env.Process.Owner

	local function throw(errorString)
		return process.createResult({
			Error = errorString,
		})
	end

	for _, tag in ipairs(env.Process.Tags) do
		if tag.name == "Proxy" then
			process.proxy = process.proxy or tag.value
			break
		end
	end

	local from = ""
	local newProxy = nil
	for _, tag in ipairs(msg.Tags) do
		if tag.name == "From" then
			from = tag.value
		end
		if tag.name == "Proxy-Update" then
			newProxy = tag.value
		end
	end
	if newProxy and from ~= process.proxy and from ~= process.state.Owner then
		return throw("Only the owner or proxy can update the proxy")
	end

	if from == process.proxy then
		return process.stdout(msg)
	else
		return process.stdin(msg, env)
	end
end

return process
