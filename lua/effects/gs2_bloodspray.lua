game.AddParticles("particles/gs2_particles.pcf")

PrecacheParticleSystem("blood_fluid_BI")
PrecacheParticleSystem("blood_fluid_02")

local decal_lifetime 	= CreateClientConVar("gs2_particles_lifetime", 60, true)
local max_particles 	= CreateClientConVar("gs2_max_particles", 10000, true)
local linger_chance 	= CreateClientConVar("gs2_particles_linger_chance", 0.1, true)
local new_effects		= CreateClientConVar("gs2_new_effects", 1, true)
local old_effects		= CreateClientConVar("gs2_old_effects", 1, true)
local bloodpool_size	= CreateClientConVar("gs2_bloodpool_size", 10, true)

local bit_band = bit.band
local bit_lshift = bit.lshift
local math_sqrt = math.sqrt

local blood_colors = {
	[BLOOD_COLOR_RED] = Vector(72, 0, 0),
	[BLOOD_COLOR_YELLOW] = Vector(195, 195, 0),
	[BLOOD_COLOR_GREEN] = Vector(195, 195, 0)
}

local blood_particles = {
	[BLOOD_COLOR_RED] = "blood_fluid_BI",
	[BLOOD_COLOR_YELLOW] = "blood_fluid_BI_green",
	[BLOOD_COLOR_GREEN] = "blood_fluid_BI_green"
}

local blood_decals = {
	[BLOOD_COLOR_RED] = "Blood",
	[BLOOD_COLOR_YELLOW] = "YellowBlood",
	[BLOOD_COLOR_GREEN] = "YellowBlood"
}

sound.Add({
	name = "gs2_bloodsquirt",
	channel = CHAN_BODY,
	volume = 1,
	level = 80,
	pitch = 100,
	sound = {
		"gibsplat2/blood_squish1.wav",
		"gibsplat2/blood_squish2.wav",
		"gibsplat2/blood_squish3.wav",
		"gibsplat2/blood_squish4.wav",
		"gibsplat2/blood_squish5.wav"
	}
})

local PEFFECTS = {}

local PARTICLES = {}

timer.Create("gs2_gcparticles", 3, 0, function()
	while PARTICLES[1] do
		if (!PARTICLES[1].Created or PARTICLES[1].Created + PARTICLES[1]:GetDieTime() < CurTime()) then
			local part = table.remove(PARTICLES, 1)
			part:SetLifeTime(0)
			part:SetDieTime(0)
		else
			break
		end
	end
end)

local trace = {output={}}
local tr = trace.output

local last_hitpos

local function BloodPoolCollide(self, pos, norm)
	self:SetDieTime(0)

	if (norm.z < 0.7) then return end

	trace.start = pos
	trace.endpos = pos - norm

	util.TraceLine(trace)

	if !tr.Hit then return end

	if tr.HitNoDraw then return end

	if tr.HitSky then return end

	if !tr.HitWorld then return end
	
	if !IsValid(self.Parent) then return end

	if !IsValid(self.Parent.Body) then return end

	local max_size = bloodpool_size:GetFloat()

	for key, part in pairs(self.Parent.Body.Blood_Pools) do
		if (part.Created + part:GetDieTime() < CurTime()) then
			self.Parent.Body.Blood_Pools[key] = nil
		else
			local size = part:GetEndSize()
			if (size < max_size and pos:DistToSqr(part:GetPos()) < size * size) then
				local new_size = math_sqrt(size * size + 1)
				if (new_size > max_size) then
					part:SetStartSize(size)
					part:SetEndSize(max_size)					
				else
					part:SetStartSize(size)
					part:SetEndSize(new_size)
				end
				return		
			end
		end
	end

	if !last_hitpos then
		last_hitpos = pos
	else
		if (pos:DistToSqr(last_hitpos) < 1) then
			local offset = Vector(0, 0, 0)
			local count = 0
			for key, part in pairs(self.Parent.Body.Blood_Pools) do
				local part_pos = part:GetPos()
				local threshold = part:GetEndSize() * 0.4
				local off = pos - part_pos
				if (off:LengthSqr() < threshold * threshold) then
					off:Normalize()
					off:Mul(threshold)
					offset:Add(off)
					count = count + 1
				end
			end

			if (count > 0) then
				offset:Div(count)
				pos:Add(offset)
			end

			local particle = self.Parent.Emitter3D:Add(util.DecalMaterial(blood_decals[self.Parent.Blood]), pos)
			particle.Created = CurTime()

			local ang = norm:Angle()
			ang:RotateAroundAxis(norm, math.Rand(0, 359))

			particle:SetAngles(ang)

			particle:SetLifeTime(0)
			particle:SetDieTime(decal_lifetime:GetFloat())

			particle:SetStartSize(0)
			particle:SetEndSize(1)

			particle:SetStartAlpha(255)
			particle:SetEndAlpha(255)

			particle:SetStartLength(1)
			particle:SetEndLength(1)

			table.insert(self.Parent.Body.Blood_Pools, particle)
			table.insert(PARTICLES, particle)

			last_hitpos:Add(pos)
			last_hitpos:Div(2)
		else
			last_hitpos = pos
		end
	end
end

function EFFECT:Init(data)
	self.LocalPos = data:GetOrigin()
	self.LocalAng = data:GetAngles()

	self.Body = data:GetEntity()
	self.Color = data:GetColor()
	self.Bone = data:GetHitBox()
	self.Created = CurTime()
	self.DieTime = math.Clamp(data:GetScale(), 0, 10)
	self.Blood = data:GetColor()
	self.BloodColor = blood_colors[self.Blood] or Vector(255, 255, 255)

	if !IsValid(self.Body) then
		self:Remove()
		return
	end

	SafeRemoveEntityDelayed(self, self.DieTime)

	self.Body.Blood_Pools = {}

	self.PhysBone = self.Body:TranslateBoneToPhysBone(self.Bone)

	self.mask = bit_lshift(1, self.PhysBone)

	local matrix = self.Body:GetBoneMatrix(self.Bone)
	
	if !matrix then
		return
	end

	self:FollowBone(self.Body, self.Bone)
	self.LocalAng:RotateAroundAxis(self.LocalAng:Right(), 180)
	self:SetLocalAngles(self.LocalAng)
	self:SetLocalPos(self.LocalPos)
	
	self.last_sim = CurTime()
	self.last_pos = self:GetPos()

	local attach = self.Body.GS2Limbs[self.PhysBone]
	if !IsValid(attach) then
		attach = self.Body
	end
	
	if (new_effects:GetBool() and blood_particles[self.Blood]) then
		self.PE = CreateParticleSystem(self, blood_particles[self.Blood], PATTACH_ABSORIGIN)
		table.insert(PEFFECTS, self.PE)
		self.Sound = CreateSound(attach, "gs2_bloodsquirt")
		
		self.LastSound = 0
	end

	self:CallOnRemove("gs2_onremove", function()
		if self.PE then			
			self.PE:StopEmission()				
		end
		if self.Sound then
			self.Sound:Stop()
		end
	end)

	self.Emitter = ParticleEmitter(matrix:GetTranslation())
	self.Emitter3D = ParticleEmitter(matrix:GetTranslation(), true)
end

function EFFECT:Think()
	if !IsValid(self.Body) then return false end
		
	if (bit_band(self.mask, self.Body:GetNWInt("GS2GibMask", 0)) != 0) then return false end

	if (self.Sound and self.LastSound + 0.4 < CurTime()) then
		self.LastSound = CurTime()
		self.Sound:Stop()
		self.Sound:PlayEx(0.5, 80)
	end

	local bone_pos, bone_ang = self.Body:GetBonePosition(self.Bone)

	local pos, ang = LocalToWorld(self.LocalPos, self.LocalAng, bone_pos, bone_ang)

	self:SetPos(pos)
	self:SetAngles(ang)
	self:SetupBones()

	if !old_effects:GetBool() then return true end

	local gravity = physenv.GetGravity()

	local pos = self:GetPos()

	local vel = (pos - self.last_pos) / (CurTime() - self.last_sim)

	local particle = self.Emitter:Add(util.DecalMaterial("Blood"), self:GetPos())

	particle:SetLifeTime(0)
	particle:SetDieTime(5)

	particle:SetStartSize(0)
	particle:SetEndSize(0)

	particle:SetStartAlpha(0)
	particle:SetEndAlpha(0)

	particle:SetVelocity(vel)
	particle:SetGravity(gravity)

	particle:SetCollide(true)
	particle:SetCollideCallback(BloodPoolCollide)
	particle.Parent = self

	return true
end


function EFFECT:Render() 
	
end

hook.Add("PostCleanupMap", "GS2ClearParticles", function()
	for key, particle in pairs(PARTICLES) do
		if particle then
			particle:SetDieTime(0)
		end
		PARTICLES[key] = nil
	end
	for key, effect in pairs(PEFFECTS) do
		if IsValid(effect) then
			effect:StopEmissionAndDestroyImmediately()
		end
		PEFFECTS[key] = nil
	end
end)