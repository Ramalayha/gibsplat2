AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	self:SetModel("models/gibsplat2/bullethole.mdl")
	self:GetBody():DeleteOnRemove(self)
end