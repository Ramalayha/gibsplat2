local data = util.KeyValuesToTable(file.Read("data/gs2/skeletons.txt", "GAME"))

--PrintTable(data)

local info = util.KeyValuesToTable(file.Read("data/gs2/skeletons.txt", "GAME"))

local body_types = info.body_types


local CACHE = {}

function GetBodyType(mdl)
	if CACHE[mdl] then
		return CACHE[mdl]
	end

	mdl = mdl:lower()

	local str = file.Read(mdl, "GAME")
	if !str then
		return
	end

	str = str:lower()

	for body_type, list in pairs(body_types) do
		for _, find in pairs(list) do
			if str:find(find) then
				CACHE[mdl] = body_type
				return body_type
			end
		end
	end

	for model_include in str:gmatch("(models/.-%.mdl)") do
		if model_include != mdl then			
			local ret = GetModelGender(model_include)
			if ret then
				CACHE[mdl] = ret
				return ret
			end
		end
	end

	if CACHE[mdl] then
		return CACHE[mdl]
	else
		CACHE[mdl] = ""
	end
end

local skeleton_parts = info.skeleton_parts

local PARTS = {}

function SpawnBone(self, phys_bone)
	local mdl = self:GetModel()
	if PARTS[mdl] and PARTS[mdl][phys_bone] then
		return PARTS[mdl][phys_bone]
	end

	local body_type = GetBodyType(mdl)

	local parts = skeleton_parts[body_type]

	if !parts then
		return
	end

	local bone = self:TranslatePhysBoneToBone(phys_bone)
	local bone_name = self:GetBoneName(bone):lower()

	local bone_mdl = parts[bone_name]

	if !bone_mdl then
		return
	end

	PARTS[mdl] = PARTS[mdl] or {}
	local part = ClientsideModel(bone_mdl)
	part:SetupBones()
	
	local bone_matrix = self:GetBoneMatrix(bone)

	local bone_pos, bone_ang = bone_matrix:GetTranslation(), bone_matrix:GetAngles()
	part:SetPos(bone_pos)
	part:SetAngles(bone_ang)
	part:SetParent(self)
	part:AddEffects(EF_BONEMERGE)

	PARTS[mdl][phys_bone] = part
end