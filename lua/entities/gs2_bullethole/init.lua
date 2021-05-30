AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local models =
{
	["models/props_junk/watermelon01_chunk02a.mdl"] = 0.5,
	--["models/props_junk/watermelon01_chunk02b.mdl"] = 1,
	["models/props_mining/rock_caves01b.mdl"] = 0.3,
	["models/props_mining/rock_caves01c.mdl"] = 0.4
}

function ENT:Initialize()
	--self:SetModel("models/props_junk/watermelon01.mdl")
	--self:SetModelScale(0.3)
	
	local scale, mdl = table.Random(models)
	self:SetModel(mdl)
	self:SetModelScale(scale)
	
	self:GetBody():DeleteOnRemove(self)

	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)

	local pos = phys:GetPos()
	local ang = phys:GetAngles()

	local lpos, lang = WorldToLocal(self:GetPos(), self:GetAngles(), pos, ang)

	local rad = self:BoundingRadius()

	local c = Vector(lpos.x, 0, 0)

	local offset = c - lpos
	offset:Normalize()
	offset:Mul(rad / 4)
	lpos:Add(offset)

	self:SetLPos(lpos)
	self:SetLAng(lang)

	body.GS2BulletHoles = body.GS2BulletHoles or {}
	body.GS2BulletHoles[phys_bone] = body.GS2BulletHoles[phys_bone] or {}

	table.insert(body.GS2BulletHoles[phys_bone], self)

	self:SetNoDraw(true)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_PVS
end