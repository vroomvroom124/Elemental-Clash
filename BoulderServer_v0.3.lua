-- Elemental Clash: authoritative Earth Floating Boulder prototype.
-- Place in ServerScriptService. Requires BoulderConfig and BoulderRemote in ReplicatedStorage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("BoulderConfig"))
local Remote = ReplicatedStorage:WaitForChild("BoulderRemote")
local AnimRemote = ReplicatedStorage:WaitForChild("CombatAnimationRemote")

local folder = Workspace:FindFirstChild("ElementalClashProjectiles")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "ElementalClashProjectiles"
    folder.Parent = Workspace
end

local active = {}   -- [Player] = server-owned boulder state
local cooldowns = {} -- [Player] = time when another boulder can start

local function validDirection(value)
    if typeof(value) ~= "Vector3" then return nil end
    for _, n in ipairs({value.X, value.Y, value.Z}) do
        if n ~= n or math.abs(n) > 1000 then return nil end
    end
    local length = value.Magnitude
    if length < 0.9 or length > 1.1 then return nil end
    return value.Unit
end

local function livingRoot(player)
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return nil end
    return root
end

local function makeBoulder()
    local ball = Instance.new("Part")
    ball.Name = "EarthBoulder"
    ball.Shape = Enum.PartType.Ball
    ball.Size = Vector3.new(Config.BoulderRadius * 2, Config.BoulderRadius * 2, Config.BoulderRadius * 2)
    ball.Material = Enum.Material.Slate
    ball.Color = Color3.fromRGB(119, 105, 87)
    ball.Anchored = true
    ball.CanCollide = false
    ball.CanTouch = false
    ball.CanQuery = false
    ball.CastShadow = true

    local upper = Instance.new("Attachment")
    upper.Position = Vector3.new(0, Config.BoulderRadius * 0.7, 0)
    upper.Parent = ball
    local lower = Instance.new("Attachment")
    lower.Position = Vector3.new(0, -Config.BoulderRadius * 0.7, 0)
    lower.Parent = ball

    local trail = Instance.new("Trail")
    trail.Attachment0 = upper
    trail.Attachment1 = lower
    trail.Lifetime = 0.22
    trail.MinLength = 0.3
    trail.Color = ColorSequence.new(Color3.fromRGB(175, 137, 91), Color3.fromRGB(101, 82, 64))
    trail.Transparency = NumberSequence.new(0.25, 1)
    trail.Enabled = false
    trail.Parent = ball

    ball.Parent = folder
    return ball, trail
end

local function clearBoulder(player, status)
    local state = active[player]
    if not state then return end
    active[player] = nil
    player:SetAttribute("EC_HoldingBoulder", false)
    if player.Parent == Players then AnimRemote:FireAllClients(player, "BoulderEnd") end
    if state.part then state.part:Destroy() end
    if status and player.Parent == Players then
        Remote:FireClient(player, status)
    end
end

local function startCooldown(player)
    cooldowns[player] = os.clock() + Config.Cooldown
end

local function paramsFor(player)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {player.Character, folder}
    params.IgnoreWater = true
    return params
end

local function heldPosition(root, state, player)
    local origin = root.Position + Vector3.new(0, Config.HoldHeight, 0)
    local desired = origin + state.aim * Config.HoldDistance
    -- Prevent the hovering rock from penetrating a wall directly ahead.
    local hit = Workspace:Raycast(origin, desired - origin, paramsFor(player))
    if hit then
        desired = origin + state.aim * math.max(2.2, hit.Distance - Config.BoulderRadius)
    end
    return desired
end

local function impact(player, state, raycastResult)
    local model = raycastResult.Instance:FindFirstAncestorOfClass("Model")
    if model then
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 and model ~= player.Character then
            local damage = Config.BaseDamage + Config.BonusDamage * state.charge
            humanoid:TakeDamage(damage)
            Remote:FireClient(player, "Hit", math.floor(damage + 0.5))
        end
    end
    clearBoulder(player, "Ended")
end

Remote.OnServerEvent:Connect(function(player, action, payload)
    if type(action) ~= "string" then return end
    local now = os.clock()
    local state = active[player]

    if action == "Begin" then
        local aim = validDirection(payload)
        if not aim or not livingRoot(player) then return end
        if state then
            Remote:FireClient(player, "Denied", 0, "A boulder is already active")
            return
        end
        local timeLeft = (cooldowns[player] or 0) - now
        if timeLeft > 0 then
            Remote:FireClient(player, "Denied", timeLeft, "Boulder cooling down")
            return
        end

        local root = livingRoot(player)
        if not root then return end
        local ball, trail = makeBoulder()
        state = {
            phase = "Held",
            part = ball,
            trail = trail,
            aim = aim,
            direction = aim,
            charge = 0,
            charging = false,
            started = now,
            lastAim = 0,
            flightTime = 0,
            distance = 0,
            controlled = true,
            launched = false,
            speed = 0,
        }
        active[player] = state
        player:SetAttribute("EC_HoldingBoulder", true)
        ball.Position = heldPosition(root, state, player)
        Remote:FireClient(player, "Started")
        AnimRemote:FireAllClients(player, "BoulderStart")
        return
    end

    if not state then return end

    if action == "Aim" then
        local aim = validDirection(payload)
        if not aim or now - state.lastAim < 1 / (Config.AimUpdatesPerSecond + 5) then return end
        state.lastAim = now
        if state.phase == "Held" or (state.phase == "Flying" and state.controlled) then
            state.aim = aim
        end
    elseif action == "Charge" then
        if state.phase == "Held" and type(payload) == "boolean" then
            state.charging = payload
        end
    elseif action == "Launch" then
        local aim = validDirection(payload)
        if state.phase ~= "Held" or not aim then return end
        state.phase = "Flying"
        player:SetAttribute("EC_HoldingBoulder", false)
        state.launched = true
        state.aim = aim
        state.direction = aim
        state.speed = Config.BaseSpeed + Config.BonusSpeed * state.charge
        state.trail.Enabled = true
        startCooldown(player)
        Remote:FireClient(player, "Launched", state.charge)
        AnimRemote:FireAllClients(player, "BoulderLaunch")
    elseif action == "StopControl" then
        if state.phase == "Held" then
            startCooldown(player)
            clearBoulder(player, "Ended")
        elseif state.phase == "Flying" then
            state.controlled = false
        end
    elseif action == "Cancel" then
        if state.phase == "Held" then
            startCooldown(player)
            clearBoulder(player, "Ended")
        elseif state.phase == "Flying" then
            state.controlled = false
        end
    end
end)

RunService.Heartbeat:Connect(function(dt)
    local step = math.min(dt, 0.06)
    for player, state in pairs(active) do
        local root = livingRoot(player)
        if not root or not state.part or not state.part.Parent then
            clearBoulder(player, "Ended")
            continue
        end

        if state.phase == "Held" then
            if os.clock() - state.started > Config.MaxHoldTime then
                startCooldown(player)
                clearBoulder(player, "Ended")
                continue
            end
            if state.charging then
                state.charge = math.min(1, state.charge + step / Config.MaxChargeTime)
            end
            local target = heldPosition(root, state, player)
            state.part.Position = state.part.Position:Lerp(target, math.min(1, step * 16))
            -- Slightly increase the apparent size as the rock charges.
            local radius = Config.BoulderRadius * (1 + state.charge * 0.18)
            state.part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
        elseif state.phase == "Flying" then
            state.flightTime += step
            if state.flightTime > Config.ProjectileLifetime or state.distance > Config.MaxTravelDistance then
                clearBoulder(player, "Ended")
                continue
            end
            if state.controlled and state.flightTime <= Config.SteeringTime then
                local blend = math.min(1, Config.SteeringResponsiveness * step)
                local newDirection = state.direction:Lerp(state.aim, blend)
                if newDirection.Magnitude > 0.001 then
                    state.direction = newDirection.Unit
                end
            else
                state.controlled = false
            end
            local travel = state.direction * state.speed * step
            local from = state.part.Position
            local hit = Workspace:Spherecast(from, Config.BoulderRadius * (1 + state.charge * 0.18), travel, paramsFor(player))
            if hit then
                impact(player, state, hit)
            else
                state.part.Position = from + travel
                state.distance += travel.Magnitude
            end
        end
    end
end)

local function connectPlayer(player)
    player.CharacterRemoving:Connect(function()
        clearBoulder(player, "Ended")
    end)
end

Players.PlayerAdded:Connect(connectPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    connectPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
    clearBoulder(player)
    cooldowns[player] = nil
end)
