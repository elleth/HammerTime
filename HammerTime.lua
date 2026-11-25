-- HammerTime: one button (and one keybind) that repairs your most damaged
-- piece with the Thalassian Master Repair Hammer. Press it repeatedly to
-- work through every damaged slot.

local HAMMER = "Thalassian Master Repair Hammer"

-- Equipment slots the hammer can plausibly work on (plate armor + weapons).
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17 }
local SLOT_NAMES = {
	[1] = "Head", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs",
	[8] = "Feet", [9] = "Wrists", [10] = "Hands", [16] = "Main hand", [17] = "Off hand",
}

local DEFAULTS = {
	threshold = 95,                          -- show button when a slot is below this %
	skip = {},                               -- slots you can't repair with the hammer
	point = { "CENTER", "CENTER", 0, -150 }, -- saved position
}

local db

-- Binding labels (Esc > Options > Keybindings > AddOns)
BINDING_HEADER_HAMMERTIME = "HammerTime"
_G["BINDING_NAME_CLICK HammerTimeButton:LeftButton"] = "Repair next damaged piece"

---------------------------------------------------------------------------
-- The secure button
---------------------------------------------------------------------------
local btn = CreateFrame("Button", "HammerTimeButton", UIParent, "SecureActionButtonTemplate")
btn:SetSize(48, 48)
btn:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:RegisterForDrag("LeftButton")
btn:SetAttribute("type", "macro")
btn:Hide()

btn.icon = btn:CreateTexture(nil, "ARTWORK")
btn.icon:SetAllPoints()
btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

btn.border = btn:CreateTexture(nil, "OVERLAY")
btn.border:SetPoint("TOPLEFT", -1, 1)
btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
btn.border:SetColorTexture(0, 0, 0, 1)
btn.border:SetDrawLayer("BACKGROUND")

btn.pct = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
btn.pct:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)

btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
btn.count:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)

btn:SetScript("OnDragStart", function(self)
	if IsShiftKeyDown() and not InCombatLockdown() then
		self:StartMoving()
	end
end)

btn:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	if db then db.point = { p, rp, x, y } end
end)

btn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.slot then
		GameTooltip:AddLine("Next: " .. (SLOT_NAMES[self.slot] or self.slot))
	end
	GameTooltip:AddLine("Click or use your keybind to repair.", 1, 1, 1)
	GameTooltip:AddLine("Shift-drag to move.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------
local pending = false

-- Returns the most damaged eligible slot, its durability %, and how many
-- slots are below the threshold.
local function Scan()
	local worstSlot, worstPct, n = nil, nil, 0
	for _, slot in ipairs(SLOTS) do
		if not db.skip[slot] then
			local cur, max = GetInventoryItemDurability(slot)
			if cur and max and max > 0 then
				local pct = cur / max * 100
				if pct < db.threshold then
					n = n + 1
					if not worstPct or pct < worstPct then
						worstSlot, worstPct = slot, pct
					end
				end
			end
		end
	end
	return worstSlot, worstPct, n
end

local function Refresh()
	if not db then return end
	-- Secure attributes and Show/Hide are locked in combat; catch up afterwards.
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false

	local slot, pct, n = Scan()
	local hasHammer = (C_Item.GetItemCount(HAMMER) or 0) > 0

	if slot and hasHammer then
		btn.slot = slot
		btn:SetAttribute("macrotext", "/use " .. HAMMER .. "\n/use " .. slot)
		btn.icon:SetTexture(GetInventoryItemTexture("player", slot))
		btn.pct:SetText(string.format("%d%%", pct))
		if pct < 25 then
			btn.pct:SetTextColor(1, 0.2, 0.2)
		elseif pct < 60 then
			btn.pct:SetTextColor(1, 0.82, 0)
		else
			btn.pct:SetTextColor(1, 1, 1)
		end
		btn.count:SetText(n > 1 and n or "")
		btn:Show()
	else
		btn.slot = nil
		btn:Hide()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= "HammerTime" then return end
		HammerTimeDB = HammerTimeDB or {}
		db = HammerTimeDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then
				if type(v) == "table" then
					db[k] = CopyTable(v)
				else
					db[k] = v
				end
			end
		end
		btn:ClearAllPoints()
		btn:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then Refresh() end
	else
		Refresh()
	end
end)

---------------------------------------------------------------------------
-- Slash command: /hammer
---------------------------------------------------------------------------
SLASH_HAMMERTIME1 = "/hammer"
SLASH_HAMMERTIME2 = "/hammertime"
SlashCmdList["HAMMERTIME"] = function(msg)
	if not db then return end
	local cmd, arg = msg:match("^(%S*)%s*(%S*)")
	cmd = (cmd or ""):lower()

	if cmd == "threshold" then
		local v = tonumber(arg)
		if v and v >= 1 and v <= 100 then
			db.threshold = v
			print("|cff66ccffHammerTime|r: showing when below " .. v .. "%.")
			Refresh()
		else
			print("|cff66ccffHammerTime|r: usage /hammer threshold 1-100")
		end
	elseif cmd == "skip" then
		local s = tonumber(arg)
		if s and SLOT_NAMES[s] then
			db.skip[s] = not db.skip[s] or nil
			print("|cff66ccffHammerTime|r: " .. SLOT_NAMES[s] .. (db.skip[s] and " will be skipped." or " is back in rotation."))
			Refresh()
		else
			print("|cff66ccffHammerTime|r: usage /hammer skip <slot>. Slots:")
			for _, slot in ipairs(SLOTS) do
				print(string.format("  %d = %s%s", slot, SLOT_NAMES[slot], db.skip[slot] and " (skipped)" or ""))
			end
		end
	elseif cmd == "reset" then
		db.point = CopyTable(DEFAULTS.point)
		btn:ClearAllPoints()
		btn:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	else
		print("|cff66ccffHammerTime|r commands:")
		print("  /hammer threshold <1-100>  - show button below this durability % (now " .. db.threshold .. ")")
		print("  /hammer skip <slot>        - toggle a slot you can't hammer-repair")
		print("  /hammer reset              - reset button position")
	end
end
