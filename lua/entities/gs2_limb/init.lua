AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local invis = Color(0,0,0,0)

function ENT:Initialize()
	local body = self:GetBody()
	self:SetModel(body:GetModel())
	self:SetSkin(body:GetSkin())
	self:SetPos(body:GetPos())
	self:SetParent(body)
	self:SetTransmitWithParent(true)
	self:DrawShadow(false)
	body:DrawShadow(false)
	body:SetColor(invis)

	for _, data in pairs(body:GetBodyGroups()) do
		local bg = body:GetBodygroup(data.id)
		self:SetBodygroup(data.id, bg)
	end	
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end