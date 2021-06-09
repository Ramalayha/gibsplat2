--[[
	Code borrowed from source sdk with slight modifications
]]

game.AddParticles("particles/gs2_particles.pcf")

PrecacheParticleSystem("blood_fluid_BI")
PrecacheParticleSystem("blood_fluid_02")

local decal_lifetime 	= CreateClientConVar("gs2_particles_lifetime", 60, true)
local max_particles 	= CreateClientConVar("gs2_max_particles", 10000, true)
local linger_chance 	= CreateClientConVar("gs2_particles_linger_chance", 0.1, true)
local new_effects		= CreateClientConVar("gs2_new_effects", 1, true)
local old_effects		= CreateClientConVar("gs2_old_effects", 0, true)
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

local flesh_mats = {
	[BLOOD_COLOR_RED] = Material("models/gibsplat2/flesh/flesh"),
	[BLOOD_COLOR_YELLOW] = Material("models/gibsplat2/flesh/alienflesh"),
	[BLOOD_COLOR_GREEN] = Material("models/gibsplat2/flesh/alienflesh")
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

local FLESH_PIECES = {}

local flesh_mdl = "models/props_junk/watermelon01_chunk02a.mdl"

local function FleshPieceCollide(self, pos, norm)
	trace.start = pos
	trace.endpos = pos - norm

	util.TraceLine(trace)

	if !tr.Hit then return end

	if tr.HitNoDraw then return end

	if tr.HitSky then return end

	if tr.Entity:IsRagdoll() then return end

	if (tr.Entity:GetMoveType() != MOVETYPE_NONE and
		tr.Entity:GetMoveType() != MOVETYPE_PUSH and
		tr.Entity:GetMoveType() != MOVETYPE_VPHYSICS) then return end

	util.DecalEx(Material(util.DecalMaterial(blood_decals[self.BloodColor])), tr.Entity, tr.HitPos, -tr.HitNormal, color_white, 0.1, 0.1)

	if (norm.z > 0) then
		self:SetDieTime(0)

		local mdl = ClientsideModel(flesh_mdl)
		mdl:SetPos(tr.HitPos - tr.HitNormal)
		mdl:SetAngles(self:GetAngles())
		mdl:SetMaterial(self.Mat:GetName())
		mdl:SetModelScale(0.4)
		mdl:SetParent(tr.Entity)

		mdl:EmitSound("Watermelon.Impact", 15, 100, 0.1)

		SafeRemoveEntityDelayed(mdl, math.random(20, 60))

		table.insert(FLESH_PIECES, mdl)
	elseif (norm.z < 0) then
		self:SetGravity(vector_origin)
		self:SetVelocity(vector_origin)
		self:SetAngleVelocity(angle_zero)

		timer.Simple(math.random(10, 20) * (1 + norm.z), function()
			self:SetGravity(physenv.GetGravity())
		end)
	end
end

local FLESH_PARTICLES = {}

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

	if !old_effects:GetBool() then return end

	local flesh = flesh_mats[self.Blood]

	if flesh then
		local gravity = physenv.GetGravity()

		for i = 1, math.random(1, 3) do
			local particle = self.Emitter:Add("", self:GetPos())

			particle:SetAngles(AngleRand())
			particle:SetAngleVelocity(AngleRand())

			particle:SetLifeTime(0)
			particle:SetDieTime(15)

			particle:SetStartSize(0)
			particle:SetEndSize(0)

			particle:SetStartAlpha(0)
			particle:SetEndAlpha(0)

			particle:SetVelocity(self:GetAngles():Forward() * 150 + VectorRand() * 30)
			particle:SetGravity(gravity)

			particle:SetCollide(true)
			particle:SetCollideCallback(FleshPieceCollide)
			particle:SetBounce(0.2)
			particle.Parent = self
			particle.Mat = flesh
			particle.BloodColor = self.Blood

			table.insert(FLESH_PARTICLES, particle)
		end
	end
end

function EFFECT:Think()
	if !IsValid(self.Body) then return false end

	if (CurTime() - self.Created > self.DieTime) then return false end
		
	if (bit_band(self.mask, self.Body:GetNWInt("GS2GibMask")) != 0) then return false end

	if (self.Sound and self.LastSound + 0.4 < CurTime()) then
		self.LastSound = CurTime()
		self.Sound:Stop()
		self.Sound:PlayEx(0.5, 80)
	end

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

local mdl = ClientsideModel(flesh_mdl)
mdl:SetNoDraw(true)
mdl:SetModelScale(0.4)

hook.Add("PostDrawOpaqueRenderables", "GS2DrawFleshParticles", function()
	for key, piece in pairs(FLESH_PARTICLES) do
		if (piece:GetDieTime() == 0) then
			FLESH_PARTICLES[key] = nil
		else
			render.MaterialOverride(piece.Mat)
				mdl:SetRenderOrigin(piece:GetPos())
				mdl:SetRenderAngles(piece:GetAngles())
				mdl:SetupBones()
				mdl:DrawModel()
			render.MaterialOverride()
		end
	end
end)

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
	for key, piece in pairs(FLESH_PIECES) do
		SafeRemoveEntity(piece)
		FLESH_PIECES[key] = nil
	end
end)