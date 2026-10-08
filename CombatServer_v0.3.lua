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
