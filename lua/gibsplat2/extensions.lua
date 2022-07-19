local DMGINFO = FindMetaTable("CTakeDamageInfo")

local COLL_CACHE = {}

local vec_max = Vector(1, 1, 1)
local vec_min = -vec_max

function DMGINFO:GetHitPhysBone(ent)
	local mdl = ent:GetModel()

	local colls = COLL_CACHE[mdl]
	if !colls then
		colls = CreatePhysCollidesFromModel(mdl)
		COLL_CACHE[mdl] = colls
	end

	if !colls then return 0 end

	local dmgpos = self:GetDamagePosition()

	local dmgdir = self:GetDamageForce()
	dmgdir:Normalize()

	local ray_start = dmgpos - dmgdir * 50
	local ray_end = dmgpos + dmgdir * 50

	for phys_bone, coll in pairs(colls) do
		phys_bone = phys_bone - 1
		local bone = ent:TranslatePhysBoneToBone(phys_bone)
		local matrix = ent:GetBoneMatrix(bone)
		if !matrix then continue end

		local pos, ang = matrix:GetTranslation(), matrix:GetAngles()

		if !pos or !ang then continue end
		
		if coll:TraceBox(pos, ang, ray_start, ray_end, vec_min, vec_max) then
			return phys_bone
		end
	end
end

local PHYSOBJ = FindMetaTable("PhysObj")

function PHYSOBJ:GetID()
	local ent = self:GetEntity()
	for pbone = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(pbone)
		if phys == self then
			return pbone
		end
	end
end