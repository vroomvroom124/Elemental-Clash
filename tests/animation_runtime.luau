-- Focused mock runtime: scheduling/ownership checks, not Roblox visual playtesting.
local now = 0
local os = {clock = function() return now end}
local function signal()
    local s = {listeners = {}}
    function s:Connect(fn) table.insert(self.listeners, fn) end
    function s:Fire(...) for _, fn in ipairs(self.listeners) do fn(...) end end
    return s
end
-- Rotation matrices give real inverse/multiplication/Lerp endpoints in these checks.
-- Lerp uses normalized component interpolation; Studio uses quaternion interpolation.
local cf = {}
cf.__index = cf
local function matrix(values) return setmetatable(values, cf) end
local function identity() return matrix({1,0,0,0,1,0,0,0,1}) end
function cf.__mul(a,b)
    local r = {}
    for row=0,2 do for col=0,2 do
        local sum=0
        for k=0,2 do sum += a[row*3+k+1]*b[k*3+col+1] end
        r[row*3+col+1]=sum
    end end
    return matrix(r)
end
function cf:Inverse() return matrix({self[1],self[4],self[7],self[2],self[5],self[8],self[3],self[6],self[9]}) end
function cf:Lerp(other, alpha)
    local r={}
    for i=1,9 do r[i]=self[i]+(other[i]-self[i])*alpha end
    return matrix(r)
end
function cf:ToAxisAngle() return nil, math.acos(math.clamp((self[1]+self[5]+self[9]-1)/2,-1,1)) end
local CFrame={identity=identity()}
function CFrame.Angles(x,y,z)
    local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    return matrix({1,0,0,0,cx,-sx,0,sx,cx}) * matrix({cy,0,sy,0,1,0,-sy,0,cy}) * matrix({cz,-sz,0,sz,cz,0,0,0,1})
end
local function equal(a,b)
    for i=1,9 do if math.abs(a[i]-b[i])>1e-5 then return false end end
    return true
end
local function typeof(v) return type(v)=='table' and v.IsA and 'Instance' or type(v) end
local remote={OnClientEvent=signal()}
local run={PreAnimation=signal(),PreSimulation=signal()}
local players={PlayerAdded=signal()}
function players:GetPlayers() return {} end
local storage={}
function storage:WaitForChild(name) assert(name=='CombatAnimationRemote'); return remote end
local services={Players=players,ReplicatedStorage=storage,RunService=run,Debris={}}
local game={}
function game:GetService(name) assert(services[name], name); return services[name] end
local function character(r15, jointClass)
    local c={Parent=true, joints={}, hum={Health=100}}
    local names=r15 and {'Root','RightShoulder','LeftShoulder','RightHip','LeftHip','Waist','Neck','RightElbow','LeftElbow','RightKnee','LeftKnee'} or {'Right Shoulder','Left Shoulder','Right Hip','Left Hip','RootJoint','Neck'}
    for _,name in ipairs(names) do
        local j={Name=name,Parent=c,Transform=identity()}
        function j:IsA(kind) return kind==(jointClass or 'Motor6D') end
        c.joints[name]=j
    end
    function c:IsA(kind) return kind=='Model' end
    function c:GetDescendants() local r={} for _,j in pairs(self.joints) do table.insert(r,j) end return r end
    function c:FindFirstChildOfClass(kind) return kind=='Humanoid' and self.hum or nil end
    function c:FindFirstChild() return nil end
    return c
end
local function step(dt) now+=dt; run.PreAnimation:Fire(); run.PreSimulation:Fire(dt) end
