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
local old_effects		= CreateClientConVar("gs2_old_effects", 1, true)
local bloodpool_size	= CreateClientConVar("gs2_bloodpool_size", 10, true)

local SIZE = 2

local bit_band = bit.band
local bit_lshift = bit.lshift

local blood_colors = {
	[BLOOD_COLOR_RED] = Vector(72, 0, 0),
	[BLOOD_COLOR_YELLOW] = Vector(195, 195, 0),
	[BLOOD_COLOR_GREEN] = Vector(195, 195, 0)
}

local blood = {
	[BLOOD_COLOR_RED] = {
		"decals/flesh2/blood1",
		"decals/flesh2/blood2",
		"decals/flesh2/blood3",
		"decals/flesh2/blood4",
		"decals/flesh2/blood5"
	},
	[BLOOD_COLOR_YELLOW] = {
		"decals/alienflesh/blood1",
		"decals/alienflesh/blood2",
		"decals/alienflesh/blood3",
		"decals/alienflesh/blood4",
		"decals/alienflesh/blood5"
	},
	[BLOOD_COLOR_GREEN] = {
		"decals/alienflesh/blood1",
		"decals/alienflesh/blood2",
		"decals/alienflesh/blood3",
		"decals/alienflesh/blood4",
		"decals/alienflesh/blood5"
	}
}

local blood_particles = {
	[BLOOD_COLOR_RED] = "blood_fluid_BI"
}

local snd_path = Sound("ambient/water/water_flow_loop1.wav")

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

	local attach = self.Body.GS2Limbs[self.PhysBone]
	if !IsValid(attach) then
		attach = self.Body
	end

	local snd = CreateSound(attach, snd_path)
	snd:PlayEx(0.6, 80)
	snd:FadeOut(self.DieTime)
	self.Sound = snd
	
	attach:CallOnRemove("gs2_bloodspray_killsound", function()
		snd:Stop()
	end)

	if (new_effects:GetBool() and blood_particles[self.Blood]) then
		self.PE = CreateParticleSystem(self, blood_particles[self.Blood], PATTACH_ABSORIGIN)
	end

	if old_effects:GetBool() then
		local pos = self:GetPos()

		self.Emitter = ParticleEmitter(pos, false)
		self.Emitter3D = ParticleEmitter(pos, true)

		self.Particles = {}

		for hbg = 0, self.Body:GetHitBoxGroupCount() - 1 do
			for hb = 0, self.Body:GetHitBoxCount(hbg) - 1 do
				if (self.Body:GetHitBoxBone(hb, hbg) == self.Bone) then
					local min, max = self.Body:GetHitBoxBounds(hb, hbg)
					min.x = 0
					max.x = 0
					self.Radius = min:Distance(max) * 0.2
					return
				end
			end
		end
		self.Radius = 0
	end
end

local trace = {
	mask = MASK_SOLID_BRUSHONLY
}

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

local function OnCollide(self, pos, norm)
	while (#PARTICLES >= max_particles:GetInt()) do
		local part = table.remove(PARTICLES, 1)
		part:SetLifeTime(0)
		part:SetDieTime(0)
	end
		
	local last_particle = self.Effect.last_particle

	if (last_particle and IsValid(self.Effect) and IsValid(self.Effect.Body) and norm.z > 0.7) then
		local blood_pools = self.Effect.Body.Blood_Pools
		if (pos:DistToSqr(last_particle:GetPos()) < last_particle:GetEndSize() ^ 2 and math.random() < 0.1) then
			blood_pools[last_particle] = true			
		end
		local new_pos = Vector(0, 0, 0)
		local div = 0
		for pool in pairs(blood_pools) do
			local size = pool:GetEndSize()
			
			if (pos:DistToSqr(pool:GetPos()) < size * size) then
				if (size >= bloodpool_size:GetFloat()) then
					div = div + 1
					local pos = pos * 1
					pos:Sub(pool:GetPos())
					pos:Normalize()
					pos:Mul(SIZE * math.Rand(1, 8))
					pos:Add(pool:GetPos())
					new_pos:Add(pos)
				else
					local old_size = pool.Size
					local area = old_size * old_size
					area = area + (SIZE * math.Rand(0.5, 1)) ^ 2
					local size = math.sqrt(area)
					pool.Size = size
					pool:SetStartSize(old_size / 3)
					pool:SetEndSize(size)
					return
				end
			end
		end
		if (div > 0) then
			new_pos:Div(div)
			pos = new_pos
		end
	end

	trace.start = pos + norm
	trace.endpos = pos - norm

	local tr = util.TraceLine(trace)

	if (!tr.Hit or tr.HitNoDraw or tr.HitSky or (IsValid(tr.Entity) and !tr.Entity:IsWorld())) then
		return
	end

	self:SetCollide(false)
	self:SetDieTime(0)

	local blood_materials = blood[self.Blood]

	if (blood_materials and IsValid(self.Emitter) and math.random() < linger_chance:GetFloat()) then
		local mat = blood_materials[math.random(1, #blood_materials)]
		
		local particle = self.Emitter:Add(mat, pos)

		local ang = norm:Angle()
		ang:RotateAroundAxis(norm, math.Rand(0, 360))

		particle:SetAngles(ang)

		local size = SIZE * math.Rand(0.5, 1)
		particle.Size = size
		particle:SetStartSize(size)
		particle:SetEndSize(size)

		particle:SetStartAlpha(255)
		particle:SetEndAlpha(255)
		--particle:SetRoll(math.random(0, 360))
		
		particle:SetLifeTime(0)
		
		if IsValid(self.Effect) then
			local die_time = self.Effect.DieTime * 1.3
			particle:SetDieTime(die_time)
			timer.Simple(die_time - 0.05, function()
				particle:SetDieTime(decal_lifetime:GetFloat() - particle:GetDieTime())
				particle:SetStartSize(particle:GetEndSize())
			end)
		else
			particle:SetDieTime(decal_lifetime:GetFloat())
		end

		local color = render.GetLightColor(pos + norm)
		
		--color:Mul(blood_color * math.random(0.95, 1))

		--particle:SetColor(color.x, color.y, color.z)

		particle.Created = CurTime()

		table.insert(PARTICLES, particle)

		self.Effect.last_particle = particle
	end
end

function EFFECT:Think()
	local cur_time = CurTime()

	if (!IsValid(self.Body) or
	 	cur_time - self.Created > self.DieTime or
	 	!self.Body.GS2Limbs or bit_band(self.mask, self.Body:GetNWInt("GS2GibMask")) != 0) then

		local Emitter = self.Emitter
		local Emitter3D = self.Emitter3D

		timer.Simple(10 ,function() --give some time for particles to hit the ground
		 	if Emitter3D then
		 		Emitter3D:Finish()
		 	end
		end)
		if Emitter then
	 		Emitter:Finish()
	 	end	
		if self.PE then
			self.PE:StopEmission()
		end
		if self.Sound then
			self.Sound:Stop() 
		end
		return false
	end

	if new_effects:GetBool() then
		if !IsValid(self.Body) then
			if self.PE then
				self.PE:StopEmission()
			end			
		end
	end

	if old_effects:GetBool() then
		if !IsValid(self.Emitter) then
			if self.Emitter3D then
				self.Emitter3D:Finish()
			end
			if self.Sound then
				self.Sound:Stop() 
			end
			if self.PE then
				self.PE:StopEmission()
			end
			return false
		end

		local matrix = self.Body:GetBoneMatrix(self.Bone)

		local pos = self:GetPos()
		local ang = self:GetAngles()

		self.last_pos = self._last_pos or pos

		local vel = pos - self.last_pos
		vel:Div(cur_time - self.last_sim)
		self.last_sim = cur_time

		local dir = ang:Forward()

		local right = dir:Cross(Vector(0, 0, 1))
		local up = right:Cross(dir)

		for i = 1, 4 do --14
			local pos = pos
			 + right * math.Rand(-0.5, 0.5)
			 + up * math.Rand(0.5, 0.5)

			local dir = dir + VectorRand(-0.3, 0.3)

			local vel = dir * math.Rand(4, 40) * 10 * (0.7 + 0.3 * math.sin((cur_time - self.Created) * 3)) * (self.Created + self.DieTime - cur_time) / self.DieTime
			
			--vel = vel * (0.5 + math.sin(self.Created - cur_time) * 0.5)

			local particle = self.Emitter:Add("effects/blood_drop", pos + Angle(0, math.Rand(0, 360), 0):Forward() * self.Radius)

			table.insert(self.Particles, particle)

			particle:SetGravity(Vector(0, 0, -600))
			particle:SetVelocity(vel + vel)
			particle:SetStartSize(SIZE * math.Rand(0.2, 0.3) * 5)
			particle:SetStartLength(math.Rand(1.25, 2.75) * 5)
			particle:SetLifeTime(0)
			particle:SetDieTime(math.Rand(0.5, 1))

			local color = render.GetLightColor(pos)
			
			color = color * self.BloodColor

			particle:SetColor(color.x, color.y, color.z)

			particle:SetCollide(true)

			particle.Effect = self
			particle.Blood = self.Blood
			particle.Emitter = self.Emitter3D
			particle:SetCollideCallback(OnCollide)
		end

		for i = 1, 8 do --24
			local pos = pos
			 + right * math.Rand(-0.5, 0.5)
			 + up * math.Rand(0.5, 0.5)

			local dir = dir + VectorRand(-1, 1)
			--dir.z = dir.z + math.Rand(0, 1)

			local vel = dir * math.Rand(2, 25) * 5 * (self.Created + self.DieTime - cur_time) / self.DieTime
			
			--vel = vel * (1 + math.sin((self.Created - cur_time) * 10))

			local particle = self.Emitter:Add("effects/blood_drop", pos)

			table.insert(self.Particles, particle)

			particle:SetGravity(Vector(0, 0, -600))
			particle:SetVelocity(vel + vel)
			particle:SetStartSize(SIZE * math.Rand(0.025, 0.05))
			particle:SetStartLength(math.Rand(2.5, 3.75))
			particle:SetLifeTime(0)
			particle:SetDieTime(math.Rand(5, 10))

			local color = render.GetLightColor(pos)
			
			color = color * self.BloodColor

			particle:SetColor(color.x, color.y, color.z)

			particle:SetCollide(true)

			particle.Effect = self
			particle.Blood = self.Blood
			particle.Emitter = self.Emitter3D
			particle:SetCollideCallback(OnCollide)
		end

		for i = 1, 10 do --6
			local pos = pos + dir
			 + right * math.Rand(-1, 1)
			 + up * math.Rand(-1, 1)

			local vel = dir * math.Rand(10, 20) + VectorRand(-0.5, 0.5)

			local particle = self.Emitter:Add("effects/blood_puff", pos + Angle(math.Rand(0, 360), 0, 0):Forward() * self.Radius)

			particle:SetGravity(Vector(0, 0, -600))
			particle:SetVelocity(vel + vel)

			local size = math.Rand(1, 1.5)
			particle:SetStartSize(SIZE * size)	
			particle:SetEndSize(SIZE * size * 4)

			particle:SetStartAlpha(math.random(150, 200))
			particle:SetEndAlpha(0)
			particle:SetRoll(math.random(0, 360))
			particle:SetRollDelta(0)

			particle:SetLifeTime(0)
			particle:SetDieTime(math.Rand(0.01, 0.03))

			local color = render.GetLightColor(pos)

			color = color * self.BloodColor

			particle:SetColor(color.x, color.y, color.z)

			particle:SetCollide(true)

			particle.Effect = self
			particle.Blood = self.Blood
			particle.Emitter = self.Emitter3D
			particle:SetCollideCallback(OnCollide)
		end
	end

 	return true
end

local mat = Material("models/flesh")

function EFFECT:Render()
	
end

hook.Add("PostCleanupMap", "GS2ClearParticles", function()
	for key, particle in pairs(PARTICLES) do
		if particle then
			particle:SetDieTime(0)
		end
		PARTICLES[key] = nil
	end
end)