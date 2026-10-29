-- The assault task (phase, timers, force, pool) lives in the host's group AI. A client only gets the
-- stealth state (mission element), the hunt flag (sync_assault_endless) and assault on/off (sync_assault_mode),
-- unless the host runs AssaultInfo too (see Sync.lua).

local PANEL_W = 260
local MIN_TITLE_SIZE = 16
local MARGIN = 8
local PHASE_COLORS = {
	assaultinfo_anticipation = "raid_gold",
	assaultinfo_build = "progress_orange",
	assaultinfo_sustain = "raid_red",
	assaultinfo_fade = "progress_green",
	assaultinfo_assault = "raid_red",
	assaultinfo_stealth = "raid_white",
	assaultinfo_hunt = "raid_dark_red",
	assaultinfo_regroup = "raid_grey",
	assaultinfo_next = "raid_grey",
}
local UPDATE_ID = "AssaultInfo_update"

local function fmt_time(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- title id, phase time left, enemies in assault groups, force, kills left, total time left, enemies alive (any may be nil)
function AssaultInfo:get_client_info()
	local gai = managers.groupai and managers.groupai:state()
	if not gai then
		return
	end

	if gai:whisper_mode() and managers.raid_job and managers.raid_job:current_job() then
		return AssaultInfo:GetOption("show_stealth") and "assaultinfo_stealth" or nil
	end
	if gai._hunt_mode and gai:get_assault_mode() then
		return "assaultinfo_hunt"
	end
	if gai:get_assault_mode() then
		return "assaultinfo_assault"
	end
end

-- Every living enemy. The assault count of the game only has the units of assault groups: the retiring ones, snipers and
-- the like are not in it, and a group is spawned as a whole, so it can be above the force.
function AssaultInfo:count_alive()
	local t = Application:time()
	if not self._alive_t or t > self._alive_t then
		self._alive_t = t + 0.25
		local n = 0
		for _ in pairs(managers.enemy:all_enemies()) do
			n = n + 1
		end
		self._alive = n
	end
	return self._alive
end

function AssaultInfo:get_info()
	-- the camp is a world point that gets despawned for missions; a selected job does not mean we left it
	if managers.raid_job and managers.raid_job:is_camp_loaded() then
		return
	end

	if not Network:is_server() then
		-- the host runs AssaultInfo too: its data, else what the client gets on its own
		local synced = AssaultInfo.Sync and AssaultInfo.Sync:get_synced()
		if synced then
			return synced.title, synced.time_left, synced.enemies, synced.force, synced.pool, synced.total_left, synced.alive
		end
		return self:get_client_info()
	end

	local gai = managers.groupai and managers.groupai:state()
	local task_data = gai and gai._task_data
	local tweak = gai and gai._tweak_data and gai._tweak_data.assault
	if not (task_data and tweak and gai._t) then
		return
	end

	if gai:whisper_mode() and managers.raid_job and managers.raid_job:current_job() then
		if AssaultInfo:GetOption("show_stealth") then
			return "assaultinfo_stealth"
		end
		return
	end

	local assault = task_data.assault
	if assault.active and assault.phase then
		local pool = gai:get_difficulty_dependent_value(tweak.spawn_pool) * gai:_get_balancing_multiplier(tweak.spawn_pool_balance_mul)
		local time_left = assault.phase_end_t and assault.phase_end_t - gai._t
		if gai._hunt_mode then
			return "assaultinfo_hunt", nil, gai:_count_police_force("assault"), assault.force, nil, nil, self:count_alive()
		end

		-- remaining phases after the current one, sustain at its average duration
		local total_left
		if assault.phase == "build" or assault.phase == "sustain" then
			total_left = time_left
			if assault.phase == "build" then
				local sustain_min = gai:get_difficulty_dependent_value(tweak.sustain_duration_min)
				local sustain_max = gai:get_difficulty_dependent_value(tweak.sustain_duration_max)
				total_left = total_left + math.lerp(sustain_min, sustain_max, 0.5) * gai:_get_balancing_multiplier(tweak.sustain_duration_balance_mul)
			end
			total_left = total_left + tweak.fade_duration
		end
		return "assaultinfo_" .. assault.phase, time_left, gai:_count_police_force("assault"), assault.force, pool - assault.casualties, total_left, self:count_alive()
	end

	if task_data.regroup.active then
		return "assaultinfo_regroup", task_data.regroup.end_t - gai._t
	end

	if assault.next_dispatch_t then
		return "assaultinfo_next", assault.next_dispatch_t - gai._t
	end
end

function AssaultInfo:create(hud)
	if alive(self._panel) then
		self._panel:parent():remove(self._panel)
	end

	self._hud = hud
	local colors = tweak_data.gui.colors
	local scale = AssaultInfo:GetOption("scale")
	local title_size = math.round(tweak_data.gui.font_sizes.size_32 * scale)
	local row_size = math.round(tweak_data.gui.font_sizes.size_20 * scale)
	self._w = math.round(PANEL_W * scale)
	self._pad = math.round(14 * scale)
	local font = tweak_data.gui.fonts.din_compressed
	local title_font = tweak_data.gui:get_font_path(font, title_size)
	local row_font = tweak_data.gui:get_font_path(font, row_size)

	self._title_size = title_size
	self._row_h = row_size + math.round(4 * scale)
	self._title_h = title_size + math.round(10 * scale)
	self._panel = hud.panel:panel({
		name = "assault_info_panel",
		w = self._w,
		h = self._title_h,
		layer = 5,
		visible = false,
	})
	self._h = nil
	self._last_title = nil

	self._bg = self._panel:rect({
		color = colors.raid_black,
		alpha = AssaultInfo:GetOption("background_alpha"),
		layer = -2,
	})
	self._title_bg = self._panel:rect({
		color = colors.raid_red,
		alpha = 0.25,
		h = self._title_h,
		layer = -1,
	})
	self._accent = self._panel:rect({
		color = colors.raid_red,
		w = math.max(2, math.round(4 * scale)),
		layer = 1,
	})
	self._title = self._panel:text({
		name = "title",
		text = "",
		font = title_font,
		font_size = title_size,
		color = colors.raid_red,
		x = self._pad,
		y = 0,
		w = self._w - self._pad - 10,
		h = self._title_h,
		vertical = "center",
		layer = 2,
	})
	self._time = self._panel:text({
		name = "time",
		text = "",
		font = title_font,
		font_size = title_size,
		color = colors.raid_white,
		x = self._pad,
		y = 0,
		w = self._w - self._pad - 10,
		h = self._title_h,
		align = "right",
		vertical = "center",
		layer = 2,
	})

	self._rows = {}
	for i, name in ipairs({ "enemies", "pool" }) do
		local y = self._title_h + math.round(4 * scale) + (i - 1) * self._row_h
		-- label and value get their own half, overlapping text widgets sometimes lose one of them
		local half_w = math.floor((self._w - self._pad - 10) / 2)
		local function text(align, color, x)
			return self._panel:text({
				text = "",
				font = row_font,
				font_size = row_size,
				color = color,
				x = x,
				y = y,
				w = half_w,
				h = self._row_h,
				align = align,
				vertical = "center",
				layer = 2,
			})
		end
		self._rows[name] = {
			label = text("left", colors.raid_grey, self._pad),
			value = text("right", colors.raid_white, self._pad + half_w),
		}
	end

	managers.hud:add_updator(UPDATE_ID, callback(self, self, "update"))
end

-- puts the row at the next free slot, hidden rows leave no gap
-- only touch a text when it changes, re-setting it every frame makes widgets flicker/vanish
local function set_text(widget, text)
	if widget:text() ~= text then
		widget:set_text(text)
		return true
	end
end

function AssaultInfo:set_row(name, slot, label, value)
	local row = self._rows[name]
	set_text(row.label, label or "")
	set_text(row.value, value or "")
	if label then
		local y = self._title_h + math.round(4 * AssaultInfo:GetOption("scale")) + (slot - 1) * self._row_h
		row.label:set_y(y)
		row.value:set_y(y)
	end
	return label ~= nil
end

-- shrink the title until it fits next to the time
function AssaultInfo:fit_title()
	local time_w = select(3, self._time:text_rect())
	local avail = self._w - self._pad - 10 - time_w - 12
	local size = self._title_size
	self._title:set_font_size(size)
	while size > MIN_TITLE_SIZE * AssaultInfo:GetOption("scale") and select(3, self._title:text_rect()) > avail do
		size = size - 1
		self._title:set_font_size(size)
	end
end

-- exponential approach, framerate independent
local function approach(current, target, dt, speed)
	return math.lerp(current, target, 1 - math.exp(-dt * speed))
end

-- catch and log errors once per message (plain pcall/xpcall are not available, blt.pcall is)
function AssaultInfo:update(t, dt)
	local ok, err = blt.pcall(self._update, self, t, dt)
	if not ok and err ~= self._last_error then
		self._last_error = err
		log("[AssaultInfo] update error: " .. tostring(err))
	end
end

function AssaultInfo:_update(t, dt)
	if not alive(self._panel) then
		managers.hud:remove_updator(UPDATE_ID)
		return
	end

	local title, time_left, enemies, force, pool, total_left, alive = self:get_info()
	if Network:is_server() and AssaultInfo.Sync then
		-- the clients get the data whether our own box is enabled or not
		AssaultInfo.Sync:host_tick(title, time_left, enemies, force, pool, total_left, alive)
	end
	if not AssaultInfo:GetOption("enabled") then
		title = nil
	end

	self._panel:set_visible(title ~= nil)
	if not title then
		return
	end

	local loc = managers.localization
	local color = tweak_data.gui.colors[PHASE_COLORS[title] or "raid_red"]
	if title ~= self._last_title then
		-- phase change: flash the title strip and slide the title in
		self._flash = self._last_title and 1 or 0
		self._last_title = title
		set_text(self._title, loc:text(title))
		self._fit_dirty = true
		self._color = self._color or color
	end
	self._color = math.lerp(self._color, color, 1 - math.exp(-dt * 6))
	self._flash = math.max(0, self._flash - dt / 0.7)

	local flash = self._flash * self._flash
	self._title:set_color(self._color)
	self._title:set_alpha(1 - 0.6 * flash)
	self._title:set_x(self._pad + math.round(16 * AssaultInfo:GetOption("scale")) * flash)
	self._title_bg:set_color(self._color)
	self._title_bg:set_alpha(0.25 + 0.45 * flash)
	self._accent:set_color(self._color)
	-- total time until the assault ends where it can be estimated, else the time of the current phase
	local shown = total_left or time_left
	local time_changed = set_text(self._time, shown and AssaultInfo:GetOption("show_time") and (shown < 0 and loc:text("assaultinfo_overdue") or (total_left and "~" or "") .. fmt_time(shown)) or "")
	if time_changed or self._fit_dirty then
		self._fit_dirty = nil
		self:fit_title()
	end

	local rows = 0
	local show_enemies = enemies and AssaultInfo:GetOption("show_enemies")
	local show_pool = pool and AssaultInfo:GetOption("show_kills_left")
	rows = rows + (self:set_row("enemies", rows + 1, show_enemies and loc:text("assaultinfo_enemies"), show_enemies and (alive and string.format("%d  (%d / %d)", alive, enemies, force) or string.format("%d / %d", enemies, force))) and 1 or 0)
	rows = rows + (self:set_row("pool", rows + 1, show_pool and loc:text("assaultinfo_pool"), show_pool and string.format("%d", math.max(0, math.floor(pool)))) and 1 or 0)

	local target_h = self._title_h + (rows > 0 and math.round(8 * AssaultInfo:GetOption("scale")) + rows * self._row_h or 0)
	self._h = target_h
	self._panel:set_h(self._h)
	self._bg:set_h(self._h)
	self._accent:set_h(self._h)
	self:position(self._h)
end

-- horizontal anchor from the "align" option, top edge at "y_pos" of the screen height (kept on screen)
function AssaultInfo:position(h)
	local hud_panel = self._hud.panel
	local align = AssaultInfo:GetOption("align")
	if align == 1 then
		self._panel:set_left(MARGIN)
	elseif align == 2 then
		self._panel:set_center_x(hud_panel:w() / 2)
	else
		self._panel:set_right(hud_panel:w() - MARGIN)
	end
	self._panel:set_top(math.clamp(AssaultInfo:GetOption("y_pos") * hud_panel:h(), 0, math.max(0, hud_panel:h() - h)))
end

function AssaultInfo:recreate()
	if self._hud and alive(self._hud.panel) then
		self:create(self._hud)
	end
end

Hooks:PostHook(HUDManager, "_setup_ingame_hud_saferect", "AssaultInfo_HUDManager_post_setup_ingame_hud_saferect", function(self)
	if not self:alive(PlayerBase.INGAME_HUD_SAFERECT) then
		return
	end
	AssaultInfo:create(self:script(PlayerBase.INGAME_HUD_SAFERECT))
end)
