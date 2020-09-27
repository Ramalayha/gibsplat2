AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self:SetModel("models/spitball_medium.mdl")
	--self:SetModel("models/gibsplat2/bullethole.mdl")
	self:GetBody():DeleteOnRemove(self)

	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	body.GS2BulletHoles = body.GS2BulletHoles or {}
	body.GS2BulletHoles[phys_bone] = body.GS2BulletHoles[phys_bone] or {}

	table.insert(body.GS2BulletHoles[phys_bone], self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_PVS
end