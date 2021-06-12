local tr = LocalPlayer():GetEyeTrace()

local EF = EffectData()
EF:SetOrigin(tr.HitPos + tr.HitNormal * 30)
EF:SetColor(BLOOD_COLOR_RED)
EF:SetMagnitude(50)
EF:SetStart(Vector(3, 3, 30))
util.Effect("gs2_explode", EF)