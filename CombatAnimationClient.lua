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
