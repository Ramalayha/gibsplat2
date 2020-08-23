--sv_cheats 1;impulse 101;lua_openscript_cl gibsplat2/drawlimbs.lua;lua_openscript gibsplat2/buildcustomragdoll.lua

include("constraintinfo.lua")

util.AddNetworkString("GS2InstallDT")

local snd_dismember = Sound("physics/body/body_medium_break3.wav")
local snd_gib 		= Sound("physics/flesh/flesh_bloody_break.wav")

local GetModelConstraintInfo = GetModelConstraintInfo

local RAGDOLL_POSE = {}

local RESTORE_POSE = {}

local function PutInRagdollPose(self)
	local mdl = self:GetModel()
	local pose = RAGDOLL_POSE[mdl]
	if !pose then
		pose = {}
		local temp = ents.Create("prop_physics")
		temp:SetModel(mdl)
		temp:Spawn()
		temp:ResetSequence(temp:LookupSequence("ragdoll"))

		for phys_bone = 0, self:GetPhysicsObjectCount()-1 do
			local bone = temp:TranslatePhysBoneToBone(phys_bone)
			local pos, ang = temp:GetBonePosition(bone)
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
		RESTORE_POSE[phys_bone] = nil
	end
end

local function GetClosestPhys(self, pos)
	local bone = 0
	local dist = math.huge
	for i=0, self:GetPhysicsObjectCount()-1 do		
		local bpos = self:GetBonePosition(self:TranslatePhysBoneToBone(i))
		local d = bpos:DistToSqr(pos)
		if d < dist then
			dist = d
			bone = i			
		end
	end

	return bone
end

local ENTITY = FindMetaTable("Entity")

function ENTITY:GS2Gib(phys_bone)
	local mask = self:GetGS2GibMask() or 0--self:GetNWInt("GS2GibMask", 0)
	mask = bit.bor(mask, bit.lshift(1, phys_bone))
	if mask == bit.lshift(1, self:GetPhysicsObjectCount())-1 then
		self:Remove()
		return
	end
	self:SetGS2GibMask(mask)--self:SetNWInt("GS2GibMask", mask)

	for _, const in pairs(self.GS2Joints[phys_bone]) do
		const.__nosound = true
		SafeRemoveEntity(const)
	end
			
	local phys = self:GetPhysicsObjectNum(phys_bone)
	
	timer.Simple(0.1, function()
		if IsValid(self) and IsValid(phys) then
			self._GS2LastGibSound = self._GS2LastGibSound or 0
			if self._GS2LastGibSound < CurTime() + 1 then
				sound.Play(snd_gib, phys:GetPos(), 100, 100, 1)
				self._GS2LastGibSound = CurTime()
			end
			phys:EnableMotion(false)
			phys:EnableCollisions(false)
			phys:EnableGravity(false)
			phys:EnableDrag(false)	
			phys:SetPos(Vector(0,0,0))			
			local EF = EffectData()
			EF:SetOrigin(phys:GetPos())
			util.Effect("BloodImpact", EF)			
		end
	end)
end

function ENTITY:MakeCustomRagdoll()
	self:InstallDataTable()
	self:NetworkVar("Int", 0, "GS2DisMask")
	self:NetworkVar("Int", 1, "GS2GibMask")

	net.Start("GS2InstallDT")
		net.WriteEntity(self)
	net.Broadcast()

	PutInRagdollPose(self)
	self:EnableConstraints(false)
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
		const_bs:SetKeyValue("forcelimit", 5000)
		const_bs:Spawn()
		const_bs:Activate()

		local const_rc = ents.Create("phys_ragdollconstraint")
		const_rc:SetPos(phys_child:GetPos())
		const_rc:SetAngles(phys_child:GetAngles())
		const_rc:SetPhysConstraintObjects(phys_parent, phys_child)
		for key, value in pairs(part_info) do
			const_rc:SetKeyValue(key, value)
		end
		const_rc:Spawn()
		const_rc:Activate()

		const_bs:CallOnRemove("GS2Dismember", function()
			SafeRemoveEntity(const_rc)
			if !const_bs.__nosound and IsValid(phys_child) then
				sound.Play(snd_dismember, phys_child:GetPos(), 75, 100, 1)
			end
			
			local mask = self:GetGS2DisMask() or 0--self:GetNWInt("GS2DismemberMask", 0)
			mask = bit.bor(mask, bit.lshift(1, part_info.child))
			self:SetGS2DisMask(mask)--self:SetNWInt("GS2DismemberMask", mask)
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
			self:GS2Gib(phys_bone)		
		elseif data.Speed > 100 then			
			local mask = self:GetGS2DisMask() or 0--self:GetNWInt("GS2DismemberMask", 0)
			if bit.band(mask, bit.lshift(1, phys_bone)) != 0 then			
				util.Decal("Blood", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
				local EF = EffectData()
				EF:SetOrigin(data.HitPos)
				util.Effect("BloodImpact", EF)	
			else			
				for _, part_info in pairs(CONST_INFO) do
					if part_info.parent == phys_bone and bit.band(mask, bit.lshift(1, part_info.child)) != 0 then
						util.Decal("Blood", data.HitPos + data.HitNormal, data.HitPos - data.HitNormal)
						local EF = EffectData()
						EF:SetOrigin(data.HitPos)
						util.Effect("BloodImpact", EF)
						break
					end
				end
			end
		end
	end)

	self.__gs2custom = true
end

hook.Add("CreateEntityRagdoll","h",function(ent, doll)
	doll:MakeCustomRagdoll()
	if ent.__lastdmginfo and ent.__lastdmginfo:IsExplosionDamage() then
		timer.Simple(0, function()
			if IsValid(doll) then
				for phys_bone = 0, doll:GetPhysicsObjectCount()-1 do
					if math.random() > 0.7 then
						doll:GS2Gib(phys_bone)
					end
				end
			end	
		end)
	end
end)

hook.Add("EntityTakeDamage", "h", function(ent, dmginfo)
	if ent.__gs2custom and ent:GetClass() == "prop_ragdoll" then		
		if dmginfo:GetDamage() >= 500 and dmginfo:IsDamageType(DMG_CRUSH) then
			local phys_bone = GetClosestPhys(ent, dmginfo:GetDamagePosition())
			local mask = ent:GetGS2DisMask() or 0--ent:GetNWInt("GS2GibMask", 0)
			if bit.band(mask, bit.lshift(1, phys_bone)) == 0 then
				ent:GS2Gib(phys_bone)
			end
		end
	elseif ent:IsNPC() then
		ent.__lastdmginfo = dmginfo
	end
end)