--sv_cheats 1;god;impulse 101;lua_openscript gs2.lua

local VERSION = 3

local HOOK_NAME = "GibSplat2"

local min_strength 	= CreateConVar("gs2_min_constraint_strength", 4000, FCVAR_ARCHIVE)
local max_strength 	= CreateConVar("gs2_max_constraint_strength", 15000, FCVAR_ARCHIVE)
local strength_mul 	= CreateConVar("gs2_constraint_strength_multiplier", 250, FCVAR_ARCHIVE)
local less_limbs	= CreateConVar("gs2_less_limbs", 0, FCVAR_ARCHIVE)
local gib_chance 	= CreateConVar("gs2_gib_chance", 0.15, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))
local pull_limb		= CreateConVar("gs2_pull_limb", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED))

local snd_dismember = Sound("physics/body/body_medium_break2.wav")
local snd_gib 		= Sound("physics/flesh/flesh_bloody_break.wav")
local snd_snap = Sound("physics/body/body_medium_break3.wav")

local decals = {
	flesh = "Blood",
	zombieflesh = "Blood",
	alienflesh = "YellowBlood",
	antlion = "YellowBlood"
}

local blood_colors = {
	flesh = BLOOD_COLOR_RED,
	zombieflesh = BLOOD_COLOR_RED,
	alienflesh = BLOOD_COLOR_YELLOW,
	antlion = BLOOD_COLOR_YELLOW
}

local text = file.Read("materials/gibsplat2/skeletons.vmt", "GAME")

local skeleton_parts = util.KeyValuesToTable(text or "").skeleton_parts or {}

local CreateGibs = CreateGibs
local SetPhysConstraintSystem = SetPhysConstraintSystem
local SafeRemoveEntity = SafeRemoveEntity
local SafeRemoveEntityDelayed = SafeRemoveEntityDelayed
local WorldToLocal = WorldToLocal
local CurTime = CurTime
local GetModelConstraintInfo = GetModelConstraintInfo
local IsValid = IsValid
local EffectData = EffectData
local pairs = pairs
local LocalToWorld = LocalToWorld

local ents_Create = ents.Create

local constraint_GetTable = constraint.GetTable

local math_min = math.min
local math_max = math.max
local math_random = math.random
local math_acos = math.acos

local table_insert = table.insert

local player_GetHumans = player.GetHumans

local bit_lshift = bit.lshift
local bit_bor = bit.bor
local bit_band = bit.band

local sound_Play = sound.Play

local timer_Simple = timer.Simple

local ang_zero = Angle(0, 0, 0)
local ang_180 = Angle(180, 0, 0)

local oob_pos = Vector(-16383, 0, 0) * 0.5

local RAGDOLL_POSE = {}

local RESTORE_POSE = {}

function PutInRagdollPose(self)
	local mdl = self:GetModel()
	local pose = RAGDOLL_POSE[mdl]
	if !pose then
		pose = {}
		local temp = ents_Create("prop_physics")
		temp:SetModel(mdl)	
		temp:Spawn()
		temp:ResetSequence(-2)
		temp:SetCycle(0)

		for pose_param = 0, temp:GetNumPoseParameters() - 1 do
			local min, max = temp:GetPoseParameterRange(pose_param)
			temp:SetPoseParameter(temp:GetPoseParameterName(pose_param), (min + max) / 2)
		end		

		--This forces temp to setup its bone
		local meme = ents_Create("prop_physics")
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
		if !posang then
			RAGDOLL_POSE[mdl] = nil
			PutInRagdollPose(self)
			return
		end
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
	local dist = math_huge

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
			if (d < dist) then
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
	return bit_band(self:GetNWInt("GS2DisMask", 0), bit_lshift(1, phys_bone)) != 0
end

function ENTITY:GS2IsGibbed(phys_bone)
	return bit_band(self:GetNWInt("GS2GibMask", 0), bit_lshift(1, phys_bone)) != 0
end

local PCOLLIDE_CACHE = {}

local vec_max = Vector(3, 3, 3)
local vec_min = -vec_max

function ENTITY:GS2GetClosestPhysBone(pos, target_phys_bone, use_collides)
	local mdl = self:GetModel()
	local collides = PCOLLIDE_CACHE[mdl]
	if (!collides and use_collides) then
		PCOLLIDE_CACHE[mdl] = CreatePhysCollidesFromModel(mdl)
		collides = PCOLLIDE_CACHE[mdl]
	end

	local closest_bone
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
			--Vector, Vector, number PhysCollide:TraceBox( Vector origin, Angle angles, Vector rayStart, Vector rayEnd, Vector rayMins, Vector rayMaxs )
			local phys = self:GetPhysicsObjectNum(phys_bone)
			if (use_collides and collides) then
				local collide = collides[phys_bone + 1]				
				local phys_pos = phys:GetPos()
				local phys_ang = phys:GetAngles()
				local lpos = phys:WorldToLocal(pos)
				local hitpos, _, d = collide:TraceBox(phys_pos, phys_ang, pos, pos, vec_min, vec_max)
				if hitpos then					
					if (d < dist) then
						dist = d
						closest_bone = phys_bone	
					end
				end
			else
				local min, max = phys:GetAABB()
				local bone_pos = phys:LocalToWorld((min + max) * 0.5)--self:GetBoneMatrix(bone):GetTranslation()
				local d = bone_pos:DistToSqr(pos)
				if (d < dist) then
					dist = d
					closest_bone = phys_bone			
				end
			end
		end		
	end

	return closest_bone
end

function ENTITY:GS2Dismember(phys_bone)
	if (self.GS2Joints and self.GS2Joints[phys_bone]) then
		SafeRemoveEntity(self.GS2Joints[phys_bone][1])	
	end
end

local _ShouldGib = {}

local whitelist = {
	"flesh",
	"zombieflesh",
	"alienflesh",
	"antlion"
}

local function ShouldGib(phys_mat)
	if (_ShouldGib[phys_mat] == nil) then
		_ShouldGib[phys_mat] = table.HasValue(whitelist, phys_mat)
	end
	return _ShouldGib[phys_mat]
end

function ENTITY:GS2Gib(phys_bone, no_gibs, forcegib)
	if (!forcegib and (self:GS2IsGibbed(phys_bone) or (!no_gibs and math.random() > gib_chance:GetFloat()))) then return end
	local phys_mat = self:GetPhysicsObject():GetMaterial()
	local GibEffects = ShouldGib(phys_mat)
	if !GibEffects then return end
	SafeRemoveEntity(self.GS2Limbs[phys_bone])
	local relay = self.GS2LimbRelays[phys_bone]
	if IsValid(relay) then
		SafeRemoveEntity(relay)
		relay:SetParent()
	end
	self.GS2Limbs[phys_bone] = nil
	--Timer makes it run outside the PhysicsCollide hook to prevent physics crashes
	timer_Simple(0, function()
		if (!IsValid(self) or self:GS2IsGibbed(phys_bone)) then return end

		local mask = self:GetNWInt("GS2GibMask", 0)
		local phys_mask = bit_lshift(1, phys_bone)
		if self:GS2IsGibbed(phys_bone) then --Called twice, do nothing
			return
		end
		mask = bit_bor(mask, phys_mask)
		if (mask == bit_lshift(1, self:GetPhysicsObjectCount()) - 1) then
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
		
		if self.GS2Joints[phys_bone] then
			for _, const in pairs(self.GS2Joints[phys_bone]) do
				const.__nosound = true
				const.__noblood = no_gibs
				SafeRemoveEntity(const)			
			end
		end
		
		local spectators = {}

		--Detach any spectators
		if (phys_bone == 0) then
			for _, ply in pairs(player_GetHumans()) do
				if (ply:GetObserverTarget() == self) then
					ply:SpectateEntity(self.GS2LimbRelays[0])
					table.insert(spectators, ply)
				end
			end
		end

		for _, const in pairs(constraint_GetTable(self)) do
			if (const.Ent1 == self and const.Bone1 == phys_bone) then
				SafeRemoveEntity(const.Constraint)
			elseif (const.Ent2 == self and const.Bone2 == phys_bone) then
				SafeRemoveEntity(const.Constraint)
			end
		end
 		
		for _, limb in pairs(self.GS2Limbs) do
			if IsValid(limb) then
				limb:SetGibMask(mask)
			end
		end

		if (self.GS2BulletHoles and self.GS2BulletHoles[phys_bone]) then
			for _, hole in pairs(self.GS2BulletHoles[phys_bone]) do
				SafeRemoveEntity(hole)
			end
		end

		local phys = self:GetPhysicsObjectNum(phys_bone)
		
		if IsValid(phys) then
			local pos = phys:GetPos()
			local ang = phys:GetAngles()
			local vel = phys:GetVelocity()

			local blood_color = blood_colors[phys:GetMaterial()]

			self._GS2LastGibSound = self._GS2LastGibSound or 0
			if (!no_gibs and self._GS2LastGibSound + 1 < CurTime()) then
				sound_Play(snd_gib, phys:GetPos(), 100, 100, 1)
				self._GS2LastGibSound = CurTime()
			end

			local bone = self:TranslatePhysBoneToBone(phys_bone)
			local bone_name = self:GetBoneName(bone)

			if (!no_gibs and blood_color) then
				local gibs = CreateGibs(self, phys_bone, nil, nil, blood_color)

				if (gibs and #gibs > 0) then
					for _, ply in pairs(spectators) do
						ply:SpectateEntity(table.Random(gibs))
					end
				end

				local min, max = phys:GetAABB()
				
				local pos = phys:LocalToWorld((min + max) / 2)	
				local EF = EffectData()				
					EF:SetOrigin(pos)
					EF:SetColor(blood_color)						
				for i = 1, 5 do
					util.Effect("BloodImpact", EF)
				end			
			end	
				
			phys:SetContents(CONTENTS_EMPTY)
			phys:EnableGravity(false)		
			phys:EnableCollisions(false)
			phys:SetDragCoefficient(10)			
			phys:SetAngleDragCoefficient(math.huge)
			
			--Wait 1 second
			timer.Simple(1, function()
				if IsValid(phys) then					
					phys:EnableMotion(false)					
					phys:SetAngles(ang_zero)
					phys:SetPos(oob_pos)
					phys:SetVelocityInstantaneous(vector_origin)				
				end
			end)
		end

		local mdl = self:GetModel()

		if !pull_limb:GetBool() then			
			local CONST_INFO = GetModelConstraintInfo(mdl)

			for key, const in ipairs(CONST_INFO) do
				if (const.child == phys_bone or const.parent == phys_bone) then
					self:RemoveInternalConstraint(key)
					SafeRemoveEntity(self.GS2Joints[const.child])					
				end
			end
		end
		
		self:CollisionRulesChanged()
		self:EnableCustomCollisions(true)
	end)
end

function ENTITY:MakeCustomRagdoll()
	if self.__gs2custom then return end
	
	local phys = self:GetPhysicsObject()
	if !IsValid(phys) then
		return
	end

	self:SetCustomCollisionCheck(true)

	local phys_mat = phys:GetMaterial()
	self:SetNWString("GS2PhysMat", phys_mat)

	local GibEffects = ShouldGib(phys_mat)

	self.GS2LimbRelays = self.GS2LimbRelays or {}
	--Damaging ragdolls behaves wierdly when they're picked apart so use these instead
	for phys_bone = 0, self:GetPhysicsObjectCount()-1 do
		local phys = self:GetPhysicsObjectNum(phys_bone)
		local relay = ents_Create("gs2_limb_relay")	
		relay:SetTarget(self, phys_bone)
		relay:Spawn()
		self.GS2LimbRelays[phys_bone] = relay		
	end

	PutInRagdollPose(self)
	if pull_limb:GetBool() then
		self:RemoveInternalConstraint()
	end
	self:DrawShadow(false)
	
	self.GS2Joints = {}

	local mdl = self:GetModel()

	local CONST_INFO = GetModelConstraintInfo(mdl)
	
	self.GS2Joints.CONST_INFO = CONST_INFO

	local const_system = self.GS2ConstraintSystem

	if !const_system then
		const_system = ents_Create("phys_constraintsystem")
		const_system:SetKeyValue("additionaliterations", 4)
		const_system:Spawn()
		const_system:Activate()
		self.GS2ConstraintSystem = const_system
	end

	SetPhysConstraintSystem(const_system)
	
	local should_activate = pull_limb:GetBool()

	for _, part_info in pairs(CONST_INFO) do
		local phys_parent = self:GetPhysicsObjectNum(part_info.parent)
		local phys_child  = self:GetPhysicsObjectNum(part_info.child)
		
		local const_bs = ents_Create("phys_ballsocket")
		const_bs:SetPos(phys_child:GetPos())
		const_bs:SetPhysConstraintObjects(phys_parent, phys_child)
		const_bs:SetKeyValue("forcelimit", math_min(max_strength:GetFloat(), math_max(min_strength:GetFloat(), strength_mul:GetFloat() * 0.5 * math_max(phys_parent:GetMass(), phys_child:GetMass()))))
		const_bs:Spawn()
		if should_activate then
			const_bs:Activate()
		end
		
		local const_rc = ents_Create("phys_ragdollconstraint")
		const_rc:SetPos(phys_child:GetPos())
		const_rc:SetAngles(phys_child:GetAngles())
		const_rc:SetPhysConstraintObjects(phys_parent, phys_child)
		const_rc:SetKeyValue("spawnflags", 2) --free movement, let const_bs keep them together
		for key, value in pairs(part_info) do
			const_rc:SetKeyValue(key, value)
		end
		const_rc:Spawn()
		if should_activate then
			const_rc:Activate()
		end

		local body_type = GS2GetBodyType(mdl)
		local skel_parts = skeleton_parts[body_type]
		local bone_child = self:TranslatePhysBoneToBone(part_info.child)		
		local const_bs2
		if (skel_parts and skel_parts[self:GetBoneName(bone_child):lower()]) then			
			const_bs2 = ents_Create("phys_ballsocket") 
			const_bs2:SetPos(phys_child:GetPos())
			const_bs2:SetPhysConstraintObjects(phys_parent, phys_child)
			const_bs2:SetKeyValue("forcelimit", math_min(max_strength:GetFloat(), math_max(min_strength:GetFloat(), strength_mul:GetFloat() * math_max(phys_parent:GetMass(), phys_child:GetMass()))))
			const_bs2:Spawn()
			if should_activate then
				const_bs2:Activate()
			end

			local const_rc2 = ents_Create("phys_ragdollconstraint")
			const_rc2:SetPos(phys_child:GetPos())
			const_rc2:SetAngles(phys_child:GetAngles())
			const_rc2:SetPhysConstraintObjects(phys_parent, phys_child)
			const_rc2:SetKeyValue("spawnflags", 2) --free movement, let const_bs2 keep them together
			for key, value in pairs(part_info) do
				if key:find("^[xyz]min$") then
					const_rc2:SetKeyValue(key, value - 15)
				elseif key:find("^[xyz]max$") then
					const_rc2:SetKeyValue(key, value + 15)
				end
			end
			const_rc2:Spawn()
			if should_activate then
				const_rc2:Activate()
			end

			const_bs2:CallOnRemove("GS2Dismember2", function()			
				if (GibEffects and IsValid(self) and IsValid(phys_child)) then
					if (!IsValid(const_bs) or !const_bs.__nosound) then
						self._GS2LastGibSound = self._GS2LastGibSound or 0
						if (self._GS2LastGibSound + 1 < CurTime()) then
							sound_Play(snd_snap, phys_child:GetPos(), 75, 100, 1)
							self._GS2LastGibSound = CurTime()
						end					
					end
				end
				SafeRemoveEntity(const_bs)
				SafeRemoveEntity(const_rc2)				
			end)	
		end
				
		const_bs:CallOnRemove("GS2Dismember", function()
			SafeRemoveEntity(const_rc)
			if !IsValid(phys_child) or !IsValid(self) then return end
						
			local less = less_limbs:GetBool()

			if (GibEffects and IsValid(self) and !const_bs.__nosound) then
				self._GS2LastGibSound = self._GS2LastGibSound or 0
				if (self._GS2LastGibSound + 1 < CurTime()) then
					sound_Play(snd_dismember, phys_child:GetPos(), 75, 100, 1)
					self._GS2LastGibSound = CurTime()
				end
			end

			local phys_pos = phys_child:GetPos()
			local phys_ang = phys_child:GetAngles()

			local blood_color = blood_colors[phys_child:GetMaterial()]

			local dir = phys_ang:Up() * 3

			if (GibEffects and !const_bs.__noblood and blood_color) then
				local EF = EffectData()
				EF:SetOrigin(phys_pos)
				EF:SetColor(blood_color)

				util.Decal("Blood", phys_pos + dir, phys_pos - dir)
				util.Decal("Blood", phys_pos - dir, phys_pos + dir)
				for i = 1, 5 do
					util.Effect("BloodImpact", EF)
				end			
			end
			
			if !IsValid(self.GS2Skeleton) then
				local skel = ents_Create("gs2_skeleton")
				skel:SetBody(self)
				skel:Spawn()
				self.GS2Skeleton = skel
				self:DeleteOnRemove(skel)
			end

			local mask = self:GetNWInt("GS2DisMask", 0)
			mask = bit_bor(mask, bit_lshift(1, part_info.child))
			self:SetNWInt("GS2DisMask", mask)

			local dissolve

			local is_lonely = less

			if (less and !self:GS2IsGibbed(part_info.child)) then								
				for phys_bone = 0, self:GetPhysicsObjectCount() - 1 do
					local bone = self:TranslatePhysBoneToBone(phys_bone)
					if (!self:GS2IsDismembered(phys_bone) and self:TranslateBoneToPhysBone(self:GetBoneParent(bone)) == part_info.child) then
						is_lonely = false
						break
					end
				end
				if is_lonely then
					self:GS2Gib(part_info.child)
				end
			end			
			if (!is_lonely and !self:GS2IsGibbed(part_info.child)) then
				local limb = ents_Create("gs2_limb")
				limb:SetBody(self)					
				limb:SetTargetBone(part_info.child)
				limb:Spawn()
				limb:SetLightingOriginEntity(self.GS2LimbRelays[part_info.child])

				self:DeleteOnRemove(limb)

				self.GS2Limbs[part_info.child] = limb

				local bone = self:TranslatePhysBoneToBone(part_info.child)
				local parent = self:TranslatePhysBoneToBone(part_info.parent)

				repeat
					local phys_bone_parent = self:TranslateBoneToPhysBone(parent)
					local parent_limb = self.GS2Limbs[phys_bone_parent]
					if IsValid(parent_limb) then
						dissolve = parent_limb.dissolving
						break
					end
					parent = self:GetBoneParent(parent)
				until (parent == -1)

				if dissolve then
					limb.dissolving = dissolve
					local name = "gs2_memename"..limb:EntIndex()
					limb:SetName(name)
					local diss = ents_Create("env_entity_dissolver")
					diss:Spawn()			
					diss:Fire("Dissolve", name)
					diss:SetParent(limb)

					net.Start("GS2Dissolve")
					net.WriteEntity(ent)
					net.WriteFloat(dissolve)
					net.WriteUInt(bit_lshift(1, part_info.child), 32)
					net.Broadcast()

					SafeRemoveEntityDelayed(limb, dissolve + 2 - CurTime())
				elseif (GibEffects and blood_color) then
					local EF = EffectData()
					EF:SetEntity(self)
					EF:SetOrigin(vector_origin)		
					EF:SetAngles(ang_zero)
					EF:SetHitBox(bone)
					EF:SetColor(blood_color)
					EF:SetScale(phys_child:GetVolume() / 200)
					util.Effect("gs2_bloodspray", EF)
				end
			end

			if (less and !self:GS2IsGibbed(part_info.parent)) then				
				if (part_info.parent == 0 or self:GS2IsDismembered(part_info.parent)) then
					is_lonely = true									
					for phys_bone = 0, self:GetPhysicsObjectCount() - 1 do
						local bone = self:TranslatePhysBoneToBone(phys_bone)
						if (!self:GS2IsDismembered(phys_bone) and self:TranslateBoneToPhysBone(self:GetBoneParent(bone)) == part_info.parent) then
							is_lonely = false
							break
						end
					end
					if is_lonely then
						self:GS2Gib(part_info.parent)
					end
				end			
			elseif (GibEffects and !self:GS2IsGibbed(part_info.parent) and blood_color) then
				local pose = RAGDOLL_POSE[self:GetModel()]

				local pose_child = pose[part_info.child]
				local pose_parent = pose[part_info.parent]

				local lpos, lang = WorldToLocal(pose_child.pos, pose_child.ang, pose_parent.pos, pose_parent.ang)
				
				lang.p = lang.p + 180

				local EF = EffectData()
				EF:SetEntity(self)
				EF:SetOrigin(lpos * 0.7)		
				EF:SetAngles(lang)
				EF:SetHitBox(self:TranslatePhysBoneToBone(part_info.parent))
				EF:SetColor(blood_color)
				EF:SetScale(phys_parent:GetVolume() / 200)
				util.Effect("gs2_bloodspray", EF)

				--RestorePose(self)
			end

			for _, limb in pairs(self.GS2Limbs) do
				if IsValid(limb) then
					limb:SetDisMask(mask)	
				end			
			end
		end)

		self.GS2Joints[part_info.child] = self.GS2Joints[part_info.child] or {}
		table_insert(self.GS2Joints[part_info.child], const_bs2 or const_bs)

		self.GS2Joints[part_info.parent] = self.GS2Joints[part_info.parent] or {}
		table_insert(self.GS2Joints[part_info.parent], const_bs2 or const_bs)
	end
	
	local limb = ents_Create("gs2_limb")
	limb:SetBody(self)					
	limb:SetTargetBone(0)			
	limb:Spawn()

	self:DeleteOnRemove(limb)	
	self.GS2Limbs = {[0] = limb}

	SetPhysConstraintSystem(NULL)

	RestorePose(self)

	if GibEffects then
		self:AddCallback("PhysicsCollide", function(self, data)
			local phys = data.PhysObject
			local phys_bone
			for i = 0, self:GetPhysicsObjectCount()-1 do
				if (self:GetPhysicsObjectNum(i) == phys) then
					phys_bone = i
					break
				end
			end
			local speed = data.Speed
			if (speed > 1000 or (!data.HitEntity:IsWorld() and !data.HitEntity:IsPlayer() and data.HitEntity != self and phys:GetEnergy() == 0)) then --0 energy = jammed in something			
				self:GS2Gib(phys_bone)
				return
			end
			
			if (data.DeltaTime < 0.05) then
				return --Don't run decal code too often
			end

			if (speed > 100) then
				local blood_color = blood_colors[phys:GetMaterial()]		
				if self:GS2IsDismembered(phys_bone) then
					util.Decal(decals[phys_mat] or "", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
					if blood_color then
						local EF = EffectData()
						EF:SetOrigin(data.HitPos)
						EF:SetColor(blood_color)
						for i = 1, 5 do
							util.Effect("BloodImpact", EF)
						end
						EmitSound("Watermelon.Impact", data.HitPos, self.GS2LimbRelays[phys_bone]:EntIndex())
					end
				else	
					local do_effects = false
					if (speed > 500) then
						do_effects = true
					else
						for _, part_info in pairs(CONST_INFO) do
							if part_info.parent == phys_bone and self:GS2IsDismembered(part_info.child) then
								do_effects = true
								EmitSound("Watermelon.Impact", data.HitPos, self.GS2LimbRelays[phys_bone]:EntIndex())
								break
							end
						end
					end
					if do_effects then
						util.Decal(decals[phys_mat] or "", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
						if blood_color then
							local EF = EffectData()
							EF:SetOrigin(data.HitPos)
							EF:SetColor(blood_color)
							for i = 1, 5 do
								util.Effect("BloodImpact", EF)
							end
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

				local ang_offset = math_acos(post_speed / pre_speed)

				if (ang_offset < 0.25 and math_random() > 0.5) then -- 0.25 ~= 15 degrees
					local closest = self:GS2GetClosestPhysBone(data.HitPos, phys_bone)
					if closest then
						self:GS2Dismember(closest)	
					end			
				end
			end
		end)
	end

	self.__gs2custom = true
end

local enabled = GetConVar("gs2_enabled")

hook.Add("SetupPlayerVisibility", HOOK_NAME, function(ply)
	if !enabled:GetBool() then return end
	
	for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
		if (ent.__gs2custom and ent.GS2LimbRelays) then
			for _, relay in pairs(ent.GS2LimbRelays) do
				if IsValid(relay) then					
					if ply:TestPVS(relay:GetPos()) then
						for phys_bone = 0, ent:GetPhysicsObjectCount() - 1 do
							local phys = ent:GetPhysicsObjectNum(phys_bone)
							if IsValid(phys) then
								AddOriginToPVS(phys:GetPos())	
							end
						end	
						break										
					end
				end
			end
		end
	end
end)