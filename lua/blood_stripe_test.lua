local tr = Entity(1):GetEyeTrace()

local p1 = tr.HitPos + tr.HitNormal
local pc = tr.HitPos + tr.HitNormal

local n = tr.HitNormal

local r = n:Cross(Vector(0, 0, -1))
local d = r:Cross(n)
d:Normalize()
print(d)

local next_think = 0

local trace = {output={}}

local speed = 5

local mat = Material("models/wireframe")

local lines = {}
table.insert(lines, p1)

hook.Add("PostDrawOpaqueRenderables", "h", function()
	--debugoverlay.Cross(p1,2,0.1,color_white,true)
	--debugoverlay.Cross(pc,2,0.1,color_white,true)

	render.SetMaterial(mat)

	local p1, p2

	for i = 1, #lines - 1 do
		p1 = lines[i]
		p2 = lines[i+1]
		render.DrawQuad(p1 + r * 3, p2 + r * 3, p2 - r * 3, p1 - r * 3)
	end

	p2 = lines[#lines]

	render.DrawQuad(p2 + r * 3, pc + r * 3, pc - r * 3, p2 - r * 3)

	if (next_think < CurTime()) then
		next_think = CurTime() + 0.015

		trace.start = pc + n
		trace.endpos = pc + d * speed * 0.015

		util.TraceLine(trace)

		if !trace.output.Hit then
			trace.start = trace.endpos
			trace.endpos = trace.start - n * 2

			util.TraceLine(trace)
			if trace.output.Hit then
				pc = trace.output.HitPos
				if trace.output.HitNormal != n then					
					n = trace.output.HitNormal
					table.insert(lines, trace.output.HitPos)
				end
			end
		else
			pc = trace.output.HitPos
			if trace.output.HitNormal != n then					
				n = trace.output.HitNormal
				table.insert(lines, trace.output.HitPos)
			end
		end
	end
end)