include("gibsplat2/gibs.lua")

ENT.Type = "anim"
ENT.Base = "base_anim"

local HOOK_NAME = "GibSplat2"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "GibIndex")
	self:NetworkVar("Int", 1, "TargetBone")
	self:NetworkVar("Entity", 0, "Body")
end

local enabled = CreateConVar("gs2_enabled", 0, FCVAR_REPLICATED)

local function ShouldGibCollide(ent1, ent2)
	if !enabled:GetBool() then return end 
	if (ent1:GetClass() == "gs2_gib") then
		if (ent2:GetClass() == "gs2_gib") then
			return false
		end
		if ent2:IsRagdoll() then
			return false
		end
	elseif (ent2:GetClass() == "gs2_gib") then
		if (ent1:GetClass() == "gs2_gib") then
			return false
		end
		if ent1:IsRagdoll() then
			return false
		end
	end
end

cvars.AddChangeCallback("gs2_enabled", function(_, _, new)
	if new == "1" then
		hook.Add("ShouldCollide", HOOK_NAME, ShouldGibCollide)
	else
		hook.Remove("ShouldCollide", HOOK_NAME)
	end
end)

if enabled:GetBool() then
	hook.Add("ShouldCollide", HOOK_NAME, ShouldGibCollide)
end