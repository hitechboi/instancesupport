# ChildVm
ChildVm emulates the functions cheeto does not support by using a polling engine built on `GetChildren` and `Address`

---

## loading

```lua
local _cvUrl = "https://raw.githubusercontent.com/hitechboi/checkitv2/refs/heads/main/ChildVm.lua?t=" .. tostring(os.time())
local _ok = pcall(function() loadstring(game:HttpGet(_cvUrl))() end)
if _ok then
    local _t0 = os.clock()
    repeat task.wait(0.05) until _G.ChildVm or (os.clock() - _t0) > 12
end

local CV = _G.ChildVm
```

---

## stuff

### OnChildAdded
Fires when a new child is added to a parent.
```lua
CV:OnChildAdded(parent, function(child)
    print("added:", child.Name)
end)
```

### OnChildRemoved
Fires when a child is removed from a parent. Requires 2 consecutive missing polls before firing to prevent false positives.
```lua
CV:OnChildRemoved(parent, function(child)
    print("removed:", child.Name)
end)
```

### OnceChildAdded / OnceChildRemoved
Same as above but automatically disconnects after the first fire.
```lua
CV:OnceChildAdded(parent, function(child)
    print("first child added:", child.Name)
end)
```

### OnDescendantAdded
Recursively watches all children and their children for additions.
```lua
CV:OnDescendantAdded(workspace, function(child)
    print("descendant added:", child.Name)
end)
```

### OnDescendantRemoved
Recursively watches all children and their children for removals.
```lua
CV:OnDescendantRemoved(workspace, function(child)
    print("descendant removed:", child.Name)
end)
```

### OnPropertyChanged
Fires when a readable property on an instance changes. Handles Vector3 and Vector2 comparisons with a 0.001 threshold to avoid float noise.
```lua
CV:OnPropertyChanged(player, "Team", function(new, old)
    print("team changed:", old and old.Name, "->", new and new.Name)
end)
```

### OncePropertyChanged
Same as above but disconnects after the first fire.

### OnAttributeChanged
Fires when a specific attribute on an instance changes.
```lua
CV:OnAttributeChanged(tool, "FireRate", function(new, old)
    print("fire rate:", old, "->", new)
end)
```

### OnceAttributeChanged
Same as above but disconnects after the first fire.

### OnChanged
Watches multiple properties at once. Automatically routes `CFrame` to `OnCFrameChanged` and `Size` to `OnSizeChanged` via memory when available.
```lua
CV:OnChanged(part, function(prop, new, old)
    print(prop, "changed")
end, { "CFrame", "Size", "Name" })
```

### OnCFrameChanged
Watches position and rotation via memory reads. Fires when either changes beyond the threshold.
```lua
CV:OnCFrameChanged(hrp, function(new, old)
    print("moved to", new.X, new.Y, new.Z)
end)
```
The callback receives a table with `X`, `Y`, `Z` and rotation matrix values `r00`–`r22`.

### OnSizeChanged
Watches size via memory reads. Fires when X, Y, or Z changes beyond the threshold.
```lua
CV:OnSizeChanged(part, function(new, old)
    print("size:", old.X, old.Y, old.Z, "->", new.X, new.Y, new.Z)
end)
```

### WaitForChild
Yields until a named child appears in a parent or the timeout is reached. Returns the child or nil on timeout.
```lua
local part = CV:WaitForChild(workspace, "MyPart", 10)
if part then
    print("found:", part.Name)
end
```

---

## Signal

A standalone event emitter included.

```lua
local sig = CV.Signal.new()

local conn = sig:Connect(function(value)
    print("received:", value)
end)

sig:Once(function(value)
    print("received once:", value)
end)

sig:Fire("hello")

sig:Wait() -- yields until fired

sig:GetConnectionCount() -- number of active connections

sig:DisconnectAll()

conn:Disconnect()
print(conn.Connected) -- false
```

---

## Connection

Every watcher and signal connection returns a Connection object.

```lua
local conn = CV:OnChildAdded(workspace, function(child) end)

print(conn.Connected) -- true
conn:Disconnect()
print(conn.Connected) -- false
```

---

## Utility

```lua
CV:SetPollRate(0.05)   -- how often all watchers check for changes (seconds)
CV:GetPollRate()       -- returns current poll rate
CV:GetWatcherCount()   -- returns number of active watchers
CV:Destroy()           -- stops the engine and clears all watchers
```

---

## How it works

ChildVm runs a single `task.spawn` loop at the configured poll rate. Every tick it snapshots the children of each watched parent using `GetChildren` and compares against the previous snapshot using `Address` as a stable key. Differences fire the registered callbacks.

`OnCFrameChanged` and `OnSizeChanged` bypass Matcha's property restrictions entirely by reading directly from memory using the instance's `Address` and known offsets.

- CFrame offset: `instance.Address + 0x148 -> prim + 0xC0`
- Size offset: `instance.Address + 0x148 -> prim + 0x50 -> + 0x20`

---

## listen brobro

- All callbacks are wrapped in `pcall` so errors won't break the engine
- `OnChildRemoved` requires 2 consecutive missing polls to fire, preventing false removals from momentary snapshot gaps

---

*love... osamason*
