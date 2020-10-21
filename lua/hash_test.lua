--local mdl = "models/Police.mdl"
--local mdl = "models/zombie/classic.mdl"
--local mdl = "models/zombie/poison.mdl"
local mdl = "models/zombie/fast.mdl"
--local mdl = "models/player/hwm/heavy.mdl"
--local mdl = "models/buggy.mdl"
--local mdl = "models/infected/common_female01.mdl"

local e = util.IsValidRagdoll(mdl) and ClientsideRagdoll(mdl) or ClientsideModel(mdl)
e:SetupBones()
SafeRemoveEntityDelayed(e, 0.1)

local data, lookup = GetSortedMeshHashTable(mdl)

--PrintTable(data)
--for k,v in pairs(data) do print(k,v) end

for phys_bone, data in pairs(data) do
	local bone = e:TranslatePhysBoneToBone(phys_bone)
	print(e:GetBoneName(bone),table.Count(data))
	for bg_num, data in pairs(data) do
		if (e:GetBodygroupCount(bg_num) > 1) then
			print("", e:GetBodygroupName(bg_num))
		 	for bg_val, data in pairs(data) do
		 		if (table.Count(data) > 1) then
			 		print("\t", bg_val)
			 		for key, hash in pairs(data) do
			 			print("\t\t", key, hash)
			 		end
			 	end
		 	end
		end
	end
end

--for k,v in pairs(lookup) do print(k,v) end