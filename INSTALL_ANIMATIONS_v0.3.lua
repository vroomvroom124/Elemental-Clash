-- Elemental Clash v0.3 COMBAT ANIMATION UPGRADE.
-- Paste into Roblox Studio Command Bar (Edit mode) after installing v0.2.
-- v0.3 upgrades two existing server scripts to broadcast validated moves;
-- installs one new animation LocalScript. Existing camera/input, combat tuning,
-- boulder client, arena and HUD stay intact.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local scripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local combat = SSS:FindFirstChild("CombatServer")
local boulder = SSS:FindFirstChild("BoulderServer")
if not combat or not boulder or not RS:FindFirstChild("CombatRemote") or not RS:FindFirstChild("BoulderRemote") then
    error("Elemental Clash v0.2 is required. Install v0.1, then v0.2, before applying v0.3.")
end
assert(combat:IsA("Script") and boulder:IsA("Script"), "CombatServer/BoulderServer must be scripts")
local backup = SSS:FindFirstChild("ElementalClashBackups")
if not backup then
    backup = Instance.new("Folder")
    backup.Name = "ElementalClashBackups"
    backup.Parent = SSS
end
local function backupOnce(name, original)
    local item = backup:FindFirstChild(name)
    if not item then
        item = Instance.new("StringValue")
        item.Name = name
        item.Value = original.Source
        item.Parent = backup
    end
end
backupOnce("CombatServer_v0.2_Source", combat)
backupOnce("BoulderServer_v0.2_Source", boulder)
local remote = RS:FindFirstChild("CombatAnimationRemote")
if remote and not remote:IsA("RemoteEvent") then error("CombatAnimationRemote has the wrong class") end
if not remote then
    remote = Instance.new("RemoteEvent")
    remote.Name = "CombatAnimationRemote"
    remote.Parent = RS
end
combat.Source = [====[
-- Elemental Clash v0.2: server-authoritative melee, guard, parry and dodge.
-- This is a prototype. No animation asset IDs are required.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Remote = ReplicatedStorage:WaitForChild("CombatRemote")
local AnimRemote = ReplicatedStorage:WaitForChild("CombatAnimationRemote")
local Config = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local stateByPlayer = {}

local function notify(player, kind, value)
    if player.Parent == Players then
        Remote:FireClient(player, kind, value)
    end
end

local function stateFor(player)
    local s = stateByPlayer[player]
    if not s then
        s = {nextAction = 0, lastLight = -100, combo = 0,
            blocking = false, blockSince = -100, guard = Config.GuardMax,
            lastGuardHit = -100, dodgeReady = 0, iframeUntil = 0,
            stunnedUntil = 0, serial = 0}
        stateByPlayer[player] = s
        player:SetAttribute("EC_Guard", Config.GuardMax)
    end
    return s
end

local function livingCharacter(player)
    local character = player.Character
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
    return character, hum, root
end

local function cantAct(player, s, now)
    return player:GetAttribute("EC_HoldingBoulder") == true
        or s.stunnedUntil > now
end

local function visual(center, wide, bright)
    local p = Instance.new("Part")
    p.Name = "EC_StrikeFX"
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(1.8, 1.8, 1.8)
    p.CFrame = CFrame.new(center)
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Material = Enum.Material.Neon
    p.Color = bright and Color3.fromRGB(255, 217, 125) or Color3.fromRGB(191, 158, 105)
    p.Transparency = 0.28
    p.Parent = Workspace
    TweenService:Create(p, TweenInfo.new(0.20), {Size = Vector3.new(wide, wide * 0.58, wide), Transparency = 1}):Play()
    Debris:AddItem(p, 0.24)
end

local function makeHitbox(attacker, root)
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = {attacker}
    local projectiles = Workspace:FindFirstChild("ElementalClashProjectiles")
    if projectiles then table.insert(ignored, projectiles) end
    overlap.FilterDescendantsInstances = ignored
    overlap.MaxParts = 100
    local cf = root.CFrame * CFrame.new(0, 0, -Config.HitboxForward)
    return Workspace:GetPartBoundsInBox(cf, Config.HitboxSize, overlap)
end

local function unobstructed(attacker, target, from, to)
    local ray = RaycastParams.new()
    ray.FilterType = Enum.RaycastFilterType.Exclude
    local projectileFolder = Workspace:FindFirstChild("ElementalClashProjectiles")
    local ignored = {attacker}
    if projectileFolder then table.insert(ignored, projectileFolder) end
    ray.FilterDescendantsInstances = ignored
    ray.IgnoreWater = true
    local hit = Workspace:Raycast(from, to - from, ray)
    return not hit or hit.Instance:IsDescendantOf(target)
end

local function setStunned(player, duration)
    local s = stateFor(player)
    s.stunnedUntil = math.max(s.stunnedUntil, os.clock() + duration)
    s.nextAction = math.max(s.nextAction, s.stunnedUntil)
    s.blocking = false
    s.serial += 1 -- cancels attacks currently winding up
    notify(player, "Stunned", duration)
    AnimRemote:FireAllClients(player, "Stun")
end

local function processHit(attackerPlayer, attackerRoot, targetModel, damage, heavy, combo)
    local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
    local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
    if not targetHum or targetHum.Health <= 0 or not targetRoot then return end
    if (targetRoot.Position - attackerRoot.Position).Magnitude > Config.HitDistanceLimit then return end
    if (targetRoot.Position - attackerRoot.Position):Dot(attackerRoot.CFrame.LookVector) < -1.5 then return end
    if not unobstructed(attackerPlayer.Character, targetModel,
        attackerRoot.Position + Vector3.new(0, 1.5, 0), targetRoot.Position + Vector3.new(0, 1.5, 0)) then return end

    local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
    local victim = targetPlayer and stateFor(targetPlayer) or nil
    local now = os.clock()
    if victim and now < victim.iframeUntil then
        notify(attackerPlayer, "Evaded")
        return
    end

    local forwardToAttacker = attackerRoot.Position - targetRoot.Position
    local facing = forwardToAttacker.Magnitude < 0.1 or targetRoot.CFrame.LookVector:Dot(forwardToAttacker.Unit) >= 0.15
    if victim and victim.blocking and now >= victim.stunnedUntil and facing then
        if now - victim.blockSince <= Config.ParryWindow then
            notify(targetPlayer, "Parry")
            AnimRemote:FireAllClients(targetPlayer, "Parry")
            notify(attackerPlayer, "Parried")
            setStunned(attackerPlayer, Config.ParryStun)
            visual(targetRoot.Position + Vector3.new(0, 2, 0), 4.5, true)
            return
        end
        local guardDamage = heavy and Config.HeavyGuardDamage or Config.LightGuardDamage
        victim.guard = math.max(0, victim.guard - guardDamage)
        victim.lastGuardHit = now
        targetPlayer:SetAttribute("EC_Guard", math.floor(victim.guard + 0.5))
        if victim.guard <= 0 then
            victim.guard = 0
            victim.blocking = false
            setStunned(targetPlayer, Config.GuardBreakStun)
            notify(targetPlayer, "GuardBroken")
            notify(attackerPlayer, "GuardBreak")
        else
            notify(targetPlayer, "Blocked", guardDamage)
            AnimRemote:FireAllClients(targetPlayer, "BlockHit")
            notify(attackerPlayer, "Guarded")
        end
        local chip = heavy and Config.HeavyChipDamage or Config.LightChipDamage
        if chip > 0 then targetHum:TakeDamage(chip) end
        visual(targetRoot.Position + Vector3.new(0, 2, 0), 3.6, false)
        return
    end

    targetHum:TakeDamage(damage)
    notify(attackerPlayer, "Hit", damage)
    -- Damage remains authoritative on the server. Visual hit reactions are broadcast.
    if not targetPlayer or (not heavy and combo ~= 3) then
        AnimRemote:FireAllClients(targetPlayer or targetModel, "Hit")
    end
    if targetPlayer then
        notify(targetPlayer, "Damaged", damage)
        if heavy or combo == 3 then
            setStunned(targetPlayer, Config.HitStun + 0.13)
        end
    end
    if heavy or combo == 3 then
        local push = targetRoot.Position - attackerRoot.Position
        if push.Magnitude > 0.1 then
            local dir = Vector3.new(push.X, 0, push.Z)
            if dir.Magnitude > 0.1 then
                targetRoot.AssemblyLinearVelocity = dir.Unit * (heavy and 33 or 23) + Vector3.new(0, 11, 0)
            end
        end
    end
    visual(targetRoot.Position + Vector3.new(0, 2, 0), heavy and 5.5 or 3.5, heavy)
end

local function performStrike(player, serial, heavy, combo)
    local s = stateByPlayer[player]
    local character, _, root = livingCharacter(player)
    if not s or s.serial ~= serial or not character or cantAct(player, s, os.clock()) then return end
    local candidates = makeHitbox(character, root)
    local seen = {}
    for _, part in ipairs(candidates) do
        local current = part
        local model = nil
        while current and current ~= Workspace do
            if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
                model = current
                break
            end
            current = current.Parent
        end
        if model and model ~= character and not seen[model] then
            seen[model] = true
            local damage = heavy and Config.HeavyDamage or Config.LightDamage[combo]
            processHit(player, root, model, damage, heavy, combo)
        end
    end
end

Remote.OnServerEvent:Connect(function(player, action)
    if type(action) ~= "string" then return end
    local s = stateFor(player)
    local character, _, root = livingCharacter(player)
    if not character then return end
    local now = os.clock()

    if action == "BlockStart" then
        if s.blocking or cantAct(player, s, now) or now < s.nextAction or s.guard < 1 then return end
        s.blocking = true
        s.blockSince = now
        notify(player, "Blocking", true)
        AnimRemote:FireAllClients(player, "BlockStart")
        return
    elseif action == "BlockEnd" then
        s.blocking = false
        notify(player, "Blocking", false)
        AnimRemote:FireAllClients(player, "BlockEnd")
        return
    elseif action == "Dodge" then
        if cantAct(player, s, now) or s.blocking or now < s.nextAction or now < s.dodgeReady then return end
        local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
        local move = character:FindFirstChildOfClass("Humanoid").MoveDirection
        if move.Magnitude > 0.08 then flat = Vector3.new(move.X, 0, move.Z) end
        if flat.Magnitude < 0.08 then return end
        s.iframeUntil = now + Config.DodgeIFrames
        s.dodgeReady = now + Config.DodgeCooldown
        s.nextAction = now + Config.DodgeRecovery
        s.serial += 1
        root.AssemblyLinearVelocity = flat.Unit * Config.DodgeSpeed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
        notify(player, "Dodge", Config.DodgeCooldown)
        AnimRemote:FireAllClients(player, "Dodge")
        return
    end

    if action ~= "Light" and action ~= "Heavy" then return end
    if s.blocking or cantAct(player, s, now) or now < s.nextAction then return end

    local heavy = action == "Heavy"
    local combo = 0
    local windup, recovery
    if heavy then
        s.combo = 0
        windup = Config.HeavyWindup
        recovery = Config.HeavyRecovery
    else
        if now - s.lastLight > Config.ComboReset then s.combo = 0 end
        s.combo = (s.combo % 3) + 1
        combo = s.combo
        s.lastLight = now
        windup = Config.LightWindup[combo]
        recovery = Config.LightRecovery[combo]
    end
    s.nextAction = now + recovery
    s.serial += 1
    local serial = s.serial
    notify(player, "Swing", heavy and "Heavy" or combo)
    AnimRemote:FireAllClients(player, heavy and "Heavy" or ("Light" .. tostring(combo)))
    visual(root.Position + root.CFrame.LookVector * 3 + Vector3.new(0, 2, 0), heavy and 4.2 or 2.7, heavy)
    task.delay(windup, function()
        performStrike(player, serial, heavy, combo)
    end)
end)

RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    for player, s in pairs(stateByPlayer) do
        local _, hum = livingCharacter(player)
        if not hum then
            s.blocking = false
        elseif s.guard < Config.GuardMax and not s.blocking and now - s.lastGuardHit >= Config.GuardRegenDelay then
            local before = math.floor(s.guard + 0.5)
            s.guard = math.min(Config.GuardMax, s.guard + math.min(dt, 0.1) * Config.GuardRegenPerSecond)
            local after = math.floor(s.guard + 0.5)
            if after ~= before then player:SetAttribute("EC_Guard", after) end
        end
    end
end)

local function connectPlayer(player)
    stateFor(player)
    player.CharacterAdded:Connect(function()
        local s = stateFor(player)
        s.guard = Config.GuardMax
        s.blocking = false
        s.iframeUntil = 0
        s.stunnedUntil = 0
        s.nextAction = 0
        s.dodgeReady = 0
        s.combo = 0
        s.serial += 1
        player:SetAttribute("EC_Guard", Config.GuardMax)
    end)
end
Players.PlayerAdded:Connect(connectPlayer)
for _, p in ipairs(Players:GetPlayers()) do connectPlayer(p) end
Players.PlayerRemoving:Connect(function(player) stateByPlayer[player] = nil end)

]====]
boulder.Source = [====[
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

]====]
local localScript = scripts:FindFirstChild("CombatAnimationClient")
if localScript and not localScript:IsA("LocalScript") then error("CombatAnimationClient name in use") end
if localScript then backupOnce("CombatAnimationClient_PrePolish_Source", localScript) end
if not localScript then
    localScript = Instance.new("LocalScript")
    localScript.Name = "CombatAnimationClient"
    localScript.Parent = scripts
end
localScript.Source = [====[
-- Elemental Clash v0.3 - procedural combat animation layer.
-- Blended procedural poses using joint.Transform; supports Motor6D and AnimationConstraint.
-- Every client animates all visible fighters using events confirmed by the server.
-- R15 is recommended. Basic R6 support is provided.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local AnimationRemote = ReplicatedStorage:WaitForChild("CombatAnimationRemote")
local states = setmetatable({}, {__mode = "k"})

local I = CFrame.identity
local function R(x, y, z)
    return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Pose names are logical joints. Map them to Motor6D or upgraded R15 AnimationConstraint joints.
local jointNames = {
    RightShoulder = {"RightShoulder", "Right Shoulder"},
    LeftShoulder = {"LeftShoulder", "Left Shoulder"},
    RightHip = {"RightHip", "Right Hip"},
    LeftHip = {"LeftHip", "Left Hip"},
    Waist = {"Waist", "RootJoint", "Root"},
    Neck = {"Neck"},
    RightElbow = {"RightElbow"},
    LeftElbow = {"LeftElbow"},
    RightKnee = {"RightKnee"},
    LeftKnee = {"LeftKnee"},
}

local function collectJoints(model)
    local motors = {}
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then motors[descendant.Name] = descendant end
    end
    local result = {}
    for key, names in pairs(jointNames) do
        -- Prefer the R15 Waist over Root, independent of descendant order.
        -- R6 falls back to RootJoint; the R15 root stays under Animator control.
        for _, name in ipairs(names) do
            if motors[name] then
                result[key] = motors[name]
                break
            end
        end
    end
    return result
end

-- Each clip uses authored poses at specific times. No hardcoded animation asset IDs.
-- Durations correspond roughly to combat timings in CombatConfig v0.2.
local clips = {
    Light1 = {
        {0, {}},
        -- Compact guard -> forward extension -> guard. The rear hand stays up.
        {0.07, {RightShoulder=R(25,-8,12), RightElbow=R(115,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(0,-12,0)}},
        {0.15, {RightShoulder=R(88,0,5), RightElbow=R(8,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(-3,18,0), Neck=R(0,-8,0)}},
        {0.27, {RightShoulder=R(35,-8,18), RightElbow=R(110,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(0,6,0)}},
        {0.34, {}},
    },
    Light2 = {
        {0, {}},
        {0.09, {LeftShoulder=R(25,8,-12), LeftElbow=R(115,0,0), RightShoulder=R(35,-8,18), RightElbow=R(110,0,0), Waist=R(0,12,0)}},
        {0.17, {LeftShoulder=R(88,0,-5), LeftElbow=R(8,0,0), RightShoulder=R(35,-8,18), RightElbow=R(110,0,0), Waist=R(-3,-18,0), Neck=R(0,8,0)}},
        {0.29, {LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), RightShoulder=R(35,-8,18), RightElbow=R(110,0,0), Waist=R(0,-6,0)}},
        {0.36, {}},
    },
    Light3 = {
        {0, {}},
        -- Forward hip pitch and backward knee flexion; hands retain guard.
        {0.11, {RightShoulder=R(35,-8,18), LeftShoulder=R(35,8,-18), RightElbow=R(110,0,0), LeftElbow=R(110,0,0), Waist=R(6,-18,0), RightHip=R(65,0,0), RightKnee=R(-95,0,0)}},
        {0.22, {RightShoulder=R(35,-8,18), LeftShoulder=R(35,8,-18), RightElbow=R(110,0,0), LeftElbow=R(110,0,0), Waist=R(10,16,0), RightHip=R(82,0,0), RightKnee=R(-8,0,0), LeftHip=R(-8,0,0)}},
        {0.43, {RightShoulder=R(35,-8,18), LeftShoulder=R(35,8,-18), RightElbow=R(110,0,0), LeftElbow=R(110,0,0), RightHip=R(40,0,0), RightKnee=R(-65,0,0), Waist=R(4,6,0)}},
        {0.58, {}},
    },
    Heavy = {
        {0, {}},
        {0.20, {RightShoulder=R(45,-10,22), RightElbow=R(120,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(4,-28,0), Neck=R(-5,0,0)}},
        {0.43, {RightShoulder=R(88,0,8), RightElbow=R(12,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(-8,28,0), Neck=R(5,0,0)}},
        {0.68, {RightShoulder=R(35,-8,18), RightElbow=R(110,0,0), LeftShoulder=R(35,8,-18), LeftElbow=R(110,0,0), Waist=R(-3,8,0)}},
        {0.86, {}},
    },
    Dodge = {
        {0, {}},
        {0.08, {Waist=R(25,0,0), RightShoulder=R(40,0,30), LeftShoulder=R(40,0,-30), RightHip=R(-25,0,0), LeftHip=R(20,0,0)}},
        {0.19, {Waist=R(15,0,0), RightShoulder=R(17,0,20), LeftShoulder=R(17,0,-20)}},
        {0.29, {}},
    },
    Hit = {
        {0, {}},
        {0.08, {Waist=R(-15,0,0), RightShoulder=R(30,0,12), LeftShoulder=R(30,0,-12), Neck=R(-15,0,0)}},
        {0.22, {}},
    },
    Stun = {
        {0, {}},
        {0.12, {Waist=R(-21,8,0), RightShoulder=R(52,0,20), LeftShoulder=R(40,0,-30), Neck=R(-16,0,0)}},
        {0.38, {Waist=R(-8,0,0), RightShoulder=R(25,0,12), LeftShoulder=R(25,0,-12)}},
        {0.56, {}},
    },
    Parry = {
        {0, {}},
        {0.08, {RightElbow=R(100,0,0), LeftElbow=R(100,0,0), RightShoulder=R(60,0,30), LeftShoulder=R(60,0,-30), Waist=R(8,0,0)}},
        {0.22, {RightShoulder=R(60,0,17), LeftShoulder=R(60,0,-17)}},
        {0.36, {}},
    },
    BlockHit = {
        {0, {}},
        {0.06, {RightShoulder=R(60,-12,35), LeftShoulder=R(60,12,-35), RightElbow=R(115,0,0), LeftElbow=R(115,0,0), Waist=R(-6,0,0)}},
        {0.18, {}},
    },
    BoulderLaunch = {
        {0, {}},
        {0.10, {RightShoulder=R(30,0,25), LeftShoulder=R(30,0,-25), RightElbow=R(105,0,0), LeftElbow=R(105,0,0), Waist=R(6,-12,0)}},
        {0.25, {RightShoulder=R(88,0,12), LeftShoulder=R(88,0,-12), RightElbow=R(10,0,0), LeftElbow=R(10,0,0), Waist=R(-10,12,0)}},
        {0.46, {RightShoulder=R(45,0,18), LeftShoulder=R(45,0,-18), RightElbow=R(65,0,0), LeftElbow=R(65,0,0)}},
        {0.62, {}},
    },
}

-- Positive X pitch brings downward R15 arms toward character-forward (-Z).
local blockPose = {RightShoulder=R(35,-12,25), LeftShoulder=R(35,12,-25), RightElbow=R(110,0,0), LeftElbow=R(110,0,0), Waist=R(6,0,0)}
local boulderPose = {RightShoulder=R(65,0,26), LeftShoulder=R(65,0,-26), RightElbow=R(35,0,0), LeftElbow=R(35,0,0), Waist=R(-7,0,0)}

-- Only joints authored by a clip are owned; punching never resets walking legs.
local clipJoints = {}
for name, frames in pairs(clips) do
    local mask = {}
    for _, frame in ipairs(frames) do
        for jointName in pairs(frame[2]) do mask[jointName] = true end
    end
    clipJoints[name] = mask
end

local function poseAt(frames, elapsed, mask, heldPose)
    if elapsed >= frames[#frames][1] then return nil end
    local before, after = frames[1], frames[#frames]
    for i = 1, #frames-1 do
        if elapsed <= frames[i+1][1] then
            before, after = frames[i], frames[i+1]
            break
        end
    end
    local span = math.max(0.001, after[1] - before[1])
    local alpha = math.clamp((elapsed - before[1]) / span, 0, 1)
    alpha = alpha * alpha * (3 - 2 * alpha)
    local result = {}
    for jointName in pairs(mask) do
        local a = before[2][jointName] or heldPose[jointName] or I
        local b = after[2][jointName] or heldPose[jointName] or I
        result[jointName] = a:Lerp(b, alpha)
    end
    return result
end

local function getState(character)
    local state = states[character]
    if state then
        -- CharacterAdded can fire before its joints are fully available.
        if not state.joints.RightShoulder or not state.joints.LeftShoulder then
            state.joints = collectJoints(character)
        end
        return state
    end
    state = {
        joints = collectJoints(character),
        active = nil, blocking = false, boulder = false,
        offsets = {}, bases = {}, nextJointRefresh = 0,
    }
    states[character] = state
    return state
end

local function impactFX(character, parry)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local part = Instance.new("Part")
    part.Name = "EC_LocalImpactFX"
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = parry and Color3.fromRGB(241, 223, 129) or Color3.fromRGB(187, 160, 117)
    part.Size = Vector3.new(1.2, 1.2, 1.2)
    part.Transparency = 0.32
    part.CFrame = root.CFrame * CFrame.new(0, 1.6, -1)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Parent = workspace
    Debris:AddItem(part, 0.14)
    local attachment = Instance.new("Attachment")
    attachment.Parent = part
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "StoneDust"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Color = ColorSequence.new(part.Color)
    emitter.Lifetime = NumberRange.new(0.12, 0.3)
    emitter.Speed = NumberRange.new(4, 13)
    emitter.SpreadAngle = Vector2.new(140, 140)
    emitter.Rate = 0
    emitter.Parent = attachment
    emitter:Emit(parry and 17 or 9)
end

local function targetModel(actor)
    if typeof(actor) ~= "Instance" then return nil end
    if actor:IsA("Player") then return actor.Character end
    if actor:IsA("Model") then return actor end
    return nil
end

AnimationRemote.OnClientEvent:Connect(function(actor, eventName)
    if type(eventName) ~= "string" then return end
    local character = targetModel(actor)
    if not character or not character.Parent then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    local state = getState(character)
    if eventName == "BlockStart" then
        state.blocking = true
        state.active = nil
    elseif eventName == "BlockEnd" then
        state.blocking = false
    elseif eventName == "BoulderStart" then
        state.boulder = true
        state.blocking = false
        state.active = nil
    elseif eventName == "BoulderEnd" then
        state.boulder = false
    elseif eventName == "BoulderLaunch" then
        state.boulder = false
        state.active = {name="BoulderLaunch", started=os.clock()}
    elseif clips[eventName] then
        if eventName == "Stun" or eventName == "Hit" then
            state.blocking = false
            if eventName == "Hit" then impactFX(character, false) end
        elseif eventName == "Parry" then
            impactFX(character, true)
        end
        state.active = {name=eventName, started=os.clock()}
    end
end)

-- Remove only our previous overrides BEFORE Animator evaluates the next frame.
-- This also prevents accumulation on joints a custom Animator doesn't animate.
RunService.PreAnimation:Connect(function()
    for _, state in pairs(states) do
        for joint, base in pairs(state.bases) do
            if joint.Parent then joint.Transform = base end
        end
        table.clear(state.bases)
    end
end)

-- Apply after Animator, blending from its fresh pose. No C0/C1 or movement edits.
RunService.PreSimulation:Connect(function(dt)
    local now = os.clock()
    local blend = 1 - math.exp(-28 * math.max(dt, 0))
    for character, state in pairs(states) do
        if not character.Parent then
            for joint, base in pairs(state.bases) do
                if joint.Parent then joint.Transform = base end
            end
            states[character] = nil
            continue
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local alive = humanoid and humanoid.Health > 0
        if not alive then
            state.active = nil
            state.blocking = false
            state.boulder = false
        end
        -- Streaming/custom rigs may expose limb joints after the shoulders.
        if now >= state.nextJointRefresh then
            state.joints = collectJoints(character)
            state.nextJointRefresh = now + 0.5
        end
        local pose = state.boulder and boulderPose or (state.blocking and blockPose or {})
        if state.active then
            local name = state.active.name
            local activePose = poseAt(clips[name], now - state.active.started, clipJoints[name], pose)
            if activePose then
                -- Fill only held-pose joints absent from the active clip.
                local combined = table.clone(pose)
                for jointName, value in pairs(activePose) do combined[jointName] = value end
                pose = combined
            else
                state.active = nil
            end
        end
        for name, joint in pairs(state.joints) do
            if joint and joint.Parent then
                local base = joint.Transform
                local target = pose[name]
                local offset = state.offsets[name]
                if not alive then
                    state.offsets[name] = nil
                elseif target or offset then
                    -- Targets are absolute authored joint poses, relative to this frame's
                    -- locomotion. Untouched joints retain the Animator's exact output.
                    local desired = target and (base:Inverse() * target) or I
                    offset = (offset or I):Lerp(desired, blend)
                    local _, angle = offset:ToAxisAngle()
                    if not target and math.abs(angle) < 0.001 then
                        state.offsets[name] = nil
                    else
                        state.offsets[name] = offset
                        state.bases[joint] = base
                        joint.Transform = base * offset
                    end
                end
            end
        end
    end
end)

-- Late joiners can see existing held-boulder poses through the replicated attribute.
local function connectPlayer(player)
    local function bindCharacter(character)
        local s = getState(character)
        s.boulder = player:GetAttribute("EC_HoldingBoulder") == true
    end
    if player.Character then bindCharacter(player.Character) end
    player.CharacterAdded:Connect(bindCharacter)
    player:GetAttributeChangedSignal("EC_HoldingBoulder"):Connect(function()
        local character = player.Character
        if character then
            local state = getState(character)
            state.boulder = player:GetAttribute("EC_HoldingBoulder") == true
        end
    end)
end
Players.PlayerAdded:Connect(connectPlayer)
for _, player in ipairs(Players:GetPlayers()) do connectPlayer(player) end

]====]
print("[Elemental Clash] v0.3 installed. Combat and boulder servers patched; procedural combat animations enabled for R15/R6.")
print("[Elemental Clash] Press Play, test three-hit combo / heavy / F block / Q dodge / E boulder, then test 2-player replication.")
