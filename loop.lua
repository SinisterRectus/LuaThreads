local loop = {}
local threads = {}

local Thread = {}
Thread.__index = Thread

function Thread:sleep(delay)
	self:stop()
	loop.setTimeout(delay, function()
		self:start()
	end)
end

function Thread:start()
	self.active = true
end

function Thread:stop()
	self.active = false
end

function Thread:clear()
	threads[self.coro] = nil
end

function Thread:isActive()
	return self.active == true
end

-- constructs and registers a new loop thread
local function newThread(f)
	local thread = setmetatable({
		coro = coroutine.create(f)
	}, Thread)
	threads[thread.coro] = thread
	return thread
end

-- returns the current process time in milliseconds
local function getTime()
	return os.clock() * 1000
end

-- runs one loop cycle
-- returns true if there are still active threads
function loop.runOnce()
	local running = false
	for coro, thread in pairs(threads) do
		local status = coroutine.status(coro)
		if status == 'suspended' then
			running = true
			if thread:isActive() then
				assert(coroutine.resume(coro))
			end
		elseif status == 'dead' then
			threads[coro] = nil
		end
	end
	return running
end

-- runs the loop until there are no more active threads
function loop.runUntilComplete()
	local run = loop.runOnce
	repeat until not run()
end

-- runs the loop forever, regardless of thread activity
function loop.runForever()
	local run = loop.runOnce
	while true do run() end
end

-- returns the currently running thread, if one exists
function loop.getThread(coro)
	return threads[coro or coroutine.running()]
end

-- asynchronously sleeps the currently running thread
function loop.sleep(delay)
	local thread = loop.getThread()
	assert(thread, 'cannot aync sleep outside of a loop thread')
	thread:sleep(delay)
	coroutine.yield()
end

-- synchronously sleeps the entire process
function loop.sleepSync(delay)
	local t = getTime()
	while delay > getTime() - t do end
end

-- schedules a callback for the next loop tick
function loop.setImmediate(callback)
	local thread = newThread(function()
		callback()
		coroutine.yield()
	end)
	thread:start()
	return thread
end

-- schedules a callback for every loop tick
function loop.setTick(callback)
	local thread = newThread(function()
		while true do
			callback()
			coroutine.yield()
		end
	end)
	thread:start()
	return thread
end

-- schedules a callback to be called after every n milliseconds
function loop.setInterval(delay, callback)
	local thread = newThread(function()
		local t = getTime()
		while true do
			local current = getTime()
			local dt = current - t
			if dt >= delay then
				t = current
				callback()
			end
			coroutine.yield()
		end
	end)
	thread:start()
	return thread
end

-- schedules a callback to be called once after x milliseconds
function loop.setTimeout(delay, callback)
	local thread = newThread(function()
		local t = getTime()
		while true do
			local current = getTime()
			local dt = current - t
			if dt >= delay then
				return callback()
			end
			coroutine.yield()
		end
	end)
	thread:start()
	return thread
end

-- asynchronously reads from a stream according to the buffer size
function loop.read(stream, bufferSize, callback)
	local thread = newThread(function()
		while true do
			local chunk = stream:read(bufferSize)
			if not chunk then return end
			callback(chunk)
			coroutine.yield()
		end
	end)
	thread:start()
	return thread
end

-- asynchronously writes to a stream according to the buffer size
function loop.write(stream, bufferSize, str)
	local n = #str
	bufferSize = bufferSize or n
	if n < bufferSize then
		stream:write(str)
	else
		local thread = newThread(function()
			for word in str:gmatch(string.rep('.', bufferSize)) do
				stream:write(word)
				n = n - bufferSize
				coroutine.yield()
			end
			if n > 0 then stream:write(str:sub(-n)) end
		end)
		thread:start()
		return thread
	end
end

-- asynchronously reads lines from a stream
function loop.lines(stream, callback)
	local thread = newThread(function()
		for line in stream:lines() do
			callback(line)
			coroutine.yield()
		end
	end)
	thread:start()
	return thread
end

return loop
