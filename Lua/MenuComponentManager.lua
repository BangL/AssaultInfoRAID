AssaultInfoMenu = AssaultInfoMenu or class(BLTMenu)

function AssaultInfoMenu:Init(root)
	self:Title({
		text = "assaultinfo_title",
	})

	self:AutoBindNamedControlsBegin()

	self:Label({
		text = nil,
		localize = false,
		h = 8,
	})
	self:_Toggle("enabled")
	self:_Toggle("show_stealth")
	self:SubTitle({ text = "", localize = false })
	self:_Toggle("show_time")
	self:_Toggle("show_enemies")
	self:_Toggle("show_kills_left")
	self:SubTitle({ text = "", localize = false })
	self:MultiChoice({
		name = "assaultinfo_align",
		text = "assaultinfo_align",
		desc = "assaultinfo_align_desc",
		value = AssaultInfo:GetOption("align"),
		callback = callback(self, self, "OnOptionChanged", "align"),
		items = {
			{ text_id = "assaultinfo_align_left", value = 1 },
			{ text_id = "assaultinfo_align_center", value = 2 },
			{ text_id = "assaultinfo_align_right", value = 3 },
		},
		auto_select_on_hover = true,
	})
	self:_Slider("y_pos", 0, 1, 2)
	self:_Slider("scale", 0.5, 2, 2)
	self:_Slider("background_alpha", 0, 1, 2)

	self._reset_btn = self:LongRoundedButton2({
		name = "assaultinfo_reset",
		text = "assaultinfo_reset",
		localize = true,
		callback = callback(self, self, "Reset"),
		ignore_align = true,
		y = 832,
		x = 1472,
		auto_select_on_hover = true,
	})
	self:AutoBindNamedControlsEnd()
end

function AssaultInfoMenu:_additional_active_controls()
	return {
		self._reset_btn,
	}
end

function AssaultInfoMenu:_Toggle(option)
	local id = "assaultinfo_" .. option
	self:Toggle({
		name = id,
		text = id,
		desc = id .. "_desc",
		value = AssaultInfo:GetOption(option),
		callback = callback(self, self, "OnOptionChanged", option),
		auto_select_on_hover = true,
	})
end

function AssaultInfoMenu:_Slider(option, min, max, decimals)
	local id = "assaultinfo_" .. option
	self:Slider({
		name = id,
		text = id,
		desc = id .. "_desc",
		value = AssaultInfo:GetOption(option),
		min = min,
		max = max,
		value_format = "%." .. decimals .. "f",
		callback = callback(self, self, "OnOptionChanged", option),
		auto_select_on_hover = true,
	})
end

function AssaultInfoMenu:OnOptionChanged(option, value)
	AssaultInfo._data[option] = type(value) == "table" and value.value or value
	AssaultInfo:OptionChanged()
end

function AssaultInfoMenu:Reset(value, item)
	QuickMenu:new(
		managers.localization:text("assaultinfo_reset"),
		managers.localization:text("assaultinfo_reset_confirm"),
		{
			{
				text = managers.localization:text("dialog_yes"),
				callback = function()
					AssaultInfo:LoadDefaults()
					self:ReloadMenu()
					AssaultInfo:OptionChanged()
				end,
			},
			{
				text = managers.localization:text("dialog_no"),
				is_cancel_button = true,
			},
		},
		true
	)
end

function AssaultInfoMenu:Close()
	AssaultInfo:Save()
end

Hooks:Add("MenuComponentManagerInitialize", "AssaultInfo.MenuComponentManagerInitialize", function(self)
	RaidMenuHelper:CreateMenu({
		name = "AssaultInfo_options",
		name_id = "assaultinfo_title",
		inject_list = "blt_options",
		icon = "waypoint_special_kill",
		class = AssaultInfoMenu,
	})
end)
