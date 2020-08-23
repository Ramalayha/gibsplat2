AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	local body = self:GetBody()
	self:SetModel(body:GetModel())
	self:SetParent(body)
	self:AddEffects(EF_BONEMERGE)
	self:DrawShadow(false)
end