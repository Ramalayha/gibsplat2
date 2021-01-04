AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local text = file.Read("materials/gibsplat2/skeletons.vmt", "GAME")

local skeleton_parts = util.KeyValuesToTable(text or "").skeleton_parts or {}

for _, data in pairs(skeleton_parts) do
	for _, mdl in pairs(data) do
		util.PrecacheModel(mdl)
	end
end

function ENT:Initialize()
	local body = self:GetBody()
	--self:SetModel("models/Roller.mdl")
	self:SetPos(body:GetPos())
	self:SetParent(body)
	self:DrawShadow(false)
end