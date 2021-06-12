local bit_band = bit.band
local bit_lshift = bit.lshift
local math_sqrt = math.sqrt

local flesh_mats = {
	[BLOOD_COLOR_RED] = "models/gibsplat2/flesh/flesh",
	[BLOOD_COLOR_YELLOW] = "models/gibsplat2/flesh/alienflesh",
	[BLOOD_COLOR_GREEN] = "models/gibsplat2/flesh/alienflesh"
}

local blood_colors = {
	[BLOOD_COLOR_RED] = {72, 0, 0, 255},
	[BLOOD_COLOR_YELLOW] = {195, 195, 0, 255},
	[BLOOD_COLOR_GREEN] = {195, 195, 0, 255}
}

local smoke_sprites = {
	--"effects/blood_puff"
	"particle/smokesprites_0001",
	"particle/smokesprites_0002",
	"particle/smokesprites_0003",
	"particle/smokesprites_0004",
	"particle/smokesprites_0005",
	"particle/smokesprites_0006",
	"particle/smokesprites_0007",
	"particle/smokesprites_0008",
	"particle/smokesprites_0009",
	"particle/smokesprites_0010",
	"particle/smokesprites_0011",
	"particle/smokesprites_0012",
	"particle/smokesprites_0013",
	"particle/smokesprites_0014",
	"particle/smokesprites_0015",
	"particle/smokesprites_0016"
}

local BLOOD_STRIPES = {}

local trace = {output={}, mask=MASK_NPCWORLDSTATIC}
local tr = trace.output

local vec_right = Vector(0, 1, 0)

local function FleshSlideThink(self)
	if !self.HitTime then
		self.HitTime = CurTime()

		local pos = self:GetPos()

		self.BloodStripe = {
			--[0] = math.Rand(0.7, 1.2),
			[1] = {
				pos = pos,
				norm = self.HitNormal
			},
			[2] = {
				pos = pos,
				norm = self.HitNormal
			},
			speed = math.Rand(0.7, 1.2)			
		}
		table.insert(BLOOD_STRIPES, self.BloodStripe)

		local color = blood_colors[self.Parent.Blood]

		if color then
			self.BloodStripe.color = color			
		else
			self.BloodStripe.color = {0, 0, 0, 0}
		end
	end

	local right = self.HitNormal:Cross(Vector(0, 0, -1))
	--right:Normalize()
	local down = right:Cross(self.HitNormal)
	down:Normalize()
	down:Mul(down.z * -1)

	trace.start = self:GetPos()
	trace.endpos = trace.start + down * FrameTime() * self.BloodStripe.speed

	util.TraceLine(trace)

	if tr.Hit then
		self:SetPos(tr.HitPos)		
		if (tr.HitNormal.z == 1) then
			--resting on flat ground			
			self.BloodStripe = nil
			self.HitTime = nil			
			return
		else			
			self.HitNormal = tr.HitNormal
			self.BloodStripe[#self.BloodStripe].pos = tr.HitPos
			table.insert(self.BloodStripe, {
				pos = tr.HitPos,
				norm = tr.HitNormal
			})
		end
	else
		trace.start = tr.HitPos + self.HitNormal
		trace.endpos = tr.HitPos - self.HitNormal * 20

		util.TraceLine(trace)

		if (tr.Hit and tr.HitNormal.z != 1) then
			if (tr.HitNormal == self.HitNormal) then
				self.BloodStripe[#self.BloodStripe].pos = tr.HitPos
				self:SetPos(tr.HitPos)
			else				
				local pos = util.IntersectRayWithPlane(self:GetPos(), down, tr.HitPos, tr.HitNormal)
				
				if pos then
					self:SetPos(pos)						
					self.HitNormal = tr.HitNormal

					self.BloodStripe[#self.BloodStripe].pos = pos
					table.insert(self.BloodStripe, table.Copy(self.BloodStripe[#self.BloodStripe]))
					self.BloodStripe[#self.BloodStripe].norm = tr.HitNormal
				end
			end
		else
			if tr.Hit then
				--self:SetVelocity(-self.HitNormal)
				self:SetGravity(physenv.GetGravity())
				self:SetPos(tr.HitPos)				
				self.HitTime = nil
				self.BloodStripe = nil

				return
			else
				trace.start = trace.endpos
				trace.endpos = trace.endpos - down * FrameTime() * self.BloodStripe.speed

				util.TraceLine(trace)

				if tr.Hit then
					local pos = util.IntersectRayWithPlane(self:GetPos(), down, tr.HitPos, tr.HitNormal)
				
					self:SetPos(pos)						
					self.HitNormal = tr.HitNormal

					self.BloodStripe[#self.BloodStripe].pos = pos
					table.insert(self.BloodStripe, table.Copy(self.BloodStripe[#self.BloodStripe]))
					self.BloodStripe[#self.BloodStripe].norm = tr.HitNormal
				else
					self.HitTime = nil
					self:SetPos(tr.HitPos)
					self:SetGravity(physenv.GetGravity())
					self:SetVelocity(Vector(10,0,0))
					return
				end
			end
		end
	end

	self:SetNextThink(CurTime())
end

local FLESH_PIECES = {}

local flesh_mdl = "models/props_junk/watermelon01_chunk02a.mdl"

local function FleshPieceCollide(self, pos, norm)
	if !IsValid(self.Model) then
		self:SetDieTime(0)
		return
	end
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

	local color = blood_colors[self.Parent.Blood]

	if color then		
		color = Color(unpack(color))
		color = color_white
		util.DecalEx(Material(util.DecalMaterial("Blood")), Entity(0), pos, -tr.HitNormal, color, 0.4, 0.4)
	end

	--util.DecalEx(Material(util.DecalMaterial(blood_decals[self.BloodColor])), tr.Entity, tr.HitPos, -tr.HitNormal, color_white, 0.1, 0.1)

	if (norm.z >= 0 and norm.z < 1) then
		self:SetDieTime(30)
		self:SetPos(tr.HitPos + tr.HitNormal * 0.1)

		self:SetVelocity(vector_origin)
		self:SetThinkFunction(FleshSlideThink)
		self:SetNextThink(CurTime())

		self.HitNormal = tr.HitNormal

		self.Model:EmitSound("Watermelon.Impact", 15, 100, 0.1)

		SafeRemoveEntityDelayed(self.Model, math.random(20, 60))
	elseif (norm.z < 0) then
		
		self:SetVelocity(vector_origin)
		self:SetAngleVelocity(angle_zero)

		self.Model:EmitSound("Watermelon.Impact", 15, 100, 0.1)

		timer.Simple(math.random(5, 30) * (2 + norm.z), function()
			if !IsValid(self.Model) then
				self:SetDieTime(0)
				return
			end
			self:SetGravity(physenv.GetGravity())			
			self.Model:EmitSound("Watermelon.Impact", 15, 100, 0.1)
		end)
	end
end

local FLESH_PARTICLES = {}

function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local ang = data:GetAngles()
	local vel = data:GetNormal() * data:GetScale()

	local L2W = Matrix()
	L2W:Translate(pos)
	L2W:Rotate(ang)
	
	self.Blood = data:GetColor()
	self.FleshMat = flesh_mats[self.Blood]

	if !self.FleshMat then
		self:Remove()
		return
	end
	
	self.Emitter = ParticleEmitter(pos)

	local bound = data:GetStart()
	bound.x = math.abs(bound.x)
	bound.y = math.abs(bound.y)
	bound.z = math.abs(bound.z)

	local size = data:GetMagnitude()

	local blood_vector = Vector(unpack(blood_colors[self.Blood]))

	if blood_colors[self.Blood] then
		for i = 1, size do
			local dir = VectorRand()
			dir:Normalize()
			dir:Mul(math.Rand(size / 3, size / 2))

			local offset = Vector(math.Rand(-bound.x, bound.x), math.Rand(-bound.y, bound.y), math.Rand(-bound.z, bound.z))

			offset = L2W * offset

			local particle = self.Emitter:Add(smoke_sprites[math.random(1, #smoke_sprites)], offset)

			particle:SetLifeTime(0)
			particle:SetDieTime(math.Rand(0.5, 1))

			particle:SetStartSize(math.Rand(size / 3, size / 6))
			particle:SetEndSize(math.Rand(size / 7, size / 10))

			particle:SetStartAlpha(math.Rand(50, 150))
			particle:SetEndAlpha(0)

			particle:SetVelocity(vel * 0.1 + dir * math.Rand(0.8, 1.2))

			local color = render.GetLightColor(offset)
			
			color:Mul(blood_vector)

			particle:SetColor(color.x, color.y, color.z)

			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(1, 3))
		end
	end

	local gravity = physenv.GetGravity()

	for i = 1, math.random(5, 10) do
		local particle = self.Emitter:Add("", self:GetPos())

		particle:SetAngles(AngleRand())
		particle:SetAngleVelocity(AngleRand())

		particle:SetLifeTime(0)
		particle:SetDieTime(15)

		particle:SetStartSize(0)
		particle:SetEndSize(0)

		particle:SetStartAlpha(255)
		particle:SetEndAlpha(255)

		particle:SetVelocity(vel + VectorRand() * vel:Length() * math.Rand(0.4, 0.8))
		particle:SetGravity(gravity)

		particle:SetCollide(true)
		particle:SetCollideCallback(FleshPieceCollide)
		--particle:SetBounce(0.2)
		particle.Parent = self
		particle.FleshMat = self.FleshMat
		particle.BloodColor = self.Blood

		table.insert(FLESH_PARTICLES, particle)

		particle.Model = ClientsideModel(flesh_mdl)
		particle.Model:SetModelScale(math.Rand(0.4, 1))
		particle.Model:SetMaterial(self.FleshMat)
				
		table.insert(FLESH_PIECES, particle.Model)
	end

	while (#FLESH_PARTICLES > 32) do
		local part = table.remove(FLESH_PARTICLES, 1)
		if part then
			part:SetDieTime(0)
			SafeRemoveEntity(part.Model)
		end
	end
end

function EFFECT:Think()
	return true
end


function EFFECT:Render() 
	
end

local matrix = Matrix()

local center_offset = Vector(-1.186550, -1.807150, 2.105250)

hook.Add("PostDrawOpaqueRenderables", "GS2DrawFleshParticles", function()
	for key, piece in pairs(FLESH_PARTICLES) do
		if (piece:GetDieTime() == 0 or !IsValid(piece.Model)) then
			FLESH_PARTICLES[key] = nil
			SafeRemoveEntity(piece.Model)
		else
			local pos = piece:GetPos()
			local ang = piece:GetAngles()
			matrix:Identity()
			matrix:Translate(pos)
			matrix:Rotate(ang)

			local mdl = piece.Model
			mdl:SetPos(matrix * (center_offset * -(mdl:GetModelScale() or 0)))
			mdl:SetAngles(ang)
			mdl:SetupBones()			
		end
	end
end)

--local mat = Material("models/flesh")
local mat = Material("effects/beam001_red")

local vec_up = Vector(0, 0, 1)

local width = 1

local render_SetMaterial	= render.SetMaterial

local mesh_Begin 			= mesh.Begin
local mesh_End 				= mesh.End
local mesh_Position 		= mesh.Position
local mesh_Normal 			= mesh.Normal
local mesh_TexCoord 		= mesh.TexCoord
local mesh_Color			= mesh.Color
local mesh_AdvanceVertex 	= mesh.AdvanceVertex

hook.Add("PostDrawOpaqueRenderables", "GS2DrawBloodStripes", function()
	for _, strip in pairs(BLOOD_STRIPES) do
		render_SetMaterial(mat)
		mesh_Begin(MATERIAL_QUADS, (#strip - 1))

		local R, G, B, A = unpack(strip.color)

		local len = 0
		for i = 1, #strip - 1 do
			local s1 = strip[i]
			local s2 = strip[i + 1]

			local p1 = s1.pos
			local p2 = s2.pos

			local len2 = len + p1:Distance(p2)

			local v1 = len / 10
			local v2 = len2 / 10

			local n = s2.norm
			local r = n:Cross(vec_up)
			r:Normalize()
			local u = n:Cross(r)

			--render.DrawQuadEasy((v1 + v2) / 2, n, 2, v1:Distance(v2), color_white)

			--vert1
			mesh_Position(p1 + r * width)
			mesh_Normal(s1.norm)
			mesh_TexCoord(0, 0, v1)
			mesh_Color(R, G, B, A)				
			mesh_AdvanceVertex()

			--vert2
			mesh_Position(p1 - r * width)
			mesh_Normal(s1.norm)
			mesh_TexCoord(0, 1, v1)
			mesh_Color(R, G, B, A)		
			mesh_AdvanceVertex()

			--vert3
			mesh_Position(p2 - r * width)
			mesh_Normal(s2.norm)
			mesh_TexCoord(0, 1, v2)
			mesh_Color(R, G, B, A)		
			mesh_AdvanceVertex()

			--vert4
			mesh_Position(p2 + r * width)
			mesh_Normal(s2.norm)
			mesh_TexCoord(0, 0, v2)
			mesh_Color(R, G, B, A)		
			mesh_AdvanceVertex()

			len = len2
		end
		mesh_End()
	end
end)

hook.Add("PostCleanupMap", "GS2ClearFleshPieces", function()
	for key, piece in pairs(FLESH_PIECES) do
		SafeRemoveEntity(piece)
		FLESH_PIECES[key] = nil
	end
	table.Empty(BLOOD_STRIPES)
end)