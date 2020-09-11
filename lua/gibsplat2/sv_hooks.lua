util.AddNetworkString("GS2Dissolve")

local enabled 		= CreateConVar("gs2_enabled", 1)
local gib_chance 	= CreateConVar("gs2_gib_chance", 0.3)

local ang_zero = Angle(0, 0, 0)

local HOOK_NAME = "GibSplat2"

hook.Add("CreateEntityRagdoll", HOOK_NAME, function(ent, doll)
	if !enabled:GetBool() then return end
	if !IsValid(doll) or !doll:IsRagdoll() or !IsValid(doll:GetPhysicsObjectNum(0)) then return end
	doll.__gs2bloodcolor = ent:GetBloodColor()
	doll:MakeCustomRagdoll()
	if ent.__forcegib then 
		local phys_bone = doll:GS2GetClosestPhysBone(ent.__forcegib)
		
		if phys_bone then
			doll:GS2Gib(phys_bone)
		end
	end
	if ent.__lastdmgpos then
		local dmg_pos = ent.__lastdmgpos
		local dmg_force = ent.__lastdmgforce
		local phys_count = doll:GetPhysicsObjectCount()

		doll:GetPhysicsObjectNum(0):ApplyForceOffset(-dmg_force, dmg_pos)

		dmg_force:Div(phys_count)

		for phys_bone = 0, phys_count-1 do
			local phys = doll:GetPhysicsObjectNum(phys_bone)
			phys:ApplyForceOffset(dmg_force, dmg_pos)
		end

		timer.Simple(0, function()
			if IsValid(doll) then
				for phys_bone = 0, doll:GetPhysicsObjectCount()-1 do
					if (math.random() < gib_chance:GetFloat()) then
						doll:GS2Gib(phys_bone)
					end
				end
			end	
		end)
	end
end)

hook.Add("SetupPlayerVisibility", HOOK_NAME, function(ply)
	if !enabled:GetBool() then return end
	for _, doll in pairs(ents.FindByClass("prop_ragdoll")) do
		if (doll:GetNWInt("GS2GibMask", 0) != 0) then
			for phys_bone = 0, doll:GetPhysicsObjectCount()-1 do
				local phys = doll:GetPhysicsObjectNum(phys_bone)
				AddOriginToPVS(phys:GetPos())
			end
		end
	end
end)

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
end

local function ShouldGib(dmginfo)
	local dmg = dmginfo:GetDamage()

	local gib_chance = math.min(0.95, 6/dmg)

	return math.random() > gib_chance	
end

hook.Add("EntityTakeDamage", HOOK_NAME, function(ent, dmginfo)
	if !enabled:GetBool() then return end
	local dmg = dmginfo:GetDamage()
	local dmg_pos = dmginfo:GetDamagePosition()
	local dmg_force = dmginfo:GetDamageForce()

	if ent.__gs2custom and ent:IsRagdoll() then
		local phys_bone = ent:GS2GetClosestPhysBone(dmg_pos)
		if !phys_bone then
			return
		end
		if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
			ent:GS2Gib(phys_bone)
		elseif dmginfo:IsExplosionDamage() then
			return true	--Let relay deal with this instead
		elseif dmginfo:IsDamageType(DMG_DISSOLVE) then
			--TODO: particle effects
			ent:SetCollisionGroup(COLLISION_GROUP_NONE)

			local pbones = {}

			local bone = ent:TranslatePhysBoneToBone(phys_bone)

			repeat
				table.insert(pbones, bone)
				local phys_bone = ent:TranslateBoneToPhysBone(bone)
				local mask = ent:GetNWInt("GS2DisMask")
				if (bit.band(mask, bit.lshift(1, phys_bone)) != 0) then
					break
				end				
				bone = ent:GetBoneParent(bone)
			until (bone == -1)
			
			local to_dissolve = {}

			for phys_bone2 = 0, ent:GetPhysicsObjectCount() - 1 do
				local phys2 = ent:GetPhysicsObjectNum(phys_bone2)
				local bone2 = ent:TranslatePhysBoneToBone(phys_bone2)
				local parent = bone2
				repeat
					if table.HasValue(pbones, parent) then
						break
					end
					parent = ent:GetBoneParent(parent)
				until (parent == -1)

				if (parent == -1) then					
					phys2:EnableGravity(true)
					phys2:SetDragCoefficient(0)
				else					
					phys2:EnableGravity(false)
					phys2:SetDragCoefficient(100)
					table.insert(to_dissolve, phys_bone2)
				end
			end

			local mask = 0

			for _, phys_bone in pairs(to_dissolve) do
				mask = bit.bor(mask, bit.lshift(1, phys_bone))
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
				if (dmg >= 100) then
					ent:GS2Gib(phys_bone, dmginfo)
				end
			end
		elseif dmginfo:IsDamageType(DMG_SLASH) then
			if ShouldGib(dmginfo) then
				ent:GS2Gib(phys_bone)
			else
				ent:GS2Dismember(phys_bone)	
			end
		elseif IsKindaBullet(dmginfo) then
			local phys = ent:GetPhysicsObjectNum(phys_bone)
			local lpos, lang = WorldToLocal(dmginfo:GetDamagePosition(), ang_zero, phys:GetPos(), phys:GetAngles())

			--[[local hole = ents.Create("gs2_bullethole")
			hole:SetBody(ent)
			hole:SetTargetBone(phys_bone)
			hole:SetLocalPos(lpos)
			hole:SetLocalAng(lang)
			hole:Spawn()]]
			
			if ShouldGib(dmginfo) then
				ent:GS2Gib(phys_bone)
			end		
		end--else
			local t = dmginfo:GetDamageType() --print(dmginfo:GetDamage())
			for k,v in pairs(_G) do
				if k:find("^DMG_") and bit.band(v,t) != 0 then
					--print(k)
				end
			end
		--end
	elseif ent:IsNPC() then
		if dmginfo:IsExplosionDamage() then
			ent.__lastdmgpos = dmginfo:GetDamagePosition()
			ent.__lastdmgforce = dmginfo:GetDamageForce()
		elseif IsKindaBullet(dmginfo) then
			if ShouldGib(dmginfo) then
				ent.__forcegib = dmg_pos
			end
		end
	end
end)

hook.Add("OnEntityCreated", HOOK_NAME, function(ent)
	if !enabled:GetBool() then return end
	if ent:IsRagdoll() then
		timer.Simple(0, function()
			if (IsValid(ent) and !ent.__gs2custom) then
				ent:MakeCustomRagdoll()
			end
		end)
	end
end)

/*hook.Add("ShouldCollide", HOOK_NAME, function(ent1, ent2)
	if !enabled:GetBool() then return end
	if (ent1:GetClass() == "gs2_gib") then
		if (ent2:GetClass() == "gs2_gib") then
			return false
		end
		if ent2:IsRagdoll() then
			return false
		end
		if ent2:IsPlayer() then
			--return false
		end
	elseif (ent2:GetClass() == "gs2_gib") then
		if (ent1:GetClass() == "gs2_gib") then
			return false
		end
		if ent1:IsRagdoll() then
			return false
		end
		if ent1:IsPlayer() then
			--return false
		end
	end
end)*/