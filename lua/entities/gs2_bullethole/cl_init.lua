include("shared.lua")

function ENT:Initialize()
	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()

	body.GS2BulletHoles = body.GS2BulletHoles or {}
	body.GS2BulletHoles[phys_bone] = body.GS2BulletHoles[phys_bone] or {}

	table.insert(body.GS2BulletHoles[phys_bone], self)
end