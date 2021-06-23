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

	local dmgpos = self:GetDamagePosition()

	local dmgdir = self:GetDamageForce()
	dmgdir:Normalize()

	local ray_start = dmgpos - dmgdir * 50
	local ray_end = dmgpos + dmgdir * 50

	for phys_bone, coll in pairs(colls) do
		phys_bone = phys_bone - 1
		local bone = ent:TranslatePhysBoneToBone(phys_bone)
		local pos, ang = ent:GetBonePosition(bone)
		
		if coll:TraceBox(pos, ang, ray_start, ray_end, vec_min, vec_max) then
			return phys_bone
		end
	end
end