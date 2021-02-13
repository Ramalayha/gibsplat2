AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local FORCE_SCALE = 3

local math_atan2 	= math.atan2
local math_min 		= math.min
local math_max 		= math.max
local math_abs 		= math.abs

local function GetPhysID(ent, phys)
	for phys_bone = 0, ent:GetPhysicsObjectCount() - 1 do
		if (ent:GetPhysicsObjectNum(phys_bone) == phys) then
			return phys_bone
		end
	end
	return -1
end

local function AlignAngles(phys, ang, invmul) 
	local avel = Vector(0, 0, 0)
	
	local ang1 = phys:GetAngles()
		
	local forward1 = ang1:Forward()
	local forward2 = ang:Forward()
	local fd = forward1:Dot(forward2)
	
	local right1 = ang1:Right()
	local right2 = ang:Right()
	local rd = right1:Dot(right2)
	
	local up1 = ang1:Up()
	local up2 = ang:Up()
	local ud = up1:Dot(up2)
	
	local pitchvel = math.asin(forward1:Dot(up2)) * 180 / math.pi
	local yawvel = math.asin(forward1:Dot(right2)) * 180 / math.pi
	local rollvel = math.asin(right1:Dot(up2)) * 180 / math.pi
		
	avel.y = avel.y + pitchvel
	avel.z = avel.z + yawvel
	avel.x = avel.x + rollvel
	
	avel:Mul(7 * (1 - invmul))
	--avel:Mul(phys:GetMass() * (1 - invmul))
	
	avel:Sub(phys:GetAngleVelocity() * 0.9)
	
	phys:AddAngleVelocity(avel)
end

local bone_list_torso = 
{
	--"ValveBiped.Bip01_Pelvis", --crashes
	--"ValveBiped.Bip01_Spine4",
	"ValveBiped.Bip01_Head1",
	--"ValveBiped.Bip01_R_Thigh",
	--"ValveBiped.Bip01_R_Calf",
	--"ValveBiped.Bip01_R_Foot",
	--"ValveBiped.Bip01_L_Thigh",
	--"ValveBiped.Bip01_L_Calf",
	--"ValveBiped.Bip01_L_Foot"
	"ValveBiped.Bip01_R_Upperarm",
	"ValveBiped.Bip01_R_Forearm",
	--"ValveBiped.Bip01_R_Hand",
	"ValveBiped.Bip01_L_Upperarm",
	"ValveBiped.Bip01_L_Forearm",
	--"ValveBiped.Bip01_L_Hand"
}

local bone_list_legs = 
{
	--"ValveBiped.Bip01_Pelvis", --crashes
	--"ValveBiped.Bip01_Spine4",
	--"ValveBiped.Bip01_Head1",
	"ValveBiped.Bip01_R_Thigh",
	"ValveBiped.Bip01_R_Calf",
	--"ValveBiped.Bip01_R_Foot",
	"ValveBiped.Bip01_L_Thigh",
	"ValveBiped.Bip01_L_Calf",
	--"ValveBiped.Bip01_L_Foot"
	--"ValveBiped.Bip01_R_Upperarm",
	--"ValveBiped.Bip01_R_Forearm",
	--"ValveBiped.Bip01_R_Hand",
	--"ValveBiped.Bip01_L_Upperarm",
	--"ValveBiped.Bip01_L_Forearm",
	--"ValveBiped.Bip01_L_Hand"
}

function ENT:Die(time)
	self.DieTime = CurTime()
	self:SetDuration(time)
	SafeRemoveEntityDelayed(self, time)
end

function ENT:Initialize()
	local mode = self:GetMode()

	self:SetModel("models/police.mdl")
	if (mode == 1) then
		self:ResetSequence(self:LookupSequence("Choked_Barnacle"))
	else
		self:ResetSequence(self:LookupSequence("idleonfire"))
	end
	self:SetPlaybackRate(0.5)

	self:StartMotionController()

	local body = self:GetBody()

	--self.Ignore = {}

	local bone_list = mode == 0 and bone_list_torso or bone_list_legs

	for _, bone_name in pairs(bone_list) do
		local bone = body:LookupBone(bone_name)
		if bone then
			local phys_bone = body:TranslateBoneToPhysBone(bone)
			local phys = body:GetPhysicsObjectNum(phys_bone)
			self:AddToMotionController(phys)
		end
	end

	self.LerpMultiplier = 1000

	self.Created = CurTime()

	local head_bone = body:LookupBone("ValveBiped.Bip01_Head1")

	self.HeadPhysBone = head_bone and body:TranslateBoneToPhysBone(head_bone) or -1

	body:AddCallback("PhysicsCollide", function(body, data)
		if (data.HitEntity == body) then 
			return
		end
		local phys = data.PhysObject		
		if (IsValid(self) and CurTime() - self.Created > 0.5) then
			if (body:GetVelocity():LengthSqr() < 200) then --Not moving? quiet down
				self:Die(1)
				return
			end
			local phys_bone = GetPhysID(body, phys)
			--If we bump head, go limp
			if (data.Speed > 500 and phys_bone == self.HeadPhysBone) then
				self:Remove()
				return
			end
			--[[
			--0.7 ~= 45 degrees
			if (data.HitNormal.z > 0.7) then
				table.insert(self.Ignore, phys_bone)
			end]]			
		end
	end)

	body:DeleteOnRemove(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:PhysicsSimulate(phys, dt)
	--If we move slow, do nothing. This somewhat prevents ragdoll spazzing out when on the ground
	if (phys:GetVelocity():LengthSqr() < 100) then
		return
	end

	local body = self:GetBody()

	if body:GS2IsDismembered(self.HeadPhysBone) then
		self:Remove()
		return
	end

	--[[if table.HasValue(self.Ignore, GetPhysID(body, phys)) then
		return
	end]]

	--If we're drowning or have been severed in half, slowly die
	if (!self.DieTime and (body:WaterLevel() > 1 or body:GS2IsDismembered(1))) then
		self:Die(5)
	end

	self:FrameAdvance(dt)

	local phys0 = body:GetPhysicsObjectNum(0)

	phys0:AddAngleVelocity(phys0:GetAngleVelocity() * -0.5)

	local fall_speed = phys0:GetVelocity().z

	--Start flailing faster the faster we fall
	if (fall_speed < 0) then
		self:SetPlaybackRate(math_max(0.5, -2 * fall_speed / 1000))
	end

	local lerp = dt * 10
	
	local phys_bone = GetPhysID(body, phys)

	local bone = body:TranslatePhysBoneToBone(phys_bone)
	local bone_name = body:GetBoneName(bone)
	
	local phys_bone2
	local dis = false
	repeat
		phys_bone2 = body:TranslateBoneToPhysBone(bone)
		if body:GS2IsDismembered(phys_bone) then			
			break
		end
		bone = body:GetBoneParent(bone)
	until (phys_bone2 == 1 or phys_bone2 == 0)

	--If it's attached to torso or if torso is attached to pelvis
	if (phys_bone2 == 1 or !body:GS2IsDismembered(1)) then
		local bone = body:TranslatePhysBoneToBone(phys_bone)
		local _, bone_ang = self:GetBonePosition(bone)
		
		local _, bone_ang0 = self:GetBonePosition(0)

		local _, lang = WorldToLocal(vector_origin, bone_ang, vector_origin, bone_ang0)

		_, bone_ang = LocalToWorld(vector_origin, lang, body:GetBonePosition(0))

		AlignAngles(phys, bone_ang, (CurTime() - (self.DieTime or self.Created)) / self:GetDuration() or 0)
	end
end