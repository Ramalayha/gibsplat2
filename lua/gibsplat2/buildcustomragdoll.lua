--sv_cheats 1;god;impulse 101;lua_openscript gs2.lua

local VERSION = 2

local min_strength = CreateConVar("gs2_min_constraint_strength", 4000)
local max_strength = CreateConVar("gs2_max_constraint_strength", 15000)
local strength_mul = CreateConVar("gs2_constraint_strength_multiplier", 250)

local snd_dismember = Sound("physics/body/body_medium_break3.wav")
local snd_gib 		= Sound("physics/flesh/flesh_bloody_break.wav")

local decals = {
	flesh = "Blood",
	zombieflesh = "Blood",
	alienflesh = "YellowBlood"
}

local GetModelConstraintInfo = GetModelConstraintInfo
local timer_Simple = timer.Simple
local min = math.min
local max = math.max

local RAGDOLL_POSE = {}

local function WriteVector(F, vec)
	F:WriteFloat(vec.x)
	F:WriteFloat(vec.y)
	F:WriteFloat(vec.z)
end

local function WriteAngle(F, ang)
	F:WriteFloat(ang.p)
	F:WriteFloat(ang.y)
	F:WriteFloat(ang.r)
end

local function ReadVector(F)
	local x = F:ReadFloat()
	local y = F:ReadFloat()
	local z = F:ReadFloat()
	return Vector(x, y, z)
end

local function ReadAngle(F, ang)
	local p = F:ReadFloat()
	local y = F:ReadFloat()
	local t = F:ReadFloat()
	return Angle(p, y, r)
end

local function WriteRagdollPose(mdl)
	local file_name = "gibsplat2/pose_cache/"..util.CRC(mdl)..".txt"

	file.CreateDir("gibsplat2")
	file.CreateDir("gibsplat2/pose_cache")

	file.Write(file_name, "") --creates file

	local F = file.Open(file_name, "wb", "DATA")

	F:WriteByte(VERSION)
	F:WriteShort(#mdl)
	F:Write(mdl)

	F:WriteShort(#RAGDOLL_POSE[mdl])
	for phys_bone, posang in pairs(RAGDOLL_POSE[mdl]) do
		F:WriteShort(phys_bone)
		WriteVector(F, posang.pos)
		WriteAngle(F, posang.ang)
	end

	F:Close()
end

local function LoadRagdollPoses()
	for _, file_name in pairs(file.Find("gibsplat2/pose_cache/*.txt", "DATA")) do
		local F = file.Open("gibsplat2/pose_cache/"..file_name, "rb", "DATA")

		if (F:ReadByte() != VERSION) then
			continue
		end

		local mdl = F:Read(F:ReadShort())

		RAGDOLL_POSE[mdl] = {}

		local num_entries = F:ReadShort()

		for entry_index = 1, num_entries do
			local phys_bone = F:ReadShort()
			local pos = ReadVector(F)
			local ang = ReadAngle(F)
			RAGDOLL_POSE[mdl][phys_bone] = {
				pos = pos,
				ang = ang
			}
		end
	end
end

LoadRagdollPoses()

local RESTORE_POSE = {}

local function PutInRagdollPose(self)
	local mdl = self:GetModel()
	local pose = RAGDOLL_POSE[mdl]
	if !pose then
		pose = {}
		local seq = self:LookupSequence("ragdoll")
		local temp
		--Ugly hack because not all ragdoll spawn in the correct pose
		if (seq == 0) then
			temp = ents.Create("prop_ragdoll")
			temp:SetModel(mdl)
			temp:Spawn()
		else
			temp = ents.Create("prop_physics")
			temp:SetModel(mdl)	
			temp:Spawn()
			temp:ResetSequence(-2)
			temp:SetCycle(0)

			for pose_param = 0, temp:GetNumPoseParameters() - 1 do
				local min, max = temp:GetPoseParameterRange(pose_param)
				--temp:SetPoseParameter(temp:GetPoseParameterName(pose_param), (min + max) / 2)
			end
		end

		--This forces temp to setup its bone
		local meme = ents.Create("prop_physics")
		meme:FollowBone(temp, 0)
		meme:Remove()
						
		for phys_bone = 0, self:GetPhysicsObjectCount() - 1 do
			local bone = temp:TranslatePhysBoneToBone(phys_bone)
			local matrix = temp:GetBoneMatrix(bone)
			local pos, ang = matrix:GetTranslation(), matrix:GetAngles()--temp:GetBonePosition(bone)
			
			pose[phys_bone] = {
				pos = pos,
				ang = ang
			}
		end

		temp:Remove()
		RAGDOLL_POSE[mdl] = pose
	end

	for phys_bone = 0, self:GetPhysicsObjectCount()-1 do
		local posang = pose[phys_bone]
		local phys = self:GetPhysicsObjectNum(phys_bone)
		RESTORE_POSE[phys_bone] = {
			pos = phys:GetPos(),
			ang = phys:GetAngles()
		}
		phys:SetPos(posang.pos)
		phys:SetAngles(posang.ang)
	end
end

local function RestorePose(self)
	for phys_bone = 0, self:GetPhysicsObjectCount()-1 do
		local posang = RESTORE_POSE[phys_bone]
		local phys = self:GetPhysicsObjectNum(phys_bone)		
		phys:SetPos(posang.pos)
		phys:SetAngles(posang.ang)
		--phys:EnableMotion(false)
		RESTORE_POSE[phys_bone] = nil
	end
end

local function GetClosestPhys(self, pos, target_phys_bone)
	local bone = 0
	local dist = math.huge

	local target_bone = target_phys_bone and self:TranslatePhysBoneToBone(target_phys_bone)

	for phys_bone = 0, self:GetPhysicsObjectCount() - 1 do
		local bone = self:TranslatePhysBoneToBone(phys_bone)
		local is_conn = target_phys_bone == nil and true
		if !is_conn then			
			local parent_bone = self:GetBoneParent(bone)
			if parent_bone then
				local parent_phys_bone = self:TranslateBoneToPhysBone(parent_bone)
				if (parent_phys_bone == target_phys_bone) then
					is_conn = true
				end
			end
			if !is_conn then
				for _, child_bone in pairs(self:GetChildBones(target_bone)) do
					local child_phys_bone = self:TranslateBoneToPhysBone(child_bone)
					if (child_phys_bone == phys_bone) then
						is_conn = true
						break
					end
				end
			end
		end	

		if is_conn then	
			local bone_pos = self:GetBoneMatrix(bone):GetTranslation()
			local d = bone_pos:DistToSqr(pos)
			if d < dist then
				dist = d
				bone = i			
			end
		end
	end

	return bone
end

local AXIS_X 	= 1
local AXIS_Y	= 2
local AXIS_Z	= 3

local function IsSharp(ent)
	local min, max = ent:GetCollisionBounds()

	if (max.x - min.x < 5) then
		return AXIS_X
	elseif (max.y - min.y < 5) then
		return AXIS_Y
	elseif (max.z - min.z < 5) then
		return AXIS_Z
	end	
end

local ENTITY = FindMetaTable("Entity")

function ENTITY:GS2IsDismembered(phys_bone)
	return bit.band(self:GetNWInt("GS2DisMask", 0), bit.lshift(1, phys_bone)) != 0
end

function ENTITY:GS2IsGibbed(phys_bone)
	return bit.band(self:GetNWInt("GS2GibMask", 0), bit.lshift(1, phys_bone)) != 0
end

function ENTITY:GS2GetClosestPhysBone(pos, target_phys_bone)
	local closest_bone = 0
	local dist = math.huge

	local target_bone = target_phys_bone and self:TranslatePhysBoneToBone(target_phys_bone)

	for phys_bone = 0, self:GetPhysicsObjectCount() - 1 do
		local bone = self:TranslatePhysBoneToBone(phys_bone)
		local is_conn = target_phys_bone == nil and true
		if !is_conn then			
			local parent_bone = self:GetBoneParent(bone)
			if parent_bone then
				local parent_phys_bone = self:TranslateBoneToPhysBone(parent_bone)
				if (parent_phys_bone == target_phys_bone) then
					is_conn = true
				end
			end
			if !is_conn then
				for _, child_bone in pairs(self:GetChildBones(target_bone)) do
					local child_phys_bone = self:TranslateBoneToPhysBone(child_bone)
					if (child_phys_bone == phys_bone) then
						is_conn = true
						break
					end
				end
			end
		end	

		if is_conn then	
			local bone_pos = self:GetBoneMatrix(bone):GetTranslation()
			local d = bone_pos:DistToSqr(pos)
			if d < dist then
				dist = d
				closest_bone = phys_bone			
			end
		end
		
	end

	return closest_bone
end

function ENTITY:GS2Dismember(phys_bone)
	if self.GS2Joints and self.GS2Joints[phys_bone] then
		SafeRemoveEntity(self.GS2Joints[phys_bone][1])	
	end
end

function ENTITY:GS2Gib(phys_bone, no_gibs)
	--Timer makes it run outside the PhysicsCollide hook to prevent physics crashes
	timer_Simple(0, function()
		if !IsValid(self) then return end

		local mask = self:GetNWInt("GS2GibMask", 0)
		local phys_mask = bit.lshift(1, phys_bone)
		if (bit.band(mask, phys_mask) != 0) then --Called twice, do nothing
			return
		end
		mask = bit.bor(mask, phys_mask)
		if mask == bit.lshift(1, self:GetPhysicsObjectCount())-1 then
			if self.GS2Gibs then
				for _, gib in pairs(self.GS2Gibs) do
					if IsValid(gib) then
						self:DontDeleteOnRemove(gib)
					end
				end
			end
			self:Remove()
			return
		end
		self:SetNWInt("GS2GibMask", mask)
		
		for _, const in pairs(self.GS2Joints[phys_bone]) do
			const.__nosound = true
			const.__noblood = no_gibs
			SafeRemoveEntity(const)			
		end
		
		--Detach any spectators
		if (phys_bone == 0) then
			for _, ply in pairs(player.GetHumans()) do
				if (ply:GetObserverTarget() == self) then
					ply:SpectateEntity()
				end
			end
		end

		for _, const in pairs(constraint.GetTable(self)) do
			if (const.Ent1 == self and const.Bone1 == phys_bone) then
				SafeRemoveEntity(const.Constraint)
			elseif (const.Ent2 == self and const.Bone2 == phys_bone) then
				SafeRemoveEntity(const.Constraint)
			end
		end

		self.GS2Limbs = self.GS2Limbs or {}

		if self.GS2Limbs[phys_bone] then
			SafeRemoveEntity(self.GS2Limbs[phys_bone])
			self.GS2Limbs[phys_bone] = nil
		end

		if !IsValid(self.GS2Limbs[0]) then
			local limb = ents.Create("gs2_limb")
			limb:SetBody(self)					
			limb:SetTargetBone(0)			
			limb:Spawn() 

			self:DeleteOnRemove(limb)
			self.GS2Limbs[0] = limb
		end

		for _, limb in pairs(self.GS2Limbs) do
			if IsValid(limb) then
				limb:SetGibMask(mask)
			end
		end

		local phys = self:GetPhysicsObjectNum(phys_bone)

		local pos = phys:GetPos()
		local ang = phys:GetAngles()
		local vel = phys:GetVelocity()
		
		if IsValid(self) and IsValid(phys) then
			self._GS2LastGibSound = self._GS2LastGibSound or 0
			if self._GS2LastGibSound + 1 < CurTime() then
				sound.Play(snd_gib, phys:GetPos(), 100, 100, 1)
				self._GS2LastGibSound = CurTime()
			end

			local bone = self:TranslatePhysBoneToBone(phys_bone)
			local bone_name = self:GetBoneName(bone)

			if !no_gibs then
				CreateGibs(self, phys_bone)

				local min, max = phys:GetAABB()

				local center = (min + max) / 2

				local EF = EffectData()
				EF:SetOrigin(center)
				EF:SetColor(self.__gs2bloodcolor or 0)
				util.Effect("BloodImpact", EF)
			end	
				
			phys:SetContents(CONTENTS_EMPTY)
			phys:EnableGravity(false)		
			phys:EnableCollisions(false)
			phys:EnableMotion(false)
			
			--Wait 1 second
			timer.Simple(1, function()
				if IsValid(phys) then
					phys:SetPos(vector_origin)
				end
			end)
		end
		
		self:CollisionRulesChanged()
		self:EnableCustomCollisions(true)
	end)
end

function ENTITY:MakeCustomRagdoll()
	local phys = self:GetPhysicsObject()
	if !IsValid(phys) then
		return
	end
	local phys_mat = phys:GetMaterial()
	self:SetNWString("GS2PhysMat", phys_mat)

	self.GS2LimbRelays = self.GS2LimbRelays or {}
	--Damaging ragdolls behaves wierdly when they're picked apart so use these instead
	for phys_bone = 0, self:GetPhysicsObjectCount()-1 do
		local phys = self:GetPhysicsObjectNum(phys_bone)
		local relay = ents.Create("gs2_limb_relay")	
		relay:SetTarget(self, phys_bone)
		relay:Spawn()
		self.GS2LimbRelays[phys_bone] = relay		
	end

	PutInRagdollPose(self)
	self:RemoveInternalConstraint()
	self:DrawShadow(false)

	local const_system = self.GS2ConstraintSystem

	if !const_system then
		const_system = ents.Create("phys_constraintsystem")
		const_system:SetKeyValue("additionaliterations", 4)
		const_system:Spawn()
		const_system:Activate()
		self.GS2ConstraintSystem = const_system
	end

	SetPhysConstraintSystem(const_system)

	self.GS2Joints = {}
	
	local CONST_INFO = GetModelConstraintInfo(self:GetModel())

	for _, part_info in pairs(CONST_INFO) do
		local phys_parent = self:GetPhysicsObjectNum(part_info.parent)
		local phys_child  = self:GetPhysicsObjectNum(part_info.child)
		
		local const_bs = ents.Create("phys_ballsocket")
		const_bs:SetPos(phys_child:GetPos())
		const_bs:SetPhysConstraintObjects(phys_parent, phys_child)
		const_bs:SetKeyValue("forcelimit", min(max_strength, max(min_strength:GetFloat(), strength_mul:GetFloat() * max(phys_parent:GetMass(), phys_child:GetMass()))))
		const_bs:Spawn()
		const_bs:Activate()

		local const_rc = ents.Create("phys_ragdollconstraint")
		const_rc:SetPos(phys_child:GetPos())
		const_rc:SetAngles(phys_child:GetAngles())
		const_rc:SetPhysConstraintObjects(phys_parent, phys_child)
		const_rc:SetKeyValue("spawnflags", 2) --free movement, let const_bs keep them together
		for key, value in pairs(part_info) do
			const_rc:SetKeyValue(key, value)
		end
		const_rc:Spawn()
		const_rc:Activate()

		const_bs:CallOnRemove("GS2Dismember", function() self:SetCustomCollisionCheck(true)
			SafeRemoveEntity(const_rc)
			if !IsValid(phys_child) then return end

			if !const_bs.__nosound then
				sound.Play(snd_dismember, phys_child:GetPos(), 75, 100, 1)
			end

			local phys_pos = phys_child:GetPos()
			local phys_ang = phys_child:GetAngles()

			local dir = phys_ang:Up() * 3

			if !const_bs.__noblood then
				local EF = EffectData()
				EF:SetOrigin(phys_pos)

				for i = 1, 3 do
					util.Decal("Blood", phys_pos + dir, phys_pos - dir)
					util.Decal("Blood", phys_pos - dir, phys_pos + dir)
					util.Effect("BloodImpact", EF)
				end
			end
			
			if !IsValid(self.GS2Skeleton) then
				local skel = ents.Create("gs2_skeleton")
				skel:SetBody(self)
				skel:Spawn()
				self.GS2Skeleton = skel
			end

			local mask = self:GetNWInt("GS2DisMask", 0)
			mask = bit.bor(mask, bit.lshift(1, part_info.child))
			self:SetNWInt("GS2DisMask", mask)		

			if !self:GS2IsGibbed(part_info.child) then
				local limb = ents.Create("gs2_limb")
				limb:SetBody(self)					
				limb:SetTargetBone(part_info.child)	
				limb:Spawn()
				limb:SetLightingOriginEntity(self.GS2LimbRelays[part_info.child])

				self:DeleteOnRemove(limb)

				self.GS2Limbs = self.GS2Limbs or {}
				self.GS2Limbs[part_info.child] = limb
			end

			if !IsValid(self.GS2Limbs[0]) then
				local limb = ents.Create("gs2_limb")
				limb:SetBody(self)					
				limb:SetTargetBone(0)			
				limb:Spawn()

				self:DeleteOnRemove(limb)

				self.GS2Limbs[0] = limb
			end

			for _, limb in pairs(self.GS2Limbs) do
				if IsValid(limb) then
					limb:SetDisMask(mask)	
				end			
			end
		end)

		self.GS2Joints[part_info.child] = self.GS2Joints[part_info.child] or {}
		table.insert(self.GS2Joints[part_info.child], const_bs)

		self.GS2Joints[part_info.parent] = self.GS2Joints[part_info.parent] or {}
		table.insert(self.GS2Joints[part_info.parent], const_bs)
	end

	SetPhysConstraintSystem(NULL)

	RestorePose(self)

	self:AddCallback("PhysicsCollide", function(self, data)
		local phys = data.PhysObject
		local phys_bone
		for i = 0, self:GetPhysicsObjectCount()-1 do
			if self:GetPhysicsObjectNum(i) == phys then
				phys_bone = i
				break
			end
		end

		if data.Speed > 1000 then
			local mask = self:GetNWInt("GS2GibMask", 0)
			if bit.band(mask, bit.lshift(1, phys_bone)) == 0 then
				--self:GS2Gib(phys_bone)
			end		
		elseif data.Speed > 100 then			
			local mask = self:GetNWInt("GS2DisMask", 0)
			if bit.band(mask, bit.lshift(1, phys_bone)) != 0 then			
				util.Decal(decals[phys_mat] or "", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				local EF = EffectData()
				EF:SetOrigin(data.HitPos)
				EF:SetColor(self.__gs2bloodcolor or 0)
				--util.Effect("BloodImpact", EF)	
			else			
				for _, part_info in pairs(CONST_INFO) do
					if part_info.parent == phys_bone and bit.band(mask, bit.lshift(1, part_info.child)) != 0 then
						util.Decal(decals[phys_mat] or "", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
						local EF = EffectData()
						EF:SetOrigin(data.HitPos)
						EF:SetColor(self.__gs2bloodcolor or 0)
						--util.Effect("BloodImpact", EF)
						break
					end
				end
			end
		end

		--Dismemberment from slicing

		local phys2 = data.HitObject

		local axis = IsSharp(data.HitEntity)

		if (axis and data.TheirOldVelocity:LengthSqr() > 100 * 100 and IsValid(phys2)) then
			local vel = phys2:GetVelocityAtPoint(data.HitPos)
			local ang = phys2:GetAngles()
			
			local dir
			if (axis == AXIS_X) then
				dir = ang:Forward()				
			elseif (axis == AXIS_Y) then
				dir = ang:Right()
			else
				dir = ang:Up()
			end

			local pre_speed = vel:Length()

			vel = vel - dir * dir:Dot(vel)	

			local post_speed = vel:Length()

			local ang_offset = math.acos(post_speed / pre_speed)

			if (ang_offset < 0.25 and math.random() > 0.5) then -- 0.25 ~= 15 degrees
				local closest = self:GS2GetClosestPhysBone(data.HitPos, phys_bone)
				if closest then
					self:GS2Dismember(closest)	
				end			
			end
		end
	end)

	self.__gs2custom = true
end