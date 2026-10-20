-- If the host runs AssaultInfo too, it sends its assault data (phase, times, enemies, kills) to the
-- clients that run it, using the same handshake scheme as PlayerInfo. Only peers that completed the
-- handshake (same protocol version) get anything, and only when the data changed: the clients count
-- the times down themselves. Clients without data from the host fall back to the reduced info they
-- can get on their own.
if not AssaultInfo.Sync then
	AssaultInfo.Sync = {
		msg_id = "AssaultInfo",
		peers = { false, false, false, false },
		events = {
			handshake = "handshake",
			state = "state",
			rejected = "rejected",
		},
		protocol_version = 1,
		TIME_TOLERANCE = 1.5, -- a time is resent when its end differs this much from what the clients count down to
		-- titles a client accepts, they are used as localization ids
		TITLES = {
			assaultinfo_anticipation = true,
			assaultinfo_build = true,
			assaultinfo_sustain = true,
			assaultinfo_fade = true,
			assaultinfo_stealth = true,
			assaultinfo_regroup = true,
			assaultinfo_next = true,
			assaultinfo_hunt = true,
		},
	}
	local Sync = AssaultInfo.Sync

	function Sync.table_to_string(tbl)
		return json.encode(tbl or {}) or ""
	end

	function Sync.string_to_table(str)
		local tbl = json.decode(str or "")
		return (type(tbl) == "table") and tbl or {}
	end

	function Sync:send_to_peer(peer_id, event, data)
		if peer_id and (peer_id ~= LuaNetworking:LocalPeerID()) and event then
			LuaNetworking:SendToPeer(peer_id, self.msg_id, self.table_to_string({
				e = event,
				d = (type(data) == "table") and data or nil,
			}))
		end
	end

	function Sync:send_to_known_peers(event, data)
		for peer_id, known in ipairs(self.peers) do
			if known and (peer_id ~= LuaNetworking:LocalPeerID()) then
				self:send_to_peer(peer_id, event, data)
			end
		end
	end

	function Sync:send_to_unknown_peers(event, data)
		for peer_id, known in ipairs(self.peers) do
			if (not known) and (peer_id ~= LuaNetworking:LocalPeerID()) then
				self:send_to_peer(peer_id, event, data)
			end
		end
	end

	function Sync:has_known_peers()
		for peer_id, known in ipairs(self.peers) do
			if known then
				return true
			end
		end
	end

	local function round(value)
		return value and math.floor(value * 10 + 0.5) / 10
	end

	-- absolute end times, so a time that is just counting down is not a change
	local function end_t(now, time_left)
		return time_left and now + time_left
	end

	local function end_changed(old, new, tolerance)
		if (old == nil) ~= (new == nil) then
			return true
		end
		return old ~= nil and math.abs(old - new) > tolerance
	end

	-- host: called every frame with the current info, sends it to the known peers if it changed
	function Sync:host_tick(title, time_left, enemies, force, pool, total_left)
		if not (Network:is_server() and LuaNetworking:IsMultiplayer() and self:has_known_peers()) then
			return
		end

		local now = Application:time()
		local key = title or "none"
		pool = pool and math.floor(pool)
		local sent = self._sent
		local tl_end = end_t(now, time_left)
		local tt_end = end_t(now, total_left)
		if sent and sent.key == key and sent.enemies == enemies and sent.force == force and sent.pool == pool
			and not end_changed(sent.tl_end, tl_end, self.TIME_TOLERANCE)
			and not end_changed(sent.tt_end, tt_end, self.TIME_TOLERANCE) then
			return
		end
		self._sent = { key = key, enemies = enemies, force = force, pool = pool, tl_end = tl_end, tt_end = tt_end }

		self:send_to_known_peers(self.events.state, {
			t = key,
			tl = round(time_left),
			e = enemies,
			f = force,
			p = pool,
			tt = round(total_left),
		})
	end

	-- client: the host's data with the times counted down since it arrived, nil if there is none
	function Sync:get_synced()
		local state = self._state
		if Network:is_server() or not (self.peers[1] and state) then
			return
		end
		local age = Application:time() - state.received_t
		return {
			title = state.title,
			time_left = state.time_left and state.time_left - age,
			enemies = state.enemies,
			force = state.force,
			pool = state.pool,
			total_left = state.total_left and state.total_left - age,
		}
	end

	function Sync:receive(sender, msg_id, payload)
		sender = tonumber(sender)
		if not sender or (msg_id ~= self.msg_id) then
			return
		end

		local msg = self.string_to_table(payload)
		local event = msg.e
		if string.is_nil_or_empty(event) then
			return
		end

		local data = (type(msg.d) == "table") and msg.d or {}
		if self.events[event] and self[event] then
			self[event](self, sender, data)
		elseif event ~= self.events.rejected then
			self:send_to_peer(sender, self.events.rejected, { reason = "event unknown." })
		end
	end

	function Sync:handshake(peer_id, data)
		if not managers.network:session():peer(peer_id) then
			return
		end

		if tostring(data.version) ~= tostring(self.protocol_version) then
			log("[AssaultInfo.Sync handshake] peer " .. tostring(peer_id) .. " uses protocol " .. tostring(data.version) .. ", we use " .. tostring(self.protocol_version) .. " - skipping.")
			return
		end

		if not self.peers[peer_id] then
			self:send_to_peer(peer_id, self.events.handshake, { version = self.protocol_version })
			self.peers[peer_id] = true
			self._sent = nil -- send the current state right away
			log("[AssaultInfo.Sync] peer " .. tostring(peer_id) .. " runs AssaultInfo too.")
		end
	end

	-- only the host's data counts
	function Sync:state(peer_id, data)
		if peer_id ~= 1 or Network:is_server() then
			return
		end

		local title = data.t
		if title ~= "none" and not self.TITLES[title] then
			return
		end

		self._state = {
			title = title ~= "none" and title or nil,
			time_left = tonumber(data.tl),
			enemies = tonumber(data.e),
			force = tonumber(data.f),
			pool = tonumber(data.p),
			total_left = tonumber(data.tt),
			received_t = Application:time(),
		}
	end

	function Sync:reset_peer(peer_id)
		self.peers[peer_id] = false
		if peer_id == 1 then
			self._state = nil
		end
	end
end

Hooks:Add("BaseNetworkSessionOnLoadComplete", "AssaultInfo.Sync_BaseNetworkSessionOnLoadComplete", function(local_peer, id)
	if AssaultInfo.Sync and LuaNetworking:IsMultiplayer() then
		AssaultInfo.Sync:send_to_unknown_peers(AssaultInfo.Sync.events.handshake, { version = AssaultInfo.Sync.protocol_version })
	end
end)

Hooks:Add("BaseNetworkSessionOnPeerEnteredLobby", "AssaultInfo.Sync_BaseNetworkSessionOnPeerEnteredLobby", function(peer, peer_id)
	if AssaultInfo.Sync and LuaNetworking:IsMultiplayer() then
		AssaultInfo.Sync:send_to_peer(peer_id or peer:id(), AssaultInfo.Sync.events.handshake, { version = AssaultInfo.Sync.protocol_version })
	end
end)

Hooks:Add("BaseNetworkSessionOnPeerRemoved", "AssaultInfo.Sync_BaseNetworkSessionOnPeerRemoved", function(peer, peer_id, reason)
	if AssaultInfo.Sync then
		AssaultInfo.Sync:reset_peer(peer_id)
	end
end)

Hooks:Add("NetworkReceivedData", "AssaultInfo.Sync_NetworkReceivedData", function(sender, msg_id, payload)
	if AssaultInfo.Sync then
		AssaultInfo.Sync:receive(sender, msg_id, payload)
	end
end)
