install()
local count=created
local backups=sss:FindFirstChild('ElementalClashBackups')
assert(backups:FindFirstChild('CombatServer_v0.2_Source').Value=='original combat','Combat backup lost')
assert(backups:FindFirstChild('BoulderServer_v0.2_Source').Value=='original boulder','Boulder backup lost')
assert(backups:FindFirstChild('CombatAnimationClient_PrePolish_Source').Value=='original animation client','Animation backup lost')
assert(scripts:FindFirstChild('CombatAnimationClient')==existingClient,'Installer replaced client instance')
local source=existingClient.Source
install()
assert(created==count,'Installer duplicated instances on rerun')
assert(existingClient.Source==source,'Installer rerun changed source')
assert(backups:FindFirstChild('CombatAnimationClient_PrePolish_Source').Value=='original animation client','Rerun overwrote animation backup')
assert(backups:FindFirstChild('CombatServer_v0.2_Source').Value=='original combat','Rerun overwrote server backup')
-- Also verify an initial v0.2 installation without the client or remote.
rs.children={rs:FindFirstChild('CombatRemote'),rs:FindFirstChild('BoulderRemote')}
scripts.children={}
install()
local newClient=scripts:FindFirstChild('CombatAnimationClient')
assert(newClient and newClient:IsA('LocalScript'),'Initial client installation failed')
assert(rs:FindFirstChild('CombatAnimationRemote'):IsA('RemoteEvent'),'Initial remote installation failed')
count=created
install()
assert(created==count,'Fresh installer path duplicated instances on rerun')
print('PASS: installer creates/reuses instances, preserves backups, and does not duplicate on rerun')
