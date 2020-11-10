include("gibsplat2/gibs.lua")

ENT.Type = "anim"
ENT.Base = "base_anim"

game.AddDecal("BloodSmall", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})

/*game.AddDecal("YellowBloodSmall", {
	"decals/alienflesh/shot1",
	"decals/alienflesh/shot2",
	"decals/alienflesh/shot3",
	"decals/alienflesh/shot4",
	"decals/alienflesh/shot5"
})*/

local decals = {
	[BLOOD_COLOR_RED] = "BloodSmall",
	[BLOOD_COLOR_YELLOW] = "YellowBlood",
	[BLOOD_COLOR_GREEN] = "YellowBlood",
	[BLOOD_COLOR_ANTLION] = "YellowBlood",
	[BLOOD_COLOR_ANTLION_WORKER] = "YellowBlood"
}

local HOOK_NAME = "GibSplat2"

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "GibIndex")
	self:NetworkVar("Int", 1, "TargetBone")
	self:NetworkVar("Entity", 0, "Body")
end

function ENT:SetBColor(color)
	self.GS2BloodColor = color
end

function ENT:InitPhysics()
	local body = self:GetBody()
	local phys_bone = self:GetTargetBone()
	
	local phys_self = self:GetPhysicsObject()
	if IsValid(phys_self) then
		if IsValid(self:GetParent()) then
			self:PhysicsDestroy()
			self:SetNotSolid(true)
		else
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			self:EnableCustomCollisions(true)
			self:SetCustomCollisionCheck(true)			
			phys_self:SetMaterial("watermelon")
			self.GS2_dummy = false
		end
	end
end

local VERT_CACHE = {}
local CONVEX_CACHE = {}

function ENT:IsTouching(other) if other:GetClass():find("custom") then return end
	local mdl = other:GetModel()
	local verts = VERT_CACHE[mdl]
	if !verts then
		VERT_CACHE[mdl] = {}
		verts = VERT_CACHE[mdl]
		local phys = other:GetPhysicsObject()
		for _, convex in ipairs(phys:GetMeshConvexes()) do
			for _, vert in pairs(convex) do
				if !table.HasValue(verts, vert.pos) then
					table.insert(verts, vert.pos)
				end
			end
		end
	end

	local body = self:GetBody()
	local mdl = body:GetModel()
	local phys_bone = self:GetTargetBone()
	local gib_index = self:GetGibIndex()

	CONVEX_CACHE[mdl] = CONVEX_CACHE[mdl] or {}
	CONVEX_CACHE[mdl][phys_bone] = CONVEX_CACHE[mdl][phys_bone] or {}
	if !CONVEX_CACHE[mdl][phys_bone][gib_index] then
		self:PhysicsInitConvex(self.GS2GibInfo.vertex_buffer)
		local phys = self:GetPhysicsObject()
		CONVEX_CACHE[mdl][phys_bone][gib_index] = phys:GetMeshConvexes()[1]
		self:PhysicsDestroy()
	end
	
	local convex = CONVEX_CACHE[mdl][phys_bone][gib_index]

	for _, vert in ipairs(verts) do
		local wpos = other:LocalToWorld(vert)
		local lpos = self:WorldToLocal(wpos)
		local is_inside = true
		for vert_index = 1, #convex - 2, 3 do
			local p1 = convex[vert_index].pos
			local p2 = convex[vert_index + 1].pos
			local p3 = convex[vert_index + 2].pos

			local n = (p3 - p1):Cross(p2 - p1)
			n:Normalize()
			local d = n:Dot(p1)				
			if (n:Dot(lpos) > d) then
				is_inside = false
				break
			end
		end
		if is_inside then
			return true
		end
	end
end

function ENT:PhysicsCollide(data, phys)
	if (data.Speed > 100) then
		local color = self.GS2BloodColor
		if color then
			local decal = decals[color]
			if decal then
				util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
			end
		end
	end
	
	if CLIENT then return end

	if ((phys:GetEnergy() == 0 and data.HitEntity:GetMoveType() == MOVETYPE_PUSH) or (data.Speed > 1000 and CurTime() - self.Created < 1)) then --0 energy = jammed in something
		self:Remove()
	end
end

local enabled = CreateConVar("gs2_enabled", 0, FCVAR_REPLICATED)

local function ShouldGibCollide(ent1, ent2)
	if !enabled:GetBool() then return end 
	if (ent1:GetClass() == "gs2_gib") then
		if (ent2:GetClass() == "gs2_gib") then
			return false
		end
		if ent2:IsRagdoll() then
			return false
		end
	elseif (ent2:GetClass() == "gs2_gib") then
		if (ent1:GetClass() == "gs2_gib") then
			return false
		end
		if ent1:IsRagdoll() then
			return false
		end
	end
end

cvars.AddChangeCallback("gs2_enabled", function(_, _, new)
	if new == "1" then
		hook.Add("ShouldCollide", HOOK_NAME, ShouldGibCollide)
	else
		hook.Remove("ShouldCollide", HOOK_NAME)
	end
end)

if enabled:GetBool() then
	hook.Add("ShouldCollide", HOOK_NAME, ShouldGibCollide)
end