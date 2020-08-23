AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	local body = self:GetBody()
	--self:SetModel("models/Roller.mdl")
	self:SetPos(body:GetPos())
	self:SetParent(body)
	self:DrawShadow(false)
end