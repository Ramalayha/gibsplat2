AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self:GetBody():DeleteOnRemove(self)

	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	local phys = body:GetPhysicsObjectNum(phys_bone)

	local pos = phys:GetPos()
	local ang = phys:GetAngles()

	local lpos = WorldToLocal(self:GetPos(), angle_zero, pos, ang)

	local lang = (phys:GetMassCenter() - lpos):Angle()
	lang:RotateAroundAxis(lang:Forward(), math.Rand(-180, 180))

	self:SetLPos(lpos)
	self:SetLAng(lang)
	
	body.GS2BulletHoles = body.GS2BulletHoles or {}
	body.GS2BulletHoles[phys_bone] = body.GS2BulletHoles[phys_bone] or {}

	local first
	local close = 0
	for key, bh in pairs(body.GS2BulletHoles[phys_bone]) do
		if (bh:GetPos():DistToSqr(self:GetPos()) < 4) then
			first = first or key
			close = close + 1
		end
	end

	if (close > 4) then
		table.remove(body.GS2BulletHoles[phys_bone], key):Remove()
	end

	table.insert(body.GS2BulletHoles[phys_bone], self)

	self:SetNoDraw(true)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_PVS
end