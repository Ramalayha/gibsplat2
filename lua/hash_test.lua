local _, folders = file.Find("entities/*", "LUA")

for _, fo in pairs(folders) do
	local files = file.Find("entities/"..fo.."/*", "LUA")
	for _, f in pairs(files) do
		local txt = file.Read("entities/"..fo.."/"..f, "LUA")
		if txt:find('gs2_enabled') then
			print(fo, f)
		end
	end
end