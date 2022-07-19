include("shared.lua")

local gib_chance = GetConVar("gs2_gib_chance")
local health_multiplier = GetConVar("gs2_health_multiplier")

local blood_colors = {
	flesh = BLOOD_COLOR_RED,
	zombieflesh = BLOOD_COLOR_RED,
	alienflesh = BLOOD_COLOR_YELLOW,
	antlion = BLOOD_COLOR_YELLOW
}

function ENT:Initialize()
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	self.TargetPhys = phys

	self.health = health_multiplier:GetFloat() * phys:GetVolume() / 15 --seems to be a good number

	self:PhysicsInitBox(phys:GetAABB())
	
	local phys0 = ent:GetPhysicsObjectNum(0)

	self.MassMultiplier = phys:GetMass() / phys0:GetMass()

	self:SetNotSolid(true)
	self:SetMoveType(MOVETYPE_NONE)	
	self:SetCustomCollisionCheck(true)
	
	self:DrawShadow(false)

	self:Think() --update position
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:SetTarget(ent, phys_bone)
	self.TargetEntity = ent
	self.TargetPhysBone = phys_bone
end

function ENT:Think()
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	if (!IsValid(ent) or ent:GS2IsGibbed(phys_bone)) then
		return self:Remove()
	end

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	if phys:GetPos():Length() > 100000 then 
		print("UH OH",phys:GetPos())
	else
		self:SetPos(phys:GetPos())
		self:SetAngles(phys:GetAngles())
	end
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

local function IsKindaBullet(dmginfo)
	return 	dmginfo:IsBulletDamage() or 
			dmginfo:IsDamageType(DMG_CLUB) or 
			dmginfo:IsDamageType(DMG_ENERGYBEAM) or 
			dmginfo:IsDamageType(DMG_NEVERGIB) or --crossbow
			dmginfo:IsDamageType(DMG_SNIPER)
			--dmginfo:IsDamageType(DMG_BUCKSHOT) --shotgun has unreliable hit detection
end



function ENT:OnTakeDamage(dmginfo)
	local ent = self.TargetEntity
	local phys_bone = self.TargetPhysBone

	local phys = ent:GetPhysicsObjectNum(phys_bone)
	
	local dmg = dmginfo:GetDamage()
	local dmg_pos = dmginfo:GetDamagePosition()
	local dmg_force = dmginfo:GetDamageForce()
	
	if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
		ent:GS2Gib(phys_bone)
	elseif dmginfo:IsExplosionDamage() or dmginfo:IsDamageType(DMG_SONIC) then		
		local forced = false
		if phys_bone == 0 or (ent:GS2IsDismembered(phys_bone) and table.Count(ent.GS2Joints[phys_bone]) == 0) then
			dmginfo:SetDamageForce(dmg_force * self.MassMultiplier)
			phys:ApplyForceOffset(dmg_force, dmg_pos)
			forced = true
		end
		if self.health - dmg <= 0 then
			--self.health = self.health - math.Rand(0, dmg)	
			self.health = math.random() < gib_chance:GetFloat() and 0 or math.Rand(1, self.health / 2) --chance not to gib for more corpse variety
			if self.health == 0 then
				if !forced then
					dmginfo:SetDamageForce(dmg_force * self.MassMultiplier)
					phys:ApplyForceOffset(dmg_force, dmg_pos)
				end
				ent:GS2Gib(phys_bone, false, true)
				return
			end
		end
	elseif dmginfo:IsDamageType(DMG_CRUSH) then			
		local att = dmginfo:GetAttacker()
		local axis = IsSharp(att)
		if axis then
			local phys = att:GetPhysicsObject()
			if IsValid(phys) then
				local vel = phys:GetVelocityAtPoint(dmg_pos)
				local ang = phys:GetAngles()
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
					ent:GS2Dismember(phys_bone)
				end
			end
		else
			if (!att:IsPlayer() and dmg >= 100) then
				ent:GS2Gib(phys_bone)
			end
		end
	elseif dmginfo:IsDamageType(DMG_SLASH) then		
		self.health = self.health - dmg
		if !ent:GS2IsDismembered(phys_bone) then
			ent:GS2Dismember(phys_bone)	
		end
	elseif IsKindaBullet(dmginfo) then		
		self.health = self.health - dmg
		
		phys:ApplyForceOffset(dmg_force, dmg_pos)

		local blood_color = blood_colors[phys:GetMaterial()]
		if blood_color then 					
			local hole = ents.Create("gs2_bullethole")
			hole:SetBody(ent)
			hole:SetTargetBone(phys_bone)			
			hole:SetPos(dmg_pos)					
			hole:Spawn()
			
			local pos = phys:GetPos()
			local ang = phys:GetAngles()

			local norm = ang:Forward()

			local hitpos = pos + norm * norm:Dot(dmg_pos - pos)

			local lpos, lang = WorldToLocal(dmg_pos, (hitpos - dmg_pos):Angle(), pos, ang)

			local EF = EffectData()
			EF:SetEntity(ent)
			EF:SetOrigin(lpos)		
			EF:SetAngles(lang)
			EF:SetHitBox(ent:TranslatePhysBoneToBone(phys_bone))
			EF:SetColor(blood_color)
			EF:SetScale(0.1)
			util.Effect("gs2_bloodspray", EF)

			EF:SetOrigin(hitpos)
			util.Effect("BloodImpact", EF)
		end		
	elseif dmginfo:IsDamageType(DMG_DISSOLVE) then			
		ent:SetCollisionGroup(COLLISION_GROUP_NONE)

		local bone = ent:TranslatePhysBoneToBone(phys_bone)

		local mask = ent:GetNWInt("GS2DisMask")
		
		local to_dissolve = {}

		local parent = bone

		repeat				
			local phys_bone_parent = ent:TranslateBoneToPhysBone(parent)
			table.insert(to_dissolve, phys_bone_parent)
			if (bit.band(mask, bit.lshift(1, phys_bone_parent)) != 0) then
				break
			end
			parent = ent:GetBoneParent(parent)
		until (parent == -1)

		for phys_bone2 = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys2 = ent:GetPhysicsObjectNum(phys_bone2)
			if (phys_bone2 != phys_bone) then
				local bone2 = ent:TranslatePhysBoneToBone(phys_bone2)
				local parent = bone2
				repeat					
					local phys_bone_parent = ent:TranslateBoneToPhysBone(parent)
					if (phys_bone_parent == phys_bone or table.HasValue(to_dissolve, phys_bone_parent)) then
						break
					elseif (bit.band(mask, bit.lshift(1, phys_bone_parent)) != 0) then
						parent = -1
						break
					end				
					parent = ent:GetBoneParent(parent)			
				until (parent == -1)

				if (parent == -1) then				
					phys2:EnableGravity(true)
					phys2:SetDragCoefficient(0)
					continue
				end
			end	

			phys2:EnableGravity(false)
			phys2:SetDragCoefficient(100)
			table.insert(to_dissolve, phys_bone2)				
		end

		local mask = 0

		for _, phys_bone in pairs(to_dissolve) do
			mask = bit.bor(mask, bit.lshift(1, phys_bone))
			local limb = ent.GS2Limbs[phys_bone]
			if IsValid(limb) then
				limb.dissolving = CurTime()
				local name = "gs2_memename"..limb:EntIndex()
				limb:SetName(name)
				local diss = ents.Create("env_entity_dissolver")
				diss:Spawn()			
				diss:Fire("Dissolve", name)
				diss:SetParent(limb)
			end
		end

		net.Start("GS2Dissolve")
		net.WriteEntity(ent)
		net.WriteFloat(CurTime())
		net.WriteUInt(mask, 32)
		net.Broadcast()

		timer.Simple(2, function()
			if IsValid(ent) then
				for _, phys_bone in pairs(to_dissolve) do
					ent:GS2Gib(phys_bone, true)
				end
			end
		end)

		for _, diss in pairs(ents.FindByClass("env_entity_dissolver")) do
			if (diss:GetMoveParent() == ent) then
				--[[for k,v in pairs(diss:GetSaveTable()) do
					if k:find("Fade") then
						print(k,v)
					end
				end]]
				diss:Remove()	
				return true
			end
		end
	end

	if self.health <= 0 then
		ent:GS2Gib(phys_bone, false, true)
	end
	/*	
	
	elseif dmginfo:IsDamageType(DMG_CRUSH) then			
		local att = dmginfo:GetAttacker()
		local axis = IsSharp(att)
		if axis then
			local phys = att:GetPhysicsObject()
			if IsValid(phys) then
				local vel = phys:GetVelocityAtPoint(dmg_pos)
				local ang = phys:GetAngles()
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
					ent:GS2Dismember(phys_bone)
				end
			end
		else
			if (!att:IsPlayer() and dmg >= 100) then
				ent:GS2Gib(phys_bone)
			end
		end
	elseif dmginfo:IsDamageType(DMG_SLASH) then
		if ShouldGib(dmginfo) then
			ent:GS2Gib(phys_bone, false, true)
		else
			ent:GS2Dismember(phys_bone)	
		end
	elseif IsKindaBullet(dmginfo) then
		ent.GS2LimbHealth[phys_bone] = ent.GS2LimbHealth[phys_bone] - dmginfo:GetDamage()

		if ent.GS2LimbHealth[phys_bone] <= 0 then			
			ent:GS2Gib(phys_bone, false, true)
			return
		end
		if ShouldGib(dmginfo) then
			ent:GS2Gib(phys_bone, false, true)
		else
			local blood_color = blood_colors[phys:GetMaterial()]
			if blood_color then 					
				local hole = ents.Create("gs2_bullethole")
				hole:SetBody(ent)
				hole:SetTargetBone(phys_bone)			
				hole:SetPos(dmg_pos)					
				hole:Spawn()
				
				local pos = phys:GetPos()
				local ang = phys:GetAngles()

				local norm = ang:Forward()

				local hitpos = pos + norm * norm:Dot(dmg_pos - pos)

				local lpos, lang = WorldToLocal(dmg_pos, (hitpos - dmg_pos):Angle(), pos, ang)

				local EF = EffectData()
				EF:SetEntity(ent)
				EF:SetOrigin(lpos)		
				EF:SetAngles(lang)
				EF:SetHitBox(ent:TranslatePhysBoneToBone(phys_bone))
				EF:SetColor(blood_color)
				EF:SetScale(0.1)
				util.Effect("gs2_bloodspray", EF)

				EF:SetOrigin(hitpos)
				util.Effect("BloodImpact", EF)
			end
		end				
	end*/
end

local function ShouldCollide(ent1, ent2)
	if (ent1:GetClass() == "gs2_limb_relay") then
		return ent2:GetClass():find("^trigger_")
	end
end