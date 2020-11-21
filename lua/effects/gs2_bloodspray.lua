--[[
	Code borrowed from source sdk with slight modifications
]]

local DECAL_CHANCE = 0.01
local LINGER_CHANCE = 0.3

local blood_small = {
	"decals/flesh/blood1",
	"decals/flesh/blood2",
	"decals/flesh/blood3",
	"decals/flesh/blood4",
	"decals/flesh/blood5"
}

local blood_small_yellow = {
	"decals/alienflesh/shot1",
	"decals/alienflesh/shot2",
	"decals/alienflesh/shot3",
	"decals/alienflesh/shot4",
	"decals/alienflesh/shot5"
}

game.AddDecal("BloodSmall", blood_small)

game.AddDecal("BloodSmallYellow", blood_small_yellow)

local bit_band = bit.band
local bit_lshift = bit.lshift

function EFFECT:Init(data)
	self.LocalPos = data:GetOrigin()
	self.LocalAng = data:GetAngles()

	self.Body = data:GetEntity()
	self.Color = data:GetColor()
	self.Bone = data:GetHitBox()
	self.Created = CurTime()
	self.DieTime = 5
	self.BloodColor = data:GetColor() or BLOOD_COLOR_RED

	if !IsValid(self.Body) then
		self:Remove()
		return
	end

	self.PhysBone = self.Body:TranslateBoneToPhysBone(self.Bone)

	local matrix = self.Body:GetBoneMatrix(self.Bone)
	
	if !matrix then
		return
	end

	local bone_pos = matrix:GetTranslation()
	local bone_ang = matrix:GetAngles()

	--self:SetRenderBounds(Vector(-1, -1, -1), Vector(1, 1, 1))
	self:SetPos(bone_pos)

	self:SetParent(self.Body)
	self:SetParentPhysNum(self.Body:TranslateBoneToPhysBone(self.Bone))

	self.Emitter = ParticleEmitter(bone_pos, false)
	self.Emitter3D = ParticleEmitter(bone_pos, true)

	self.Particles = {}
end

local red = Vector(72, 0, 0)
local yellow = Vector(195, 195, 0)

local function OnCollide(self, pos, norm)
	if (math.random() < DECAL_CHANCE) then
		if (self.BloodColor == BLOOD_COLOR_RED) then
			util.Decal("BloodSmall", pos, norm)
		else
			util.Decal("YellowBlood", pos, norm)
		end
	end

	if (IsValid(self.Emitter) and math.random() < LINGER_CHANCE) then
		local mat
		if (self.BloodColor == BLOOD_COLOR_RED) then
			mat = blood_small[math.random(1, #blood_small)]
		else
			mat = blood_small_yellow[math.random(1, #blood_small_yellow)]
		end
		local particle = self.Emitter:Add(mat, pos)

		local ang = norm:Angle()
		ang:RotateAroundAxis(norm, math.Rand(0, 360))

		particle:SetAngles(ang)

		local size = math.Rand(0.5, 1)
		particle:SetStartSize(size)
		particle:SetEndSize(size)

		particle:SetStartAlpha(255)
		particle:SetEndAlpha(255)
		--particle:SetRoll(math.random(0, 360))
		
		particle:SetLifeTime(0)
		particle:SetDieTime(10)

		local color = render.GetLightColor(pos + norm)
		
		if (self.BloodColor == BLOOD_COLOR_RED) then
			color:Mul(red)
		else
			color:Mul(yellow)
		end

		particle:SetColor(color.x, color.y, color.z)
	end

	self:SetDieTime(0)
end

function EFFECT:Think() --do return false end
	local cur_time = CurTime()
	if !IsValid(self.Emitter) then
		return false
	end
	if (!IsValid(self.Body) or
	 	cur_time - self.Created > self.DieTime or
	 	!self.Body.GS2Limbs or !IsValid(self.Body.GS2Limbs[self.PhysBone])) then
	 	self.Emitter:Finish()	 	
		return false
	end

	local matrix = self.Body:GetBoneMatrix(self.Bone)

	local bone_pos, bone_ang = LocalToWorld(self.LocalPos, self.LocalAng, matrix:GetTranslation(), matrix:GetAngles())

	local bone_dir = -bone_ang:Forward()

	local right = bone_dir:Cross(Vector(0, 0, 1))
	local up = right:Cross(bone_dir)

	for i = 1, 7 do --14
		local pos = bone_pos
		 + right * math.Rand(-0.5, 0.5)
		 + up * math.Rand(0.5, 0.5)

		local dir = bone_dir + VectorRand(-0.3, 0.3)

		local vel = dir * math.Rand(4, 40) * 10 * (0.5 + 0.5 * math.sin((cur_time - self.Created) * 3)) * (self.Created + self.DieTime - cur_time) / self.DieTime
		
		--vel = vel * (0.5 + math.sin(self.Created - cur_time) * 0.5)

		local particle = self.Emitter:Add("effects/blood_drop", pos)

		table.insert(self.Particles, particle)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(vel)
		particle:SetStartSize(math.Rand(0.2, 0.3) * 5)
		particle:SetStartLength(math.Rand(1.25, 2.75) * 5)
		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(0.5, 1))

		local color = render.GetLightColor(pos) * 1.5
		
		if (self.BloodColor == BLOOD_COLOR_RED) then
			color:Mul(red)
		else
			color:Mul(yellow)
		end

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.BloodColor = self.BloodColor
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

	for i = 1, 12 do --24
		local pos = bone_pos
		 + right * math.Rand(-0.5, 0.5)
		 + up * math.Rand(0.5, 0.5)

		local dir = bone_dir + VectorRand(-1, 1)
		--dir.z = dir.z + math.Rand(0, 1)

		local vel = dir * math.Rand(2, 25) * 5 * (self.Created + self.DieTime - cur_time) / self.DieTime
		
		--vel = vel * (1 + math.sin((self.Created - cur_time) * 10))

		local particle = self.Emitter:Add("effects/blood_drop", pos)

		table.insert(self.Particles, particle)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(vel)
		particle:SetStartSize(math.Rand(0.025, 0.05))
		particle:SetStartLength(math.Rand(2.5, 3.75))
		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(5, 10))

		local color = render.GetLightColor(pos) * 1.5
		
		if (self.BloodColor == BLOOD_COLOR_RED) then
			color:Mul(red)
		else
			color:Mul(yellow)
		end

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.BloodColor = self.BloodColor
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

	for i = 1, 3 do --6
		local pos = bone_pos + bone_dir
		 + right * math.Rand(-1, 1)
		 + up * math.Rand(-1, 1)

		local vel = bone_dir * math.Rand(10, 20) + VectorRand(-0.5, 0.5)

		local particle = self.Emitter:Add("effects/blood_puff", pos)

		particle:SetGravity(Vector(0, 0, -600))
		particle:SetVelocity(vel)

		local size = math.Rand(1.5, 2)
		particle:SetStartSize(size)	
		particle:SetEndSize(size * 4)

		particle:SetStartAlpha(math.random(80, 128))
		particle:SetEndAlpha(0)
		particle:SetRoll(math.random(0, 360))
		particle:SetRollDelta(0)

		particle:SetLifeTime(0)
		particle:SetDieTime(math.Rand(0.01, 0.03))

		local color = render.GetLightColor(pos) * 1.5

		if (self.BloodColor == BLOOD_COLOR_RED) then
			color:Mul(red)
		else
			color:Mul(yellow)
		end

		particle:SetColor(color.x, color.y, color.z)

		particle:SetCollide(true)

		particle.BloodColor = self.BloodColor
		particle.Emitter = self.Emitter3D
		particle:SetCollideCallback(OnCollide)
	end

	self:NextThink(cur_time + 1)

 	return true
end

local mat = Material("models/flesh")

function EFFECT:Render()
	
end