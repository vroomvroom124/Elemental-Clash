local fighter=character(true)
local legBase=CFrame.Angles(0.25,0,0)
fighter.joints.LeftHip.Transform=legBase
remote.OnClientEvent:Fire(fighter,'Light1')
step(0.15)
assert(states[fighter].joints.Waist==fighter.joints.Waist,'R15 root was selected instead of Waist')
assert(equal(fighter.joints.Root.Transform,CFrame.identity),'Punch posed R15 root')
assert(equal(fighter.joints.LeftHip.Transform,legBase),'Punch stomped locomotion')
assert(not equal(fighter.joints.RightElbow.Transform,CFrame.identity),'Punch did not articulate elbow')
run.PreAnimation:Fire()
assert(equal(fighter.joints.RightElbow.Transform,CFrame.identity),'Previous override was not removed')
assert(equal(fighter.joints.LeftHip.Transform,legBase),'Restore touched unowned hip')
for _=1,100 do step(1/60) end
assert(next(states[fighter].offsets)==nil,'Recovery did not release joints')
assert(equal(fighter.joints.RightShoulder.Transform,CFrame.identity),'Shoulder did not recover')
remote.OnClientEvent:Fire(fighter,'BlockStart')
for _=1,30 do step(1/60) end
assert(states[fighter].blocking and not equal(fighter.joints.RightElbow.Transform,CFrame.identity),'Guard did not bend elbow')
assert(equal(fighter.joints.RightElbow.Transform,blockPose.RightElbow),'Held pose accumulated frame over frame')
run.PreAnimation:Fire()
local newBase=CFrame.Angles(0.1,0.2,0)
fighter.joints.RightShoulder.Transform=newBase
run.PreSimulation:Fire(1/60)
run.PreAnimation:Fire()
assert(equal(fighter.joints.RightShoulder.Transform,newBase),'Restore lost fresh Animator output')
remote.OnClientEvent:Fire(fighter,'BlockHit')
assert(states[fighter].active.name=='BlockHit','Server-confirmed BlockHit ignored')
for _=1,30 do step(1/60) end
assert(states[fighter].blocking and states[fighter].active==nil,'BlockHit lost held guard')
remote.OnClientEvent:Fire(fighter,'BlockEnd')
for _=1,100 do step(1/60) end
assert(next(states[fighter].offsets)==nil,'Guard release left stale offsets')
remote.OnClientEvent:Fire(fighter,'Light3')
step(0.11)
assert(not equal(fighter.joints.RightKnee.Transform,CFrame.identity),'Kick did not chamber knee')
remote.OnClientEvent:Fire(fighter,'BoulderStart')
assert(states[fighter].active==nil and states[fighter].boulder,'Boulder did not interrupt old clip')
remote.OnClientEvent:Fire(fighter,'BoulderLaunch')
assert(states[fighter].active.name=='BoulderLaunch' and not states[fighter].boulder,'Launch state wrong')
remote.OnClientEvent:Fire(fighter,'Hit')
assert(states[fighter].active.name=='Hit','Hit did not interrupt launch')
fighter.hum.Health=0
step(1/60)
assert(next(states[fighter].offsets)==nil and next(states[fighter].bases)==nil,'Death retained overrides')
local classic=character(false)
remote.OnClientEvent:Fire(classic,'Light3')
step(0.11)
assert(not equal(classic.joints['Right Hip'].Transform,CFrame.identity),'R6 fallback did not animate')
classic.Parent=nil
step(1/60)
assert(states[classic]==nil,'Removed character state was retained')
local streamed=character(true)
local elbow=streamed.joints.RightElbow
streamed.joints.RightElbow=nil
remote.OnClientEvent:Fire(streamed,'BlockStart')
step(0.05)
streamed.joints.RightElbow=elbow
step(0.6)
assert(not equal(elbow.Transform,CFrame.identity),'Late-streamed joint was not collected')
print('PASS: punch locomotion, elbow/knee articulation, recovery, guard recoil, interruptions, death, R6, cleanup, streaming')

local upgraded=character(true, 'AnimationConstraint')
remote.OnClientEvent:Fire(upgraded,'BlockStart')
for _=1,30 do step(1/60) end
assert(equal(upgraded.joints.RightElbow.Transform,blockPose.RightElbow),'Upgraded R15 guard did not animate')
assert(equal(upgraded.joints.Root.Transform,CFrame.identity),'Upgraded R15 root was overwritten')
remote.OnClientEvent:Fire(upgraded,'BlockEnd')
for _=1,100 do step(1/60) end
assert(next(states[upgraded].offsets)==nil,'Upgraded R15 guard did not release')
remote.OnClientEvent:Fire(upgraded,'Light3')
step(0.11)
assert(not equal(upgraded.joints.RightKnee.Transform,CFrame.identity),'Upgraded R15 kick did not animate')
upgraded.hum.Health=0
step(1/60)
assert(next(states[upgraded].bases)==nil,'Upgraded R15 death did not release overrides')
print('PASS: AnimationConstraint R15 guard, recovery, kick, death, and root preservation')

-- Standard R15 arms point down (-Y): positive X bends toward forward (-Z).
for _, name in ipairs({'RightShoulder','LeftShoulder','RightElbow','LeftElbow'}) do
    assert(blockPose[name][8] > 0, name..' guard pitch points behind the fighter')
end
print('PASS: guard limb pitch faces forward under standard R15 joint axes')

-- Kinematic direction check on standard R15 axes, with equal-length upper/lower arms.
local function handForward(pose, side)
    local shoulder=assert(pose[side..'Shoulder'])
    local elbow=assert(pose[side..'Elbow'])
    local forearm=shoulder*elbow
    -- Resting limbs point down (-Y), and fighter-forward is -Z.
    return shoulder[8]+forearm[8]
end
for _, spec in ipairs({{'Light1','Right','Left'}, {'Light2','Left','Right'}, {'Heavy','Right','Left'}}) do
    local frames=clips[spec[1]]
    local windup, strike, recovery=frames[2][2],frames[3][2],frames[4][2]
    assert(handForward(strike,spec[2])>1.8,spec[1]..' strike points behind or away from opponent')
    assert(handForward(strike,spec[2])>handForward(windup,spec[2])+0.5,spec[1]..' does not extend from windup')
    assert(handForward(recovery,spec[2])<handForward(strike,spec[2])-0.5,spec[1]..' does not retract')
    assert(handForward(strike,spec[3])>0.8,spec[1]..' rear hand is behind torso')
end
for name, times in pairs({Light1={0,0.07,0.15,0.27,0.34},Light2={0,0.09,0.17,0.29,0.36},Light3={0,0.11,0.22,0.43,0.58},Heavy={0,0.20,0.43,0.68,0.86},BoulderLaunch={0,0.10,0.25,0.46,0.62}}) do
    assert(#clips[name]==#times,name..' changed keyframe count')
    for i,time in ipairs(times) do assert(clips[name][i][1]==time,name..' changed existing timing') end
end
assert(clips.Light3[3][2].RightHip[8]>0,'Kick hip points backward')
assert(clips.Light3[2][2].RightKnee[8]<0,'Kick knee folds forward instead of backward')
assert(handForward(boulderPose,'Right')>0 and handForward(boulderPose,'Left')>0,'Boulder hold arms point behind torso')
for _,class in ipairs({'Motor6D','AnimationConstraint'}) do
    local boxer=character(true,class)
    boxer.joints.LeftHip.Transform=legBase
    remote.OnClientEvent:Fire(boxer,'Light2')
    for _=1,10 do step(1/60) end
    assert(not equal(boxer.joints.LeftShoulder.Transform,CFrame.identity),class..' cross did not animate')
    assert(equal(boxer.joints.LeftHip.Transform,legBase),class..' cross changed locomotion leg')
    for _=1,100 do step(1/60) end
    assert(next(states[boxer].offsets)==nil,class..' cross did not release')
end
print('PASS: forward punch extension, retraction, rear-hand guard, kick/boulder direction, preserved timings, both joint classes')
