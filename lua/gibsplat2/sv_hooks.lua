util.AddNetworkString("GS2Dissolve")

local enabled 			= GetConVar("gs2_enabled")
local player_ragdolls 	= GetConVar("gs2_player_ragdolls")
local default_ragdolls 	= GetConVar("gs2_default_ragdolls")

local ang_zero = Angle(0, 0, 0)

local blood_colors = {
	flesh = BLOOD_COLOR_RED,
	zombieflesh = BLOOD_COLOR_RED,
	alienflesh = BLOOD_COLOR_YELLOW,
	antlion = BLOOD_COLOR_YELLOW
}

local HOOK_NAME = "GibSplat2"

local function GS2CreateEntityRagdoll(ent, doll)
	if !IsValid(doll) or !doll:IsRagdoll() or !IsValid(doll:GetPhysicsObjectNum(0)) then return end
	doll:MakeCustomRagdoll()

	if ent.__forcegib then 
		local phys_bone = doll:GS2GetClosestPhysBone(ent.__forcegib, nil, true)
		
		if phys_bone then
			doll:GS2Gib(phys_bone, false, true)
		end
	end
	if (ent.__lastdmgpos and ent.__lastdmgtime == CurTime()) then
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
				local tr = {
					output = {},				
					start = dmgpos,
					ignoreworld = true
				}
				for phys_bone = 0, doll:GetPhysicsObjectCount() - 1 do
					doll:GS2Gib(phys_bone)

					if (math.random() < 0.3) then
						local phys = doll:GetPhysicsObjectNum(phys_bone)
						if IsValid(phys) then
							tr.endpos = phys:GetPos()
							
							util.TraceLine(tr)
							if tr.output.Hit then
								net.Start("GS2ApplyDecal")
									net.WriteEntity(doll)
									net.WriteString(phys:GetMaterial())
									net.WriteVector(tr.output.HitPos)
									net.WriteVector(-tr.output.HitNormal)
								net.Broadcast()
							end
						end
					end					
				end								
			end				
		end)
	end
	if ent.GS2Decals then
		for phys_bone, decals in pairs(ent.GS2Decals) do
			for _, pos in pairs(decals) do
				local hole = ents.Create("gs2_bullethole")
				hole:SetBody(doll)
				hole:SetTargetBone(phys_bone)			
				hole:SetPos(pos)					
				hole:Spawn()				
			end
		end		
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
			dmginfo:IsDamageType(DMG_SNIPER) or
			dmginfo:IsDamageType(DMG_BUCKSHOT) --this doesnt count as bullet damage for some reason
end

local gib_chance = GetConVar("gs2_gib_chance")

local function ShouldGib(dmginfo)
	local chance = gib_chance:GetFloat()
	if (chance >= 1) then
		return true
	elseif (chance <= 0) then
		return false
	end
	
	return math.random() < chance and math.random() < dmginfo:GetDamage() / 20
end

local function GS2EntityTakeDamage(ent, dmginfo)
	local dmg = dmginfo:GetDamage()
	local dmg_pos = dmginfo:GetDamagePosition()
	local dmg_force = dmginfo:GetDamageForce()

	if ent.__gs2custom and ent:IsRagdoll() then
		local phys_bone = ent:GS2GetClosestPhysBone(dmg_pos, nil, true)
		if !phys_bone then
			return
		end
		local phys = ent:GetPhysicsObjectNum(phys_bone)
		if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
			ent:GS2Gib(phys_bone)
		elseif dmginfo:IsExplosionDamage() then
			return true	--Let relay deal with this instead
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
		end
	elseif (ent:IsNPC() or ent:IsPlayer()) then
		if (dmginfo:IsDamageType(5) and dmginfo:GetDamage() > ent:Health()) then --5 = DMG_CRUSH | DMG_SLASH
			local dmg_type = dmginfo:GetDamageType() --Prevents zombie from cutting in half
			dmginfo:SetDamageType(bit.band(dmg_type, bit.bnot(DMG_SLASH)))			
		end
		if dmginfo:IsExplosionDamage() then
			ent.__lastdmgpos = dmginfo:GetDamagePosition()
			ent.__lastdmgforce = dmginfo:GetDamageForce()
			ent.__lastdmgtime = CurTime()
		elseif IsKindaBullet(dmginfo) then
			if ShouldGib(dmginfo) then
				ent.__forcegib = dmg_pos
			else
				ent.GS2Decals = ent.GS2Decals or {}
				local phys_bone = ent:GS2GetClosestPhysBone(dmg_pos)
				if (phys_bone) then
					ent.GS2Decals[phys_bone] = ent.GS2Decals[phys_bone] or {}
					table.insert(ent.GS2Decals[phys_bone], dmg_pos)
				end
			end
		else
			local att = dmginfo:GetAttacker()
			local is_heavy
			if IsValid(att) then
				local phys = att:GetPhysicsObject()
				if IsValid(phys) then
					is_heavy = phys:GetMass() >= 300 --this triggers zombie splitting to occur and we dont want that
				end
			end
			if (dmginfo:IsDamageType(DMG_CRUSH) and is_heavy and ent:GetClass():find("zombie")) then
				dmginfo:SetDamageType(DMG_GENERIC) --change damage type so zombies dont split
			end
		end
	end
end

local function GS2OnEntityCreated(ent)
	if ent:IsRagdoll() then
		timer.Simple(0, function()
			if (IsValid(ent) and !ent.__gs2custom) then
				ent:MakeCustomRagdoll()
			end
		end)
	end
end

local PLAYER = FindMetaTable("Player")

local oldCreateRagdoll = PLAYER.CreateRagdoll

local dolls = {}

local function CreateRagdoll(self)
	SafeRemoveEntity(dolls[self])

	local ragdoll = ents.Create("prop_ragdoll")
	ragdoll:SetModel(self:GetModel())
	ragdoll:SetPos(self:GetPos())
	ragdoll:SetAngles(self:GetAngles())
	ragdoll:Spawn()

	ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)

	ragdoll:SetSkin(self:GetSkin())

	for i = 0, self:GetNumBodyGroups() - 1 do
		ragdoll:SetBodygroup(i, self:GetBodygroup(i))
	end

	for i = 0, ragdoll:GetPhysicsObjectCount()-1 do
		local phys = ragdoll:GetPhysicsObjectNum(i)
		local bone = ragdoll:TranslatePhysBoneToBone(i)
		local matrix = self:GetBoneMatrix(bone)
		local pos, ang = matrix:GetTranslation(), matrix:GetAngles()--self:GetBonePosition(bone)
		phys:SetPos(pos)
		phys:SetAngles(ang)
		phys:SetVelocity(self:GetVelocity())
	end

	self:SpectateEntity(ragdoll)
	self:Spectate(OBS_MODE_CHASE)

	dolls[self] = ragdoll

	GS2CreateEntityRagdoll(self, ragdoll)
end

local oldGetRagdollEntity = PLAYER.GetRagdollEntity

local function GetRagdoll(self)
	return dolls[self] or NULL
end

local FL_PHYS = 8

local filter

local function FixTrigger(trigger)
	if trigger:GetClass():match("^trigger_") then
		timer.Simple(0, function()
			if !IsValid(trigger) then return end
			local spawnflags = trigger:GetInternalVariable("spawnflags")
			if (bit.band(spawnflags, FL_PHYS) != 0) then
				if !IsValid(filter) then
					filter = ents.Create("gs2_filter")
					filter:SetName("gs2_filter")
					filter:Spawn()
				end
				local current_filter = 	trigger:GetInternalVariable("m_hFilter")
				if (IsValid(current_filter) and current_filter != filter) then
					local new_filter = ents.Create("filter_multi")
					new_filter:SetKeyValue("FilterType", 0) --FILTER_AND
					new_filter:SetKeyValue("Filter01", "gs2_filter")
					new_filter:SetKeyValue("Filter02", current_filter:GetName())
					new_filter:Spawn()		
					trigger:SetSaveValue("m_hFilter", new_filter)		
				else
					trigger:SetSaveValue("m_hFilter", filter)
				end	
			end
		end)
	end
end

local function FixAllTriggers()	
	if IsValid(filter) then return end
	print("[GS2] Fixing triggers!")
	for _, trigger in pairs(ents.FindByClass("trigger_*")) do
		FixTrigger(trigger)
	end
end

if enabled:GetBool() then
	if player_ragdolls:GetBool() then
		PLAYER.CreateRagdoll = CreateRagdoll
		PLAYER.GetRagdollEntity = GetRagdoll
	end
	if default_ragdolls:GetBool() then
		hook.Add("CreateEntityRagdoll", HOOK_NAME, GS2CreateEntityRagdoll)
		hook.Add("OnEntityCreated", HOOK_NAME, GS2OnEntityCreated)		
	end
	hook.Add("EntityTakeDamage", HOOK_NAME, GS2EntityTakeDamage)
	hook.Add("OnEntityCreated", "GS2TriggerFix", FixTrigger)
end

cvars.AddChangeCallback("gs2_enabled", function(_, _, new)
 	if (new == "1") then
 		if player_ragdolls:GetBool() then
			PLAYER.CreateRagdoll = CreateRagdoll
			PLAYER.GetRagdollEntity = GetRagdoll
		end
		if default_ragdolls:GetBool() then
			hook.Add("CreateEntityRagdoll", HOOK_NAME, GS2CreateEntityRagdoll)
			hook.Add("OnEntityCreated", HOOK_NAME, GS2OnEntityCreated)
		end
		hook.Add("EntityTakeDamage", HOOK_NAME, GS2EntityTakeDamage)
		hook.Add("OnEntityCreated", "GS2TriggerFix", FixTrigger)
		FixAllTriggers()
	else
		PLAYER.CreateRagdoll = oldCreateRagdoll
		PLAYER.GetRagdollEntity = oldGetRagdollEntity
		hook.Remove("CreateEntityRagdoll", HOOK_NAME)
		hook.Remove("OnEntityCreated", HOOK_NAME)
		hook.Remove("EntityTakeDamage", HOOK_NAME)	
		hook.Remove("OnEntityCreated", "GS2TriggerFix")
	end
end)

cvars.AddChangeCallback("gs2_default_ragdolls", function(_, _, new)
	if !enabled:GetBool() then return end

	if (new == "1") then
		hook.Add("CreateEntityRagdoll", HOOK_NAME, GS2CreateEntityRagdoll)
		hook.Add("OnEntityCreated", HOOK_NAME, GS2OnEntityCreated)
	else
		hook.Remove("CreateEntityRagdoll", HOOK_NAME)
		hook.Remove("OnEntityCreated", HOOK_NAME)
	end
end)

cvars.AddChangeCallback("gs2_player_ragdolls", function(_, _, new)
	if !enabled:GetBool() then return end
	
	if (new == "1") then
		PLAYER.CreateRagdoll = CreateRagdoll
	else
		PLAYER.CreateRagdoll = oldCreateRagdoll
	end
end)

if game.SinglePlayer() then
	enabled:SetBool(true)
	default_ragdolls:SetBool(true)
end

local MSG = "GS2ForceModelPregen"

util.AddNetworkString(MSG)

local suppress = false

local function ForceModelPregen(ply, dosv)
	timer.Simple(1, function() --wait a second to avoid crash
		local active_models = {}
		for _, ent in pairs(ents.GetAll()) do
			if (player_ragdolls:GetBool() or !ent:IsPlayer()) then
				local mdl = ent:GetModel()
				if (!active_models[mdl] and util.IsValidRagdoll(mdl or "")) then
					active_models[mdl] = true
					if dosv then
						hook.GetTable()["OnEntityCreated"]["GS2Gibs"](ent) --ugly, forces gibs to generate
					end
				end
			end
		end

		net.Start(MSG)
		net.WriteUInt(table.Count(active_models), 16)
		for mdl in pairs(active_models) do
			net.WriteString(mdl)	
		end
		net.Send(ply)
		suppress = true
		enabled:SetBool(false)
		enabled:SetBool(true)
		suppress = false
	end)
end

hook.Add("PlayerInitialSpawn", "GibSplat2ForceModelPregen", function(ply)
	if enabled:GetBool() then		
		ForceModelPregen(ply)
	end
end)

cvars.AddChangeCallback("gs2_enabled", function(_, old, new)
	if (!suppress and old == "0" and new == "1") then
		local RF = RecipientFilter()
		RF:AddAllPlayers()
		ForceModelPregen(RF, true)
	end
end)