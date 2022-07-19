AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local invis = Color(0,0,0,0)

local function CheckShouldRemove(self, _, _, new)
	if (bit.band(new, bit.lshift(1, self:GetTargetBone())) != 0) then
		self:Remove()
	end
end

function ENT:Initialize()
	local body = self:GetBody()
	self:SetModel(body:GetModel())
	self:SetSkin(body:GetSkin())
	self:SetPos(body:GetPos())
	self:SetParent(body)
	self:AddEffects(EF_BONEMERGE)

	self:SetLightingOriginEntity(body.GS2LimbRelays[self:GetTargetBone()])

	self:SetTransmitWithParent(true)
	self:DrawShadow(false)
	body:DrawShadow(false)
	body:SetColor(invis)

	for _, data in pairs(body:GetBodyGroups()) do
		local bg = body:GetBodygroup(data.id)
		self:SetBodygroup(data.id, bg)
	end	

	self:NetworkVarNotify("GibMask", CheckShouldRemove)
end