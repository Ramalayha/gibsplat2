AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self:SetModel("models/props_junk/watermelon01.mdl")
	self:SetModelScale(0.3)
	
	self:GetBody():DeleteOnRemove(self)

	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)

	local pos = phys:GetPos()
	local ang = phys:GetAngles()

	local lpos, lang = WorldToLocal(self:GetPos(), self:GetAngles(), pos, ang)

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