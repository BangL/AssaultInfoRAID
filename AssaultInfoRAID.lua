AssaultInfo = AssaultInfo or {}
if not AssaultInfo.setup then
	AssaultInfo._path = ModPath
	AssaultInfo._data_path = SavePath .. "AssaultInfoRAID.json"
	AssaultInfo._data = {}

	function AssaultInfo:Save()
		local file = io.open(self._data_path, "w+")
		if file then
			file:write(json.encode(self._data))
			file:close()
		end
	end

	function AssaultInfo:LoadDefaults()
		local default_file = io.open(self._path .. "default_values.json")
		if default_file then
			self._data = json.decode(default_file:read("*all"))
			default_file:close()
		end
	end

	function AssaultInfo:Load()
		self:LoadDefaults()
		local file = io.open(self._data_path, "r")
		if file then
			local config = json.decode(file:read("*all"))
			file:close()
			if config and type(config) == "table" then
				for k, v in pairs(config) do
					self._data[k] = v
				end
			end
		end
	end

	function AssaultInfo:GetOption(id)
		return self._data[id]
	end

	-- rebuilds the panel, so scale and alpha apply right away
	function AssaultInfo:OptionChanged()
		if self.recreate then
			self:recreate()
		end
	end

	AssaultInfo:Load()
	AssaultInfo.setup = true
end
