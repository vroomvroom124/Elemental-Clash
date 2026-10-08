local created=0
local methods={}
function methods:IsA(class) return self.ClassName==class end
function methods:FindFirstChild(name)
    for _,child in ipairs(self.children) do if child.Name==name then return child end end
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name),name) end
local mt={__index=methods}
function mt.__newindex(self,key,value)
    if key=='Parent' and value then table.insert(value.children,self) end
    rawset(self,key,value)
end
local Instance={}
function Instance.new(class)
    created+=1
    return setmetatable({ClassName=class,children={}},mt)
end
local function child(parent,class,name,source)
    local result=Instance.new(class)
    result.Name=name
    result.Source=source
    result.Parent=parent
    return result
end
local rs=Instance.new('ReplicatedStorage')
local sss=Instance.new('ServerScriptService')
local starter=Instance.new('StarterPlayer')
local scripts=child(starter,'StarterPlayerScripts','StarterPlayerScripts')
local combat=child(sss,'Script','CombatServer','original combat')
local boulder=child(sss,'Script','BoulderServer','original boulder')
local existingClient=child(scripts,'LocalScript','CombatAnimationClient','original animation client')
child(rs,'RemoteEvent','CombatRemote')
child(rs,'RemoteEvent','BoulderRemote')
local services={ReplicatedStorage=rs,ServerScriptService=sss,StarterPlayer=starter}
local game={}
function game:GetService(name) return assert(services[name],name) end
