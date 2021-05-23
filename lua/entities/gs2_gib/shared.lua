include("gibsplat2/gibs.lua")

local gib_expensive = GetConVar("gs2_gib_expensive")
local gib_chance	= GetConVar("gs2_gib_chance")

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.LifeTime = GetConVar("gs2_gib_lifetime")

game.AddDecal("BloodSmall", {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
})

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

function ENT:PhysicsSimulate()
	self.LastSim = CurTime()
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
			--phys_self:SetMaterial("watermelon")
			self.GS2_dummy = false
			self:StartMotionController()
			
			phys_self:SetDragCoefficient(0)	
		end
	end
end

local VERT_CACHE = {}
local CONVEX_CACHE = {}

function ENT:IsTouching(other)
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
		if gib_expensive:GetBool() then
			self:PhysicsInitConvex(self.GS2GibInfo.vertex_buffer)
		else
			local min = Vector(math.huge, math.huge, math.huge)
			local max = -min
			for _, vert in ipairs(verts) do
				min.x = math.min(min.x, vert.x)
				min.y = math.min(min.y, vert.y)
				min.z = math.min(min.z, vert.z)

				max.x = math.max(max.x, vert.x)
				max.y = math.max(max.y, vert.y)
				max.z = math.max(max.z, vert.z)
			end
			self:PhysicsInitBox(min, max)
		end
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

function ENT:PhysicsCollide(data, phys_self)
	local speed = data.Speed
	if (self.Created and speed > 1500 and CurTime() - self.Created > 1) then
		self:Remove()
		return
	end
	local phys_self = self:GetPhysicsObject()
	if SERVER then
		if (!data.HitEntity:IsWorld() and !data.HitEntity:IsRagdoll() and phys_self:GetEnergy() == 0) then --0 energy = jammed in something
			if (math.random() > gib_chance:GetFloat() or phys_self:GetPos():Distance(data.HitPos) > self:BoundingRadius() * 0.7) then
				self:Remove()
			else	
				local color = self.GS2BloodColor
				if color then
					local decal = decals[color]
					if decal then
						util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
						util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
					end
				end
				local phys = data.HitObject
				local lpos, lang = WorldToLocal(phys_self:GetPos(), phys_self:GetAngles(), phys:GetPos(), phys:GetAngles())
				timer.Simple(0, function()
					if (IsValid(self) and IsValid(phys)) then			
						self:SetNotSolid(true)
						self:PhysicsDestroy()
						local pos, ang = LocalToWorld(lpos, lang, phys:GetPos(), phys:GetAngles())
						self:SetPos(pos)
						self:SetAngles(ang)
						self:SetParent(data.HitEntity)									
					end
				end)			
			end
		end
	end

	if (data.DeltaTime < 0.05) then
		return
	end
	
	if (speed > 100) then
		local color = self.GS2BloodColor
		if color then
			local decal = decals[color]
			if decal then
				util.Decal(decal, data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				util.Decal(decal, data.HitPos - data.HitNormal, data.HitPos + data.HitNormal)
			end
		end
		
		if (phys_self:GetVolume() > 500) then
			util.Decal("Blood", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
			local EF = EffectData()
				EF:SetOrigin(self:LocalToWorld(phys_self:GetMassCenter()))
				EF:SetColor(color)
			for i = 1, 5 do
				util.Effect("BloodImpact", EF)
			end
		end

		self:EmitSound("Watermelon.Impact")
	end	
end

local enabled = GetConVar("gs2_enabled")

local function Collide(ent1, ent2)
	local class1 = ent1:GetClass()
	local class2 = ent2:GetClass()
	if class1:find("^gs2_gib") then
		if class2:find("^gs2_gib") then
			return false
		end		
		if (class2 == "prop_ragdoll") then
			return false
		end
	end
	return true
end

hook.Add("ShouldCollide", HOOK_NAME, function(ent1, ent2)
	if !enabled:GetBool() then return end
	
	if (!Collide(ent1, ent2) or !Collide(ent2, ent1)) then
		return false
	end
end)