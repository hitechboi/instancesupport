local Connection = {}
Connection.__index = Connection

function Connection.new(disconnectFn)
    return setmetatable({
        Connected = true,
        _disconnect = disconnectFn,
    }, Connection)
end

function Connection:Disconnect()
    if not self.Connected then return end
    self.Connected = false
    if self._disconnect then
        self._disconnect()
    end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({
        _entries = {},
    }, Signal)
end

function Signal:Connect(callback)
    local entry = { callback = callback, connected = true }
    table.insert(self._entries, entry)
    return Connection.new(function()
        entry.connected = false
    end)
end

function Signal:Once(callback)
    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        callback(...)
    end)
    return conn
end

function Signal:Fire(...)
    local alive = {}
    for _, entry in ipairs(self._entries) do
        if entry.connected then
            table.insert(alive, entry)
            pcall(entry.callback, ...)
        end
    end
    self._entries = alive
end

function Signal:Wait()
    local co = coroutine.running()
    self:Once(function(...)
        coroutine.resume(co, ...)
    end)
    return coroutine.yield()
end

function Signal:DisconnectAll()
    for _, entry in ipairs(self._entries) do
        entry.connected = false
    end
    self._entries = {}
end

function Signal:GetConnectionCount()
    local n = 0
    for _, entry in ipairs(self._entries) do
        if entry.connected then n = n + 1 end
    end
    return n
end

local ChildVm = {}
ChildVm.__index = ChildVm
ChildVm.Signal = Signal
ChildVm.Connection = Connection
ChildVm._VERSION = "1.0.0"

function ChildVm.new(config)
    config = config or {}
    local self = setmetatable({
        _watchers = {},
        _running = false,
        _pollRate = config.PollRate or 0.05,
    }, ChildVm)
    self:_startEngine()
    return self
end

function ChildVm:_startEngine()
    if self._running then return end
    self._running = true
    task.spawn(function()
        while self._running do
            local watchers = self._watchers
            local alive = {}
            for i = 1, #watchers do
                local w = watchers[i]
                if w.active then
                    table.insert(alive, w)
                    pcall(w.poll)
                end
            end
            self._watchers = alive
            task.wait(self._pollRate)
        end
    end)
end

local function snapshotChildren(parent)
    local set = {}
    pcall(function()
        for _, child in ipairs(parent:GetChildren()) do
            local addr = child.Address
            if addr then
                set[addr] = child
            end
        end
    end)
    return set
end

function ChildVm:OnChildAdded(parent, callback)
    local current = snapshotChildren(parent)
    local pending = {}
    local watcher = {
        active = true,
        poll = function()
            if not parent or not parent.Parent then return end
            local now = snapshotChildren(parent)
            for addr, child in pairs(now) do
                if not current[addr] then
                    if not pending[addr] then
                        pending[addr] = true
                        pcall(callback, child)
                    end
                else
                    pending[addr] = nil
                end
            end
            current = now
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:OnceChildAdded(parent, callback)
    local conn
    conn = self:OnChildAdded(parent, function(child)
        conn:Disconnect()
        callback(child)
    end)
    return conn
end

function ChildVm:OnChildRemoved(parent, callback)
    local current = snapshotChildren(parent)
    local missingFor = {}
    local watcher = {
        active = true,
        poll = function()
            if not parent or not parent.Parent then return end
            local now = snapshotChildren(parent)
            for addr, child in pairs(current) do
                if not now[addr] then
                    missingFor[addr] = (missingFor[addr] or 0) + 1
                    if missingFor[addr] >= 2 then
                        missingFor[addr] = nil
                        current[addr] = nil
                        pcall(callback, child)
                    end
                else
                    missingFor[addr] = nil
                end
            end
            for addr, child in pairs(now) do
                if not current[addr] then
                    current[addr] = child
                end
            end
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:OnceChildRemoved(parent, callback)
    local conn
    conn = self:OnChildRemoved(parent, function(child)
        conn:Disconnect()
        callback(child)
    end)
    return conn
end

function ChildVm:OnAttributeChanged(instance, attrName, callback)
    local currentValue = nil
    pcall(function()
        currentValue = instance:GetAttribute(attrName)
    end)
    local watcher = {
        active = true,
        poll = function()
            if not instance or not instance.Parent then return end
            local newValue = nil
            pcall(function()
                newValue = instance:GetAttribute(attrName)
            end)
            if newValue ~= currentValue then
                local old = currentValue
                currentValue = newValue
                pcall(callback, newValue, old)
            end
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:OnceAttributeChanged(instance, attrName, callback)
    local conn
    conn = self:OnAttributeChanged(instance, attrName, function(new, old)
        conn:Disconnect()
        callback(new, old)
    end)
    return conn
end

local function valuesEqual(a, b)
    if typeof(a) ~= typeof(b) then return false end
    local t = typeof(a)
    if t == "Vector3" then
        local eq = false
        pcall(function()
            local dx = math.abs(b.X - a.X)
            local dy = math.abs(b.Y - a.Y)
            local dz = math.abs(b.Z - a.Z)
            eq = dx < 0.001 and dy < 0.001 and dz < 0.001
        end)
        return eq
    end
    if t == "Vector2" then
        local eq = false
        pcall(function()
            local dx = math.abs(b.X - a.X)
            local dy = math.abs(b.Y - a.Y)
            eq = dx < 0.001 and dy < 0.001
        end)
        return eq
    end
    if t == "table" then
        if a.X and a.Y and a.Z then
            return math.abs(b.X - a.X) < 0.001
                and math.abs(b.Y - a.Y) < 0.001
                and math.abs(b.Z - a.Z) < 0.001
        end
    end
    return a == b
end

function ChildVm:OnPropertyChanged(instance, propName, callback)
    local currentValue = nil
    pcall(function()
        currentValue = instance[propName]
    end)
    local watcher = {
        active = true,
        poll = function()
            if not instance or not instance.Parent then return end
            local newValue = nil
            local ok = pcall(function()
                newValue = instance[propName]
            end)
            if not ok then return end
            if not valuesEqual(currentValue, newValue) then
                local old = currentValue
                currentValue = newValue
                pcall(callback, newValue, old)
            end
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:OncePropertyChanged(instance, propName, callback)
    local conn
    conn = self:OnPropertyChanged(instance, propName, function(new, old)
        conn:Disconnect()
        callback(new, old)
    end)
    return conn
end

function ChildVm:OnChanged(instance, callback, properties)
    properties = properties or {
        "Name", "Parent", "Visible", "Text", "Value",
        "Position", "Size", "Health", "MaxHealth",
        "WalkSpeed", "Transparency", "Enabled", "Anchored",
        "CFrame",
    }
    local conns = {}
    for _, prop in ipairs(properties) do
        if prop == "CFrame" then
            local ok = pcall(function() memory_read("uintptr_t", instance.Address + 0x148) end)
            if ok then
                local c = self:OnCFrameChanged(instance, function(new, old)
                    pcall(callback, "CFrame", new, old)
                end)
                table.insert(conns, c)
            end
        elseif prop == "Size" then
            local ok = pcall(function() memory_read("uintptr_t", instance.Address + 0x148) end)
            if ok then
                local c = self:OnSizeChanged(instance, function(new, old)
                    pcall(callback, "Size", new, old)
                end)
                table.insert(conns, c)
            end
        else
            local readable = pcall(function() local _ = instance[prop] end)
            if readable then
                local c = self:OnPropertyChanged(instance, prop, function(new, old)
                    pcall(callback, prop, new, old)
                end)
                table.insert(conns, c)
            end
        end
    end
    return Connection.new(function()
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
    end)
end

function ChildVm:OnDescendantAdded(ancestor, callback)
    local conns = {}
    local function watchNode(parent)
        local c = self:OnChildAdded(parent, function(child)
            pcall(callback, child)
            watchNode(child)
        end)
        table.insert(conns, c)
    end
    watchNode(ancestor)
    pcall(function()
        local function walkExisting(parent)
            for _, child in ipairs(parent:GetChildren()) do
                watchNode(child)
                walkExisting(child)
            end
        end
        walkExisting(ancestor)
    end)
    return Connection.new(function()
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
    end)
end

function ChildVm:OnDescendantRemoved(ancestor, callback)
    local conns = {}
    local function watchNode(parent)
        local c = self:OnChildRemoved(parent, function(child)
            pcall(callback, child)
        end)
        table.insert(conns, c)
    end
    watchNode(ancestor)
    pcall(function()
        local function walkExisting(parent)
            for _, child in ipairs(parent:GetChildren()) do
                watchNode(child)
                walkExisting(child)
            end
        end
        walkExisting(ancestor)
    end)
    return Connection.new(function()
        for _, c in ipairs(conns) do
            c:Disconnect()
        end
    end)
end

function ChildVm:WaitForChild(parent, childName, timeout)
    timeout = timeout or 10
    local existing = nil
    pcall(function()
        existing = parent:FindFirstChild(childName)
    end)
    if existing then return existing end
    local result = nil
    local done = false
    local conn = self:OnChildAdded(parent, function(child)
        pcall(function()
            if child.Name == childName then
                result = child
                done = true
            end
        end)
    end)
    local start = tick()
    while not done and (tick() - start) < timeout do
        task.wait(self._pollRate)
    end
    conn:Disconnect()
    return result
end

function ChildVm:OnCFrameChanged(instance, callback, threshold)
    threshold = threshold or 0.001
    local function readCFrame()
        local result = nil
        pcall(function()
            local prim = memory_read("uintptr_t", instance.Address + 0x148)
            local cf_base = prim + 0xC0
            result = {
                X   = memory_read("float", cf_base + 36),
                Y   = memory_read("float", cf_base + 40),
                Z   = memory_read("float", cf_base + 44),
                r00 = memory_read("float", cf_base),
                r01 = memory_read("float", cf_base + 4),
                r02 = memory_read("float", cf_base + 8),
                r10 = memory_read("float", cf_base + 12),
                r11 = memory_read("float", cf_base + 16),
                r12 = memory_read("float", cf_base + 20),
                r20 = memory_read("float", cf_base + 24),
                r21 = memory_read("float", cf_base + 28),
                r22 = memory_read("float", cf_base + 32),
            }
        end)
        return result
    end

    local current = readCFrame()
    local watcher = {
        active = true,
        poll = function()
            if not instance or not instance.Parent then return end
            local new = readCFrame()
            if not new or not current then current = new return end
            local dx = math.abs(new.X - current.X)
            local dy = math.abs(new.Y - current.Y)
            local dz = math.abs(new.Z - current.Z)
            local rotChanged = math.abs(new.r00 - current.r00) > threshold
                or math.abs(new.r11 - current.r11) > threshold
                or math.abs(new.r22 - current.r22) > threshold
            if dx > threshold or dy > threshold or dz > threshold or rotChanged then
                local old = current
                current = new
                pcall(callback, new, old)
            end
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:OnSizeChanged(instance, callback, threshold)
    threshold = threshold or 0.001
    local function readSize()
        local result = nil
        pcall(function()
            local prim = memory_read("uintptr_t", instance.Address + 0x148)
            local sizePtr = memory_read("uintptr_t", prim + 0x50)
            result = {
                X = memory_read("float", sizePtr + 0x20),
                Y = memory_read("float", sizePtr + 0x24),
                Z = memory_read("float", sizePtr + 0x28),
            }
        end)
        return result
    end

    local current = readSize()
    local watcher = {
        active = true,
        poll = function()
            if not instance or not instance.Parent then return end
            local new = readSize()
            if not new or not current then current = new return end
            local dx = math.abs(new.X - current.X)
            local dy = math.abs(new.Y - current.Y)
            local dz = math.abs(new.Z - current.Z)
            if dx > threshold or dy > threshold or dz > threshold then
                local old = current
                current = new
                pcall(callback, new, old)
            end
        end,
    }
    table.insert(self._watchers, watcher)
    return Connection.new(function()
        watcher.active = false
    end)
end

function ChildVm:SetPollRate(rate)
    self._pollRate = math.max(0.01, rate)
end

function ChildVm:GetPollRate()
    return self._pollRate
end

function ChildVm:GetWatcherCount()
    local n = 0
    for _, w in ipairs(self._watchers) do
        if w.active then n = n + 1 end
    end
    return n
end

function ChildVm:Destroy()
    self._running = false
    for _, w in ipairs(self._watchers) do
        w.active = false
    end
    self._watchers = {}
end

local singleton = ChildVm.new()
singleton.new = ChildVm.new
_G.ChildVm = singleton
return singleton