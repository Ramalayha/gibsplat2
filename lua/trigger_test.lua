hook.Remove("ShouldCollide", "h", function(ent, ent2)
	local c = ent:GetClass()
	local c2 = ent2:GetClass()
	if ent:IsRagdoll() or ent2:IsRagdoll() then
		--print(ent, ent2)
		if c:find("trigger") or c2:find("trigger") then		
			print"yo"
			--return false
		end
	end
end)