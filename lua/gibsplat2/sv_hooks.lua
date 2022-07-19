include("extensions.lua")

util.AddNetworkString("GS2Dissolve")

local enabled 			= GetConVar("gs2_enabled")
local player_ragdolls 	= GetConVar("gs2_player_ragdolls")
local default_ragdolls 	= GetConVar("gs2_default_ragdolls")

local HOOK_NAME = "GibSplat2"

local var_funcs = {}

for key, value in pairs(FindMetaTable("CTakeDamageInfo")) do
	if (key:find("^Get") and debug.getinfo(value).what == "C") then		
		table.insert(var_funcs, key:match("^Get(.-)$"))
	end
end

local function GetDamageInfoVars(dmginfo)
	local output = {}
	for _, func in pairs(var_funcs) do
		output[func] = dmginfo["Get"..func](dmginfo)
	end
	return output
end

local function SetDamageInfoVars(dmginfo, vars)
	for var, value in pairs(vars) do
		dmginfo["Set"..var](dmginfo, value)
	end
end

local function GS2CreateEntityRagdoll(ent, doll)
	if !IsValid(doll) or !doll:IsRagdoll() or !IsValid(doll:GetPhysicsObjectNum(0)) then return end
	doll:MakeCustomRagdoll()

	if (ent.__lastdmginfovars and ent.__lastdmgtime == CurTime()) then
		local dmginfo = DamageInfo()
		SetDamageInfoVars(dmginfo, ent.__lastdmginfovars)

		local dmg_pos = dmginfo:GetDamagePosition()

		if ent:IsPlayer() then
			--doll:TakePhysicsDamage(dmginfo)
			local force = dmginfo:GetDamageForce()
			doll:GetPhysicsObject():ApplyForceOffset(force, dmg_pos)
			doll.took_damage = true
		end

		if dmginfo:IsExplosionDamage() then
			local pbone = dmginfo:GetHitPhysBone(doll) or 0
			local phys = doll:GetPhysicsObjectNum(pbone)

			local dmg = dmginfo:GetDamage()
			local dmg_max = dmginfo:GetMaxDamage()
						
			dmginfo:SetDamageForce(vector_origin) --no extra force on limbs when npc died
			
			if dmg == dmg_max then
				dmg_max = 150
				dmginfo:SetMaxDamage(150) --fix for gmod bug
			end

			local dist = phys:GetPos():Distance(dmg_pos)

			for _, relay in pairs(doll.GS2LimbRelays) do
				local dist2 = relay:GetPos():Distance(dmg_pos)
				local frac = dist / dist2
				local dmg = dmg * frac				
				dmginfo:SetDamage(dmg)				
				relay:TakeDamageInfo(dmginfo)
			end			
		else			
			doll:TakeDamageInfo(dmginfo)
		end
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

local gib_chance = GetConVar("gs2_gib_chance")

local function ShouldGib(dmginfo, ragdoll)
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
		
		local phys_bone = dmginfo:GetHitPhysBone(ent)
		if !phys_bone then
			return
		end
		
		local relay = ent.GS2LimbRelays[phys_bone]

		if IsValid(relay) then
			relay:OnTakeDamage(dmginfo)
		end

		return true		
	elseif (ent:IsNPC() or ent:IsPlayer()) then
		if (dmginfo:IsDamageType(5) and dmginfo:GetDamage() > ent:Health()) then --5 = DMG_CRUSH | DMG_SLASH
			local dmg_type = dmginfo:GetDamageType() --Prevents zombie from cutting in half
			dmginfo:SetDamageType(bit.band(dmg_type, bit.bnot(DMG_SLASH)))			
		end

		if ent:GetClass():find("antlion") and ent:Health() - dmg < 20 then
			dmginfo:SetDamageType(DMG_GENERIC)
			dmginfo:SetDamage(ent:Health() + 20) --override default gibbing mechanic of antlions
			ent:SetSaveValue("m_bDontExplode", true)
		end
		
		ent.__lastdmginfovars = GetDamageInfoVars(dmginfo)
		ent.__lastdmgtime = CurTime()
		
		if ent:GetClass():find("zombie") then
			local att = dmginfo:GetAttacker()
			local is_heavy
			if IsValid(att) then
				local phys = att:GetPhysicsObject()
				if IsValid(phys) then
					is_heavy = phys:GetMass() >= 300 --this triggers zombie splitting to occur and we dont want that
				end
			end
			if (dmginfo:IsDamageType(DMG_CRUSH) and is_heavy) then
				dmginfo:SetDamageType(DMG_GENERIC) --change damage type so zombies dont split
			elseif (dmginfo:IsDamageType(DMG_BLAST) and dmg > ent:GetMaxHealth() / 2) then
				dmginfo:SetDamageType(DMG_GENERIC) --change damage type so zombies dont split
			end
		end
		
		ent.GS2Decals = ent.GS2Decals or {}
		
		local phys_bone = dmginfo:GetHitPhysBone(ent)
		if (phys_bone) then
			ent.GS2Decals[phys_bone] = ent.GS2Decals[phys_bone] or {}
			table.insert(ent.GS2Decals[phys_bone], dmg_pos)
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
		--phys:SetVelocity(self:GetVelocity())
	end

	self:SpectateEntity(ragdoll)
	self:Spectate(OBS_MODE_CHASE)

	dolls[self] = ragdoll

	ragdoll.GS2Player = self

	GS2CreateEntityRagdoll(self, ragdoll)

	if !ragdoll.took_damage then --no forces where applied from damage, copy player velocity
		for i = 0, ragdoll:GetPhysicsObjectCount()-1 do
			local phys = ragdoll:GetPhysicsObjectNum(i)
			phys:SetVelocity(self:GetVelocity())
		end
	end

	ragdoll.took_damage = nil

	return ragdoll
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