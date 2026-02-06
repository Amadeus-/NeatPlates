
	--Spinning Cooldown Frame
	--[[
	frame.Cooldown = CreateFrame("Cooldown", nil, frame, "NeatPlatesAuraWidgetCooldown")
	frame.Cooldown:SetAllPoints(frame)
	frame.Cooldown:SetReverse(true)
	frame.Cooldown:SetHideCountdownNumbers(true)
	--]]

local LibClassicDurations
local _UnitAura = UnitAura

-- 12.0.0+ Secret Value Handling:
-- In WoW 12.0.0+, aura data fields can be "secret values" during combat that cannot be
-- compared, printed, or used as table keys. However, display APIs (SetTexture, SetText,
-- SetCooldown) all accept secret values with SecretArguments = "AllowedWhenTainted".
--
-- Key APIs that return usable values even with secrets:
-- - C_UnitAuras.GetAuraDuration(unit, auraInstanceID) -> LuaDurationObject (for cooldowns)
-- - C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, min, max) -> string (for stacks)
-- - C_UnitAuras.GetAuraBaseDuration(unit, auraInstanceID) -> number (for pandemic)
-- - issecretvalue(value) -> checks if a value is secret before comparison
--
-- NOTE: UnitIsUnit() does NOT accept secret values. Use isFromPlayerOrPlayerPet field instead.

-- Check if we have the modern 12.0.0+ APIs with secret value support
local HAS_SECRET_VALUE_SUPPORT = (issecretvalue ~= nil)
local HAS_DURATION_OBJECT_API = (C_UnitAuras and C_UnitAuras.GetAuraDuration ~= nil)
local HAS_STACK_DISPLAY_API = (C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount ~= nil)
local HAS_BASE_DURATION_API = (C_UnitAuras and C_UnitAuras.GetAuraBaseDuration ~= nil)

-- Helper function to safely check if caster is the player
-- In 12.0.0+, sourceUnit can be a secret value that cannot be used with UnitIsUnit
-- We prefer the isFromPlayerOrPlayerPet field when available, otherwise check for secret
local function IsCasterPlayer(sourceUnit, isFromPlayerOrPlayerPet)
	-- Prefer the boolean flag if available (works with secrets, doesn't require UnitIsUnit)
	if isFromPlayerOrPlayerPet ~= nil then
		-- The flag itself might be secret in some edge cases
		if HAS_SECRET_VALUE_SUPPORT and issecretvalue(isFromPlayerOrPlayerPet) then
			return false  -- Can't determine, assume not player
		end
		return isFromPlayerOrPlayerPet
	end
	-- Fallback to UnitIsUnit only if sourceUnit is not nil and not secret
	if sourceUnit == nil then return false end
	if HAS_SECRET_VALUE_SUPPORT and issecretvalue(sourceUnit) then
		return false  -- Can't use UnitIsUnit with secret values
	end
	return UnitIsUnit("player", sourceUnit)
end

-- Helper function to safely get a value, returning nil if it's secret
local function SafeValue(value)
	if HAS_SECRET_VALUE_SUPPORT and issecretvalue(value) then
		return nil
	end
	return value
end

-- Filter modes for "Show Mine" vs "Show All" - set via SetAuraFilterModes()
-- Values: 1 = Show None, 2 = Show Mine, 3 = Show All
-- IMPORTANT: These must be declared BEFORE _GetUnitAurasForNameplate so the function
-- captures these locals in its closure, not nonexistent globals
local WidgetDebuffFilterMode = 3  -- Default to Show All
local WidgetBuffFilterMode = 1    -- Default to Show None

-- 12.0.0+: Use C_UnitAuras.GetUnitAuras() which returns full aura data tables
-- The data fields may be secret values, but we handle that when displaying
local _GetUnitAurasForNameplate = nil
if C_UnitAuras and C_UnitAuras.GetUnitAuras then
	-- Function to get all auras for a unit
	-- Returns raw aura data with auraInstanceID preserved for later API calls
	-- Uses |PLAYER filter when "Show Mine" mode is active to filter server-side
	_GetUnitAurasForNameplate = function(unit)
		local auras = {}
		local seenIds = {}

		-- Debug: Log API calls
		if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
			NeatPlatesUtility.Debug.Log("Aura", "_GetUnitAurasForNameplate called for: " .. tostring(unit))
			NeatPlatesUtility.Debug.Log("Aura", "  WidgetDebuffFilterMode: " .. tostring(WidgetDebuffFilterMode))
			NeatPlatesUtility.Debug.Log("Aura", "  WidgetBuffFilterMode: " .. tostring(WidgetBuffFilterMode))
		end

		-- Build filter strings based on "Show Mine" vs "Show All" settings
		-- Filter mode 2 = "Show Mine" -> append |PLAYER to filter server-side
		-- Filter mode 3 = "Show All" -> no |PLAYER, get all auras
		-- Filter mode 1 = "Show None" -> we still fetch, but they'll be filtered out later
		local debuffPlayerFilter = (WidgetDebuffFilterMode == 2) and "|PLAYER" or ""
		local buffPlayerFilter = (WidgetBuffFilterMode == 2) and "|PLAYER" or ""

		-- First, get nameplate-specific auras (always include these for proper nameplate display)
		-- For nameplate auras, also apply the |PLAYER filter when "Show Mine" is active
		local debuffNPFilter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY" .. debuffPlayerFilter
		local buffNPFilter = "HELPFUL|INCLUDE_NAME_PLATE_ONLY" .. buffPlayerFilter

		local debuffsNP = C_UnitAuras.GetUnitAuras(unit, debuffNPFilter) or {}
		local buffsNP = C_UnitAuras.GetUnitAuras(unit, buffNPFilter) or {}

		-- Debug: Log counts from each filter
		if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
			NeatPlatesUtility.Debug.Log("Aura", "  Filter: " .. debuffNPFilter .. " -> " .. #debuffsNP .. " auras")
			NeatPlatesUtility.Debug.Log("Aura", "  Filter: " .. buffNPFilter .. " -> " .. #buffsNP .. " auras")
		end

		for _, auraData in ipairs(debuffsNP) do
			if not seenIds[auraData.auraInstanceID] then
				seenIds[auraData.auraInstanceID] = true
				auraData.isHarmful = true
				auraData.isHelpful = false
				table.insert(auras, auraData)
			end
		end

		for _, auraData in ipairs(buffsNP) do
			if not seenIds[auraData.auraInstanceID] then
				seenIds[auraData.auraInstanceID] = true
				auraData.isHarmful = false
				auraData.isHelpful = true
				table.insert(auras, auraData)
			end
		end

		-- Also get other auras (for custom aura lists that might reference non-nameplate auras)
		-- Skip these passes when "Show Important Auras Only" is enabled
		if not ShowImportantAurasOnly then
			-- Apply |PLAYER filter when "Show Mine" is active
			local debuffFilter = "HARMFUL" .. debuffPlayerFilter
			local buffFilter = "HELPFUL" .. buffPlayerFilter

			local allDebuffs = C_UnitAuras.GetUnitAuras(unit, debuffFilter) or {}
			local allBuffs = C_UnitAuras.GetUnitAuras(unit, buffFilter) or {}

			-- Debug: Log counts from each filter
			if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
				NeatPlatesUtility.Debug.Log("Aura", "  Filter: " .. debuffFilter .. " -> " .. #allDebuffs .. " auras")
				NeatPlatesUtility.Debug.Log("Aura", "  Filter: " .. buffFilter .. " -> " .. #allBuffs .. " auras")
			end

			for _, auraData in ipairs(allDebuffs) do
				if not seenIds[auraData.auraInstanceID] then
					seenIds[auraData.auraInstanceID] = true
					auraData.isHarmful = true
					auraData.isHelpful = false
					table.insert(auras, auraData)
				end
			end

			for _, auraData in ipairs(allBuffs) do
				if not seenIds[auraData.auraInstanceID] then
					seenIds[auraData.auraInstanceID] = true
					auraData.isHarmful = false
					auraData.isHelpful = true
					table.insert(auras, auraData)
				end
			end
		end

		-- Debug: Log final count
		if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
			NeatPlatesUtility.Debug.Log("Aura", "  Total unique auras: " .. #auras)
		end

		return auras
	end

	-- Legacy wrapper for backwards compatibility (uses GetAuraDataByIndex)
	_UnitAura = function(unit, index, filter)
		local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if not auraData then return nil end
		-- Return fields directly from table (may be secret, but callers should handle that)
		return auraData.name, auraData.icon, auraData.applications, auraData.dispelName,
		       auraData.duration, auraData.expirationTime, auraData.sourceUnit,
		       auraData.isStealable, auraData.nameplateShowPersonal, auraData.spellId,
		       auraData.canApplyAura, auraData.isBossAura, auraData.isFromPlayerOrPlayerPet,
		       auraData.nameplateShowAll
	end
end

if NEATPLATES_IS_CLASSIC_ERA then
	-- Classic Era uses different aura handling, disable the modern GetUnitAuras approach
	_GetUnitAurasForNameplate = nil
	LibClassicDurations = LibStub("LibClassicDurations", true)
	if LibClassicDurations then
		LibClassicDurations:Register("NeatPlates")
		_UnitAura = LibClassicDurations.UnitAuraWithBuffs
	else
		_UnitAura = function() end
	end
end

-- IsSpellKnown compatibility wrapper (deprecated in 12.0, moved to C_SpellBook)
local IsSpellKnown = C_SpellBook and C_SpellBook.IsSpellKnown or IsSpellKnown

NeatPlatesWidgets.DebuffWidgetBuild = 2

-- Debug flag for aura tracing - toggle with /npdebug auras
NEATPLATES_DEBUG_AURAS = false

-- Helper function for debug output
local function DebugAura(msg)
	if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
		NeatPlatesUtility.Debug.Log("Aura", msg)
	end
end

local PlayerGUID = UnitGUID("player")
local FilterFunction = function() return 1 end
local AuraMonitor = CreateFrame("Frame")
local WatcherIsEnabled = false
local WidgetList, WidgetGUID = {}, {}

local UpdateWidget

local TargetOfGroupMembers = {}
local DebuffColumns = 3
local DebuffLimit = 6
local AuraLimit = 9
local inArena = false
local useWideIcons = true
local SpacerSlots = 0 -- math.min(15, DebuffColumns-1)

local PandemicEnabled = false
local PandemicColor = {}

-- Note: WidgetDebuffFilterMode and WidgetBuffFilterMode are declared earlier in the file
-- (before _GetUnitAurasForNameplate) so they're properly captured in the closure

local EmphasizedUnique = false
local MaxEmphasizedAuras = 1
local AuraWidth = 16.5
local AuraScale = 1
local EmphasizedAuraScale = 1
local AuraAlignment = "BOTTOMLEFT"
-- local ScaleOptions = {x = 1, y = 1, offset = {x = 0, y = 0}}
local EmphasizedScaleOptions = {x = 1, y = 1, offset = {x = 0, y = 0}}
local PreciseAuraThreshold = 0
local BuffSeparationMode = 1
local HideInHeadlineMode = false
local BlizzardStyleIcons = false

local function DummyFunction() end

local function DefaultPreFilterFunction() return true end
local function DefaultFilterFunction(aura, unit) if aura and aura.duration and (aura.duration < 30) then return true end end

local AuraFilterFunction = DefaultFilterFunction
local EmphasizedAuraFilterFunction = function() end
local AuraSortFunction = function() end
local AuraHookFunction
local AuraCache = {}
local AuraBaseDuration = {}

local AURA_TARGET_HOSTILE = 1
local AURA_TARGET_FRIENDLY = 2

local AURA_TYPE_BUFF = 1
local AURA_TYPE_DEBUFF = 6

local ButtonGlow = LibStub("LibButtonGlow-1.0")
local ButtonGlowEnabled = {
		["Pandemic"] = false,
		["Magic"] = false,
		[""] = false, -- Enrage
	}

local HideCooldownSpiral = false
local HideAuraDuration = false
local HideAuraStacks = false
local ShowAuraTooltip = true
local ShowImportantAurasOnly = true

-- Get a clean version of the function...  Avoid OmniCC interference
-- local CooldownNative = CreateFrame("Cooldown", nil, WorldFrame)
-- local SetCooldown = CooldownNative.SetCooldown

local _

local AuraType_Index = {
	["Buff"] = 1,
	["Curse"] = 2,
	["Disease"] = 3,
	["Magic"] = 4,
	["Poison"] = 5,
	["Debuff"] = 6,
}

local function SetFilter(func)
	if func and type(func) == "function" then
		FilterFunction = func
	end
end

local function GetAuraWidgetByGUID(guid)
	if guid then return WidgetGUID[guid] end
end

local function IsAuraShown(widget, aura)
		if widget and widget:IsShown() then
			return true
		end
	return false
end


-----------------------------------------------------
-- Default Filter
-----------------------------------------------------
local function DefaultFilterFunction(debuff)
	if (debuff.duration < 600) then
		return true
	end
end


-----------------------------------------------------
-- General Events
-----------------------------------------------------


local function EventUnitAura(unitid, updateInfo)
	local frame

	if unitid then frame = WidgetList[unitid] end

	if frame then UpdateWidget(frame) end

end

-- Clear the AuraCache for the unitid
local function ClearAuraCache(unitid)
	if unitid then AuraCache[unitid] = nil end
end

-----------------------------------------------------
-- Function Reference Lists
-----------------------------------------------------

local AuraEvents = {
	--["UNIT_TARGET"] = EventUnitTarget,
	["UNIT_AURA"] = EventUnitAura,
	["NAME_PLATE_UNIT_REMOVED"] = ClearAuraCache,
}

local function AuraEventHandler(frame, event, ...)
	local unitid = ...

	if event then
		local eventFunction = AuraEvents[event]
		eventFunction(...)
	end

end



-------------------------------------------------------------
-- Widget Object Functions
-------------------------------------------------------------

-- UpdateWidgetTime: REMOVED (old custom timer text system)
-- Timer display is now handled entirely by Blizzard's built-in CooldownFrame countdown numbers
-- via SetCooldownFromDurationObject. This function is kept as a no-op for safety.
local function UpdateWidgetTime(frame, expiration)
end

local function UpdateAuraHighlighting(frame, aura)
		local r, g, b, a = aura.r, aura.g, aura.b, aura.a
		local glowType = aura.type  -- May be secret but not used in comparisons here
		local duration = aura.duration or 0
		local expirationTime = aura.expiration or 0
		local baseduration = aura.baseduration or duration
		local expiration = expirationTime > 0 and (expirationTime - GetTime()) or 0
		local pandemicThreshold = duration > 0 and expirationTime > 0 and baseduration > 0 and expiration <= baseduration * 0.3
		local removeGlow = true

	-- Pandemic and other Highlighting
	-- Note: ButtonGlowEnabled uses aura.type as key - we use SafeValue to get nil if secret
		local safeType = SafeValue(aura.type)
		local typeGlowEnabled = safeType and ButtonGlowEnabled[safeType]

		if (aura.effect == "HELPFUL" and typeGlowEnabled) or (PandemicEnabled and pandemicThreshold and ButtonGlowEnabled["Pandemic"]) then
			removeGlow = false
			frame.BorderHighlight:Hide()
			frame.Border:Hide()
			ButtonGlow.ShowOverlayGlow(frame)
			frame.__LBGoverlay:SetFrameLevel(frame:GetFrameLevel() or 65)
		elseif PandemicEnabled and pandemicThreshold then
			frame.BorderHighlight:SetVertexColor(PandemicColor.r,PandemicColor.g,PandemicColor.b,PandemicColor.a)
			frame.BorderHighlight:Show()
			frame.Border:Hide()
		elseif r then
			frame.BorderHighlight:SetVertexColor(r, g or 1, b or 1, a or 1)
			frame.BorderHighlight:Show()
			frame.Border:Hide()
		else
			frame.BorderHighlight:Hide()
			if not BlizzardStyleIcons then frame.Border:Show() end
		end

		-- Remove ButtonGlow if appropriate
		if frame.__LBGoverlay and removeGlow then ButtonGlow.HideOverlayGlow(frame) end

		if PandemicEnabled and not pandemicThreshold and duration > 0 and baseduration > 0 then
			local timeLeft = math.max(expiration - baseduration * 0.3, 0)
			if timeLeft > 0 then
				if frame.PandemicTimer then frame.PandemicTimer:Cancel() end
				frame.PandemicTimer = C_Timer.NewTimer(timeLeft, function() UpdateAuraHighlighting(frame, aura) end)
			end
		end
end

local function UpdateIcon(frame, aura)
	-- Early exit if no aura provided (used for cleanup of empty slots)
	if not aura then
		if frame then
			frame.auraInstanceID = nil
			frame.spellid = nil
			frame.unitid = nil
			if GameTooltip:IsOwned(frame) then
				GameTooltip:Hide()
			end
			frame:Hide()
		end
		return
	end

	-- Check for valid aura using auraInstanceID (always a readable integer, never secret)
	-- In 12.0.0+, aura.texture is a secret value that cannot be used in boolean checks,
	-- but it CAN be passed directly to SetTexture() which accepts secret values.
	-- We check auraInstanceID instead since it's always a plain integer.
	local hasValidAura = frame and (aura.auraInstanceID or aura.texture)

	if hasValidAura then
		-- Icon - SetTexture accepts secret values (SecretArguments = "AllowedWhenTainted")
		frame.Icon:SetTexture(aura.texture)

		-- Stacks - SetText accepts secret values at the engine level
		-- Use applicationsString (raw API value, possibly secret) for direct display
		-- The API returns "" for stacks < 2, so no numeric comparison needed
		if not HideAuraStacks and aura.applicationsString then
			frame.Stacks:SetText(aura.applicationsString)
		else
			frame.Stacks:SetText("")
		end

		-- Highlighting
		UpdateAuraHighlighting(frame, aura)

		-- Cooldown - Use duration object API if available (handles secrets properly)
		-- All paths use Blizzard's built-in CooldownFrame countdown numbers for timer display
		local useDurationObjectAPI = aura.durationObject and frame.Cooldown.SetCooldownFromDurationObject

		if useDurationObjectAPI then
			-- WoW 12.0.0+: Use the LuaDurationObject API
			-- Enable the built-in countdown numbers since we can't read the expiration time
			if not HideAuraDuration then
				frame.Cooldown:SetHideCountdownNumbers(false)
				frame.Cooldown.noCooldownCount = false  -- Allow OmniCC if user has it
			else
				frame.Cooldown:SetHideCountdownNumbers(true)
				frame.Cooldown.noCooldownCount = true
			end
			frame.Cooldown:SetCooldownFromDurationObject(aura.durationObject, true)
			frame.Cooldown:SetDrawSwipe(not HideCooldownSpiral)
			frame.Cooldown:SetDrawEdge(not HideCooldownSpiral)
		elseif aura.duration and aura.duration > 0 and aura.expiration and aura.expiration > 0 then
			-- Legacy path for pre-12.0.0 or when duration values are available
			-- Use built-in countdown numbers (same as durationObject path)
			if not HideAuraDuration then
				frame.Cooldown:SetHideCountdownNumbers(false)
				frame.Cooldown.noCooldownCount = false
			else
				frame.Cooldown:SetHideCountdownNumbers(true)
				frame.Cooldown.noCooldownCount = true
			end
			if frame.Cooldown.SetUseAuraDisplayTime then
				frame.Cooldown:SetUseAuraDisplayTime(true)
			end
			frame.Cooldown:SetCooldown(aura.expiration - aura.duration, aura.duration)
			frame.Cooldown:SetDrawSwipe(not HideCooldownSpiral)
			frame.Cooldown:SetDrawEdge(not HideCooldownSpiral)
		else
			-- No duration info - just show static icon (no cooldown spiral or timer)
			frame.Cooldown:SetHideCountdownNumbers(true)
			frame.Cooldown:SetCooldown(0, 0)
		end

		-- Store data for tooltip
		frame.auraInstanceID = aura.auraInstanceID
		frame.spellid = aura.spellid or aura.safeSpellId
		frame.unitid = aura.unit

		frame:Show()

		-- Aura visibility is driven by UNIT_AURA events; no polling needed
	elseif frame then
		-- Clear tooltip data and dismiss tooltip if hovering
		frame.auraInstanceID = nil
		frame.spellid = nil
		frame.unitid = nil
		if GameTooltip:IsOwned(frame) then
			GameTooltip:Hide()
		end
		frame:Hide()
	end
end


--local function AuraSortFunction(a,b)
--	return a.priority < b.priority
--end


local function UpdateIconGrid(frame, unitid)
		if not unitid then return end

		local unitReaction
		if UnitIsFriend("player", unitid) then unitReaction = AURA_TARGET_FRIENDLY
		else unitReaction = AURA_TARGET_HOSTILE end

		local AuraIconFrames = frame.AuraIconFrames
		local storedAuras = {}
		local storedAuraCount = 0
		local emphasizedAuras = {}

		AuraCache[unitid] = {} -- Clear cache for unit

		-- Debug: Log which unit we're processing
		DebugAura("UpdateIconGrid for: " .. unitid .. " - " .. (unitReaction == AURA_TARGET_FRIENDLY and "FRIENDLY" or "HOSTILE"))

		-- 12.0.0+: Use GetUnitAuras with INCLUDE_NAME_PLATE_ONLY filter for reliable aura data
		-- Aura data fields may be secret values - use helper APIs and UnitIsUnit for comparisons
		if _GetUnitAurasForNameplate then
			local allAuras = _GetUnitAurasForNameplate(unitid)
			DebugAura("Total auras returned by API: " .. #allAuras)

			local auraIndex = 0
			for _, auraData in ipairs(allAuras) do
				auraIndex = auraIndex + 1
				local aura = {}
				local auraInstanceID = auraData.auraInstanceID

				-- Map aura data to NeatPlates format
				-- These fields may be secret values but can be passed directly to display APIs
				aura.name = auraData.name
				aura.texture = auraData.icon
				aura.type = auraData.dispelName
				aura.effect = auraData.isHarmful and "HARMFUL" or "HELPFUL"
				aura.reaction = unitReaction
				aura.caster = auraData.sourceUnit
				aura.unit = unitid
				aura.auraInstanceID = auraInstanceID

				-- Wrap the rest of aura processing in pcall to catch any errors
				local processSuccess, processErr = pcall(function()
					-- Use helper APIs that return usable values even with secrets
					-- These bypass the secret value restrictions
					if HAS_STACK_DISPLAY_API then
						-- GetAuraApplicationDisplayCount returns a pre-formatted string (may be secret in 12.0.0+)
						-- Store raw value for direct SetText use (SetText accepts secret values)
						aura.applicationsString = C_UnitAuras.GetAuraApplicationDisplayCount(unitid, auraInstanceID, 2, 1000)
						local stackStr = SafeValue(aura.applicationsString)  -- Returns nil if secret
						aura.stacks = (stackStr and stackStr ~= "") and tonumber(stackStr) or 1
					else
						aura.stacks = SafeValue(auraData.applications) or 1
					end

					if HAS_DURATION_OBJECT_API then
						-- GetAuraDuration returns a LuaDurationObject that can be used with cooldowns
						aura.durationObject = C_UnitAuras.GetAuraDuration(unitid, auraInstanceID)
						-- For backward compatibility, try to get numeric values safely
						aura.duration = SafeValue(auraData.duration) or 0
						aura.expiration = SafeValue(auraData.expirationTime) or 0
					else
						aura.duration = SafeValue(auraData.duration) or 0
						aura.expiration = SafeValue(auraData.expirationTime) or 0
					end

					-- Use safe spellId for table keys (nil if secret)
					local safeSpellId = SafeValue(auraData.spellId)
					aura.spellid = auraData.spellId  -- Keep original for display
					aura.safeSpellId = safeSpellId   -- Use this for table operations

					-- Pandemic Base duration - use IsCasterPlayer which handles secret sourceUnit
					-- Pass isFromPlayerOrPlayerPet flag as preferred source (doesn't require UnitIsUnit)
					local casterIsPlayer = IsCasterPlayer(auraData.sourceUnit, auraData.isFromPlayerOrPlayerPet)
					aura.isFromPlayer = casterIsPlayer  -- Cache this for later use

					if HAS_BASE_DURATION_API and casterIsPlayer and safeSpellId then
						-- GetAuraBaseDuration returns the base duration for pandemic calculations
						local baseDur = C_UnitAuras.GetAuraBaseDuration(unitid, auraInstanceID)
						if baseDur then
							AuraBaseDuration[safeSpellId] = baseDur
						elseif aura.duration > 0 then
							if not AuraBaseDuration[safeSpellId] or AuraBaseDuration[safeSpellId] > aura.duration then
								AuraBaseDuration[safeSpellId] = aura.duration
							end
						end
					elseif safeSpellId and casterIsPlayer and aura.duration > 0 then
						if not AuraBaseDuration[safeSpellId] or AuraBaseDuration[safeSpellId] > aura.duration then
							AuraBaseDuration[safeSpellId] = aura.duration
						end
					end
					aura.baseduration = (safeSpellId and AuraBaseDuration[safeSpellId]) or aura.duration

					-- Process aura through filter
					-- In 12.0.0+, process all auras that were returned (Platynator approach)
					-- The auraInstanceID is always valid if the aura exists
					local filterSuccess, show, priority, r, g, b, a = pcall(AuraFilterFunction, aura)
					if not filterSuccess then
						show = nil
					end

					local emphSuccess, emphasized, ePriority = pcall(EmphasizedAuraFilterFunction, aura)
					if not emphSuccess then
						emphasized = nil
					end

					show = show or emphasized

					-- Cache aura by name and spellid (only if we have safe values)
					local safeName = SafeValue(auraData.name)
					if safeName then
						local existing = AuraCache[unitid][safeName]
						local existingCasterNotPlayer = not existing or not existing.isFromPlayer
						if existingCasterNotPlayer then
							AuraCache[unitid][safeName] = aura
							if safeSpellId then
								AuraCache[unitid][tostring(safeSpellId)] = aura
							end
						end
					end

					-- Store Order/Priority
					if show then
						aura.priority = priority or 10
						aura.r, aura.g, aura.b, aura.a = r, g, b, a
						storedAuraCount = storedAuraCount + 1
						storedAuras[storedAuraCount] = aura
					end

					-- Add to Emphasized list
					if emphasized then
						aura.priority = ePriority or 10
						emphasizedAuras[#emphasizedAuras+1] = aura
					end
				end)
			end
			DebugAura("  Total: " .. storedAuraCount .. " auras passed filter, " .. #emphasizedAuras .. " emphasized")
		else
			-- Legacy path for pre-12.0.0 and Classic: iterate by index
			local auraIndex = 0
			local searchedDebuffs, searchedBuffs = false, false
			local auraFilter = "HARMFUL"

			repeat
				auraIndex = auraIndex + 1

				local aura = {}

				do
					local name, icon, stacks, auraType, duration, expiration, caster, canStealOrPurge, nameplateShowPersonal, spellid, canApplyAura, isBossAura, isFromPlayerOrPlayerPet = _UnitAura(unitid, auraIndex, auraFilter)

					aura.name = name
					aura.texture = icon
					aura.stacks = stacks or 1
					aura.type = auraType
					aura.effect = auraFilter
					aura.duration = SafeValue(duration) or 0
					aura.reaction = unitReaction
					aura.expiration = SafeValue(expiration) or 0
					aura.caster = caster
					aura.spellid = spellid
					aura.unit = unitid

					-- Get safe values for table key operations
					local safeSpellId = SafeValue(spellid)
					aura.safeSpellId = safeSpellId

					-- Pandemic Base duration
					-- Use IsCasterPlayer which handles secret sourceUnit values
					-- Pass isFromPlayerOrPlayerPet flag as preferred source (doesn't require UnitIsUnit)
					local casterIsPlayer = IsCasterPlayer(caster, isFromPlayerOrPlayerPet)
					aura.isFromPlayer = casterIsPlayer

					if safeSpellId and casterIsPlayer and aura.duration > 0 then
						if not AuraBaseDuration[safeSpellId] or AuraBaseDuration[safeSpellId] > aura.duration then
							AuraBaseDuration[safeSpellId] = aura.duration
						end
					end
					aura.baseduration = (safeSpellId and AuraBaseDuration[safeSpellId]) or aura.duration
				end

				-- Auras are evaluated by an external function
				-- Pre-filtering before the icon grid is populated
				-- Note: In legacy path, texture is always readable; in 12.0.0+ path we use auraInstanceID
				local safeName = SafeValue(aura.name)
				if safeName or aura.auraInstanceID or aura.texture then  -- Show if we have valid identifier
					local show, priority, r, g, b, a = AuraFilterFunction(aura)
					local emphasized, ePriority = EmphasizedAuraFilterFunction(aura)
					show = show or emphasized

					-- Cache aura by name and spellid (only if we have safe values)
					if safeName then
						local existing = AuraCache[unitid][safeName]
						-- Use isFromPlayer flag instead of comparing caster directly
						local existingCasterNotPlayer = not existing or not existing.isFromPlayer
						if existingCasterNotPlayer then
							AuraCache[unitid][safeName] = aura
							if aura.safeSpellId then
								AuraCache[unitid][tostring(aura.safeSpellId)] = aura
							end
						end
					end

					-- Store Order/Priority
					if show then
						aura.priority = priority or 10
						aura.r, aura.g, aura.b, aura.a = r, g, b, a
						storedAuraCount = storedAuraCount + 1
						storedAuras[storedAuraCount] = aura
					end

					-- Add to Emphasized list
					if emphasized then
						aura.priority = ePriority or 10
						emphasizedAuras[#emphasizedAuras+1] = aura
					end
				else
					if auraFilter == "HARMFUL" then
						searchedDebuffs = true
						auraFilter = "HELPFUL"
						auraIndex = 0
					else
						searchedBuffs = true
					end
				end
			until (searchedDebuffs and searchedBuffs)
		end

		NeatPlatesWidgets.AuraCache = AuraCache

		--[[ Debug, add custom Buff
		while storedAuraCount < AuraLimit do
			storedAuraCount = storedAuraCount+1
			storedAuras[storedAuraCount] = {
				["type"] = "Magic",
				["effect"] = "HELPFUL",
				["duration"] = 12,
				["stacks"] = 0,
				["reaction"] = 1,
				["name"] = "Debug",
				["expiration"] = 0,
				["priority"] = 20,
				["spellid"] = 234153,
				["texture"] = 136069,
				["r"] = 0.2,
				["g"] = 0,
				["b"] = 1,
			}
		end
		--]]


		-- Display Auras
		------------------------------------------------------------------------------------------------------
		local DebuffSlotCount = 0
		local BuffSlotCount = 0
		local AuraSlots = {}
		local BuffAuras = {}
		local DebuffAuras = {}
		local DebuffCount = 0
		local DisplayedRows = 0
		local EmphasizedAura
		local EmphasizedAuraCount = 0


		EmphasizedAura, EmphasizedAuraCount = frame.emphasized:SetAura(emphasizedAuras)	-- Display Emphasized Aura, returns displayed aura

		if not (HideInHeadlineMode and frame.style == "NameOnly") and (storedAuraCount > 0 or next(EmphasizedAura)) then
			frame:Show()
		end
		if storedAuraCount > 0 then
			sort(storedAuras, AuraSortFunction)

			for index = 1, storedAuraCount do
				if (DebuffSlotCount+BuffSlotCount) > AuraLimit then break end
				local aura = storedAuras[index]

				-- Use safeSpellId for table key operations (nil if secret)
				-- aura.safeSpellId is set during processing, fall back to checking issecretvalue
				local safeSpellId = aura.safeSpellId
				if safeSpellId == nil and aura.spellid then
					-- Fallback for legacy path
					local spellIdIsSecret = HAS_SECRET_VALUE_SUPPORT and issecretvalue(aura.spellid)
					safeSpellId = not spellIdIsSecret and aura.spellid or nil
				end

				local isEmphasizedUnique = EmphasizedUnique and safeSpellId and EmphasizedAura[tostring(safeSpellId)]

				-- Check for valid aura using auraInstanceID (always readable, never secret)
				-- In 12.0.0+, aura.texture is a secret value that cannot be used in boolean checks,
				-- but SetTexture() accepts secret values directly for display.
				local hasValidIdentifier = aura.auraInstanceID or aura.texture

				if hasValidIdentifier and not isEmphasizedUnique then
					-- Sort buffs and debuffs
					if aura.effect == "HELPFUL" then
						table.insert(BuffAuras, aura)
						BuffSlotCount = BuffSlotCount + 1
					elseif DebuffSlotCount < DebuffLimit then
						table.insert(DebuffAuras, aura)
						DebuffSlotCount = DebuffSlotCount + 1
					end

					frame.currentAuraCount = index
				end
			end

			-- Loop through debuffs and call function to display them
			for k, aura in ipairs(DebuffAuras) do
				UpdateIcon(AuraIconFrames[k], aura)
				AuraSlots[k] = true
			end

			-- Calculate Buff Offset
			local rowOffset = DebuffSlotCount+1	-- Offset as a debuff would be
			DisplayedRows = (math.floor((DebuffSlotCount + BuffSlotCount - 1)/DebuffColumns) + math.min(DebuffSlotCount, 1))

			if BuffSeparationMode < 3 then
				if BuffSeparationMode == 2 and DebuffColumns * DisplayedRows - (DebuffSlotCount + BuffSlotCount) >= SpacerSlots then
					rowOffset = math.max(DebuffColumns * DisplayedRows, DebuffColumns) -- Same Row with space between
				elseif BuffSlotCount > 0 then
					rowOffset = DebuffColumns * (DisplayedRows + 1)	-- Seperate Row
					DisplayedRows = DisplayedRows+1
				end
			end

			-- Loop through buffs and call function to display them
			for k, aura in ipairs(BuffAuras) do
				local index = rowOffset+1-k
				-- Make sure we aren't overwriting any debuffs and that we're not trying to apply buffs to slots that don't exist
				if index > DebuffCount and index > 0 then
						UpdateIcon(AuraIconFrames[index], aura)
						AuraSlots[index] = true
				end
			end

		end

		-- Clear Extra Slots
		for AuraSlotEmpty = 1, AuraLimit do
			if AuraSlots[AuraSlotEmpty] ~= true then UpdateIcon(AuraIconFrames[AuraSlotEmpty]) end
		end

		if AuraAlignment == "BOTTOM" then
			local offsetX = -(AuraWidth+5)*(math.min(storedAuraCount, DebuffColumns)-1)/2
			AuraIconFrames[1]:SetPoint(AuraAlignment, offsetX, 0)
		end

		DisplayedRows = math.max(0, DisplayedRows)
		EmphasizedAuraCount = math.max(1, EmphasizedAuraCount) -- Make sure we aren't setting 0 as this can detach the frame...

		-- Set Height/Width of Aura Frames
		if DisplayedRows > 0 then frame:SetHeight(DisplayedRows*16 + (DisplayedRows-1)*8) else frame:SetHeight(2) end -- Set Height of the parent for easier alignment of the Emphasized aura.
		frame.emphasized:SetWidth(EmphasizedAuraCount * AuraWidth)
end

function UpdateWidget(frame)
		local unitid = frame.unitid

		if(HideInHeadlineMode and frame.style == "NameOnly") then
			frame:Hide()
		else
			frame:Show()
		end
		UpdateIconGrid(frame, unitid)
end

-- Context Update (mouseover, target change)
local function UpdateWidgetContext(frame, unit)
	local unitid = unit.unitid
	frame.unitid = unitid
	frame.style = unit.style

	-- Removed verbose context debug spam

	WidgetList[unitid] = frame

	UpdateWidget(frame)
end

local function ClearWidgetContext(frame)
	for unitid, widget in pairs(WidgetList) do
		if frame == widget then WidgetList[unitid] = nil end
	end
end

local function ExpireFunction(icon)
	-- UpdateWidget(icon.Parent)
	UpdateIcon(icon) -- Won't re-arrange auras to fill empty slots, but at least it won't show and hopefully will prevent script timeouts from the expire function (This function is really just a backup that rarely gets run anyways)
end

-------------------------------------------------------------
-- Widget Frames
-------------------------------------------------------------
local WideArt = "Interface\\Addons\\NeatPlatesWidgets\\Aura\\AuraFrameWide"
local SquareArt = "Interface\\Addons\\NeatPlatesWidgets\\Aura\\AuraFrameSquare"
local BlizzardArt = "Interface\\Common\\WhiteIconFrame"
local WideHighlightArt = "Interface\\Addons\\NeatPlatesWidgets\\Aura\\AuraFrameHighlightWide"
local SquareHighlightArt = "Interface\\Addons\\NeatPlatesWidgets\\Aura\\AuraFrameHighlightSquare"
local AuraFont = "FONTS\\ARIALN.TTF"

local function Enable()
	AuraMonitor:SetScript("OnEvent", AuraEventHandler)

	for event in pairs(AuraEvents) do AuraMonitor:RegisterEvent(event) end

	--NeatPlatesUtility:EnableGroupWatcher()
	WatcherIsEnabled = true

end

local function Disable()
	AuraMonitor:SetScript("OnEvent", nil)
	AuraMonitor:UnregisterAllEvents()
	WatcherIsEnabled = false

	for unitid, widget in pairs(WidgetList) do
		if frame == widget then WidgetList[unitid] = nil end
	end

end


local function TransformWideAura(frame)
	frame.Parent:SetWidth(DebuffColumns*(26 + 5)*AuraScale)

	frame:SetWidth(26.5)
	frame:SetHeight(14.5)
	-- Icon
	frame.Icon:SetAllPoints(frame)
	frame.Border:ClearAllPoints()
	frame.BorderHighlight:ClearAllPoints()
	if BlizzardStyleIcons then
		frame.Icon:SetTexCoord(0, 1, 0, 1)  -- obj:SetTexCoord(left,right,top,bottom)
		-- Border
		frame.Border:SetAllPoints(frame.Icon)
		frame.Border:SetTexture(BlizzardArt)
		frame.Border:Hide()
		-- Highlight
		frame.BorderHighlight:SetAllPoints(frame.Border)
		frame.BorderHighlight:SetTexture(BlizzardArt)
	else
		frame.Icon:SetTexCoord(.07, 1-.07, .23, 1-.23)  -- obj:SetTexCoord(left,right,top,bottom)
		-- Border
		frame.Border:SetWidth(32); frame.Border:SetHeight(32)
		frame.Border:SetPoint("CENTER", 1, -2)
		frame.Border:SetTexture(WideArt)
		-- Highlight
		frame.BorderHighlight:SetAllPoints(frame.Border)
		frame.BorderHighlight:SetTexture(WideHighlightArt)
	end

	--  Stacks
	frame.Stacks:SetFont(AuraFont,10, "OUTLINE")
	frame.Stacks:SetShadowOffset(1, -1)
	frame.Stacks:SetShadowColor(0,0,0,1)
	frame.Stacks:SetPoint("RIGHT", 0, -6)
	frame.Stacks:SetWidth(26)
	frame.Stacks:SetHeight(16)
	frame.Stacks:SetJustifyH("RIGHT")

	AuraWidth = frame:GetWidth()
end

local function TransformSquareAura(frame)
	frame.Parent:SetWidth(DebuffColumns*(16 + 5))

	frame:SetWidth(16.5)
	frame:SetHeight(14.5)
	-- Icon
	frame.Icon:SetAllPoints(frame)
	frame.Border:ClearAllPoints()
	frame.BorderHighlight:ClearAllPoints()
	if BlizzardStyleIcons then
		frame.Icon:SetTexCoord(0, 1, 0, 1)  -- obj:SetTexCoord(left,right,top,bottom)
		-- Border
		frame.Border:SetAllPoints(frame.Icon)
		frame.Border:SetTexture(BlizzardArt)
		frame.Border:Hide()
		-- Highlight
		frame.BorderHighlight:SetAllPoints(frame.Border)
		frame.BorderHighlight:SetTexture(BlizzardArt)
	else
		frame.Icon:SetTexCoord(.10, 1-.07, .12, 1-.12)  -- obj:SetTexCoord(left,right,top,bottom)
		-- Border
		frame.Border:SetWidth(32); frame.Border:SetHeight(32)
		frame.Border:SetPoint("CENTER", 0, -2)
		frame.Border:SetTexture(SquareArt)
		-- Highlight
		frame.BorderHighlight:SetAllPoints(frame.Border)
		frame.BorderHighlight:SetTexture(SquareHighlightArt)
	end
	--  Stacks
	frame.Stacks:SetFont(AuraFont,10, "OUTLINE")
	frame.Stacks:SetShadowOffset(1, -1)
	frame.Stacks:SetShadowColor(0,0,0,1)
	frame.Stacks:SetPoint("RIGHT", 0, -6)
	frame.Stacks:SetWidth(26)
	frame.Stacks:SetHeight(16)
	frame.Stacks:SetJustifyH("RIGHT")

	AuraWidth = frame:GetWidth()
end

-- Create a Wide Aura Icon
local function CreateAuraIcon(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame.unit = nil
	frame.Parent = parent

	frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
	frame.Border = frame:CreateTexture(nil, "ARTWORK")
	frame.BorderHighlight = frame:CreateTexture(nil, "ARTWORK")
	frame.Cooldown = CreateFrame("Cooldown", nil, frame, "NeatPlatesAuraWidgetCooldown")
	frame.Info = CreateFrame("Frame", nil, frame)

	frame.Cooldown:SetAllPoints(frame)
	frame.Cooldown:SetReverse(true)
	frame.Cooldown:SetHideCountdownNumbers(true)  -- Will be overridden per-aura in UpdateIcon
	frame.Cooldown:SetDrawEdge(true)
	-- Set a smaller font for countdown numbers to fit small aura icons (16-26 pixels)
	-- The default countdown font is designed for larger frames like action buttons (~36-45px)
	if frame.Cooldown.SetCountdownFont then
		frame.Cooldown:SetCountdownFont("GameFontHighlightSmallOutline")
	end

	frame.Info:SetAllPoints(frame)

	-- Text (TimeLeft kept as hidden stub to prevent nil reference errors in custom themes)
	frame.TimeLeft = frame.Info:CreateFontString(nil, "OVERLAY")
	frame.TimeLeft:Hide()
	frame.Stacks = frame.Info:CreateFontString(nil, "OVERLAY")

	-- Information about the currently displayed aura
	frame.AuraInfo = {
		Name = "",
		Icon = "",
		Stacks = 0,
		Expiration = 0,
		Type = "",
	}

	frame.Expire = ExpireFunction

	-- Tooltip support
	frame:EnableMouse(true)
	frame:SetMouseClickEnabled(false)  -- Clicks pass through to nameplate

	frame:SetScript("OnEnter", function(self)
		if not ShowAuraTooltip then return end
		if self.auraInstanceID and self.unitid then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			if GameTooltip.SetUnitAuraByAuraInstanceID then
				GameTooltip:SetUnitAuraByAuraInstanceID(self.unitid, self.auraInstanceID)
			elseif self.spellid then
				GameTooltip:SetSpellByID(self.spellid)
			end
			GameTooltip:Show()
		elseif self.spellid then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetSpellByID(self.spellid)
			GameTooltip:Show()
		end
	end)

	frame:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	frame:Hide()

	return frame
end

local function UpdateIconConfig(frame)
	local iconTable = frame.AuraIconFrames

	if iconTable then
		-- Create Icons
		for index = 1, AuraLimit do
			--if not iconTable[index] then print("Creating aura icon"); auraIconsCreated = (auraIconsCreated or 0) + 1; print(auraIconsCreated);end
			local icon = iconTable[index] or CreateAuraIcon(frame)
			iconTable[index] = icon
			icon:SetScale(AuraScale)
			-- Apply Style
			if useWideIcons then TransformWideAura(icon) else TransformSquareAura(icon) end
		end

		-- Set Anchors
		local anchorIndex = 1
		for row = 1, AuraLimit/DebuffColumns do
			iconTable[anchorIndex]:ClearAllPoints()
			if row == 1 then
				iconTable[anchorIndex]:SetPoint(AuraAlignment or "BOTTOMLEFT", frame)
			else
				iconTable[anchorIndex]:SetPoint("BOTTOMLEFT", iconTable[anchorIndex-DebuffColumns], "TOPLEFT", 0, 8)
			end
			for index = anchorIndex + 1, DebuffColumns * row do
			  iconTable[index]:ClearAllPoints()
			  if AuraAlignment == "BOTTOMRIGHT" then
			  	iconTable[index]:SetPoint("RIGHT", iconTable[index-1], "LEFT", -5, 0)
			  else
			  	iconTable[index]:SetPoint("LEFT", iconTable[index-1], "RIGHT", 5, 0)
			  end
			end
			anchorIndex = anchorIndex + DebuffColumns -- Set next anchor index
		end
	end
end

local function UpdateEmphasizedIconConfig(frame)
	local iconTable = frame.AuraIconFrames

	--local columns = 1
	local auraLimit = MaxEmphasizedAuras
	frame:SetScale(EmphasizedAuraScale)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOM", frame:GetParent(), EmphasizedScaleOptions.anchor or "TOP", EmphasizedScaleOptions.offset.x, 2 + EmphasizedScaleOptions.offset.y)

	if iconTable then
		-- Create Icons
		for index = 1, auraLimit do
			local icon = iconTable[index] or CreateAuraIcon(frame)
			iconTable[index] = icon
			-- Apply Style
			if useWideIcons then TransformWideAura(icon) else TransformSquareAura(icon) end
		end

		-- Set Anchors
		iconTable[1]:ClearAllPoints()
		iconTable[1]:SetPoint("BOTTOMLEFT", frame)
		for index = 2, auraLimit do
		  iconTable[index]:ClearAllPoints()
		  iconTable[index]:SetPoint("LEFT", iconTable[index-1], "RIGHT", 5, 0)
		end
	end
end

local function UpdateWidgetConfig(frame)
	UpdateIconConfig(frame)
	UpdateEmphasizedIconConfig(frame.emphasized)
end

local function UpdateWidgetOffset(frame, x, y)
	x = x or frame.lastOffset.x
	y = y or frame.lastOffset.y
	frame.lastOffset = {
		x = x,
		y = y
	}
	local config = frame.lastConfig
	frame:ClearAllPoints()
	frame:SetPoint(config.anchor or "TOP", config.relFrame, config.anchorRel or config.anchor or "TOP", config.x or 0, (config.y or 0) + (y or 0))
end

local function SetCustomPoint(frame, anchor, relFrame, anchorRel, x, y)
	frame.lastConfig = {
		anchor = anchor,
		relFrame = relFrame,
		anchorRel = anchorRel,
		x = x,
		y = y
	}

	UpdateWidgetOffset(frame)
end

-- Create the Main Widget Body and Icon Array
local function CreateAuraWidget(parent, style)
	-- Create Base frame
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(128); frame:SetHeight(32); frame:Show()
	--frame.PollFunction = UpdateWidgetTime

	-- Create Emphasized Frame
	frame.emphasized = CreateFrame("Frame", nil, frame)
	frame.emphasized:SetWidth(32)
	frame.emphasized:SetHeight(32)
	frame.emphasized:SetPoint("BOTTOM", frame, "TOP", 0, 2)
	frame.emphasized:SetScale(EmphasizedAuraScale)
	frame.emphasized:Show()

	-- Create Icon Grid
	frame.AuraIconFrames = {}
	frame.emphasized.AuraIconFrames = {}
	UpdateIconConfig(frame)
	UpdateEmphasizedIconConfig(frame.emphasized)

	-- Functions
	frame._Hide = frame.Hide
	frame.Hide = function() ClearWidgetContext(frame); frame:_Hide() end

	frame.Filter = nil
	frame.UpdateContext = UpdateWidgetContext
	frame.Update = UpdateWidgetContext
	frame.UpdateConfig = UpdateWidgetConfig
	frame.UpdateTarget = UpdateWidgetTarget
	frame.SetCustomPoint = SetCustomPoint
	frame.UpdateOffset = UpdateWidgetOffset

	-- Various stored data
	frame.lastConfig = {}
	frame.lastOffset = {}

	-- Emphasized Functions
	frame.emphasized.SetAura = function(frame, auras)
		local shown = 0
		local ids = {}
		local auraLimit = MaxEmphasizedAuras
		sort(auras, AuraSortFunction)

		for index = 1, #auras do
			if index > auraLimit then break end
			shown = shown + 1

			-- Use safeSpellId for table key (already calculated during processing)
			-- Fall back to checking if spellid is secret
			local aura = auras[index]
			local safeSpellId = aura.safeSpellId
			if safeSpellId == nil and aura.spellid then
				local isSecret = HAS_SECRET_VALUE_SUPPORT and issecretvalue(aura.spellid)
				safeSpellId = not isSecret and aura.spellid or nil
			end

			if safeSpellId then
				ids[tostring(safeSpellId)] = true
			end

			UpdateIcon(frame.AuraIconFrames[index], aura)
		end

		-- Cleanup empty aura slots
		for i = shown + 1, #frame.AuraIconFrames do
			UpdateIcon(frame.AuraIconFrames[i])
		end

		return ids, shown
	end

	return frame
end

local function SetAuraIconStyle(style, scale)
	AuraScale = scale
	BlizzardStyleIcons = style == 3
	useWideIcons = style == 1

	if style >= 2 and style <= 3 then
		DebuffColumns = math.max(math.ceil(5/AuraScale), 5) -- Compact
	else
		DebuffColumns = math.max(math.ceil(3/AuraScale), 3) -- Wide
	end

	DebuffLimit = DebuffColumns * 2
	AuraLimit = DebuffColumns * 3	-- Extra row for buffs

	NeatPlates:ForceUpdate()
end

local function SetAuraSortMode(func)
	if func and type(func) == 'function' then
		AuraSortFunction = func
	end
end

local function SetAuraFilter(func)
	if func and type(func) == 'function' then
		AuraFilterFunction = func
	end
end

local function SetEmphasizedAuraFilter(func, unique)
	if func and type(func) == 'function' then
		EmphasizedAuraFilterFunction = func
	end
	EmphasizedUnique = unique
end

local function SetAuraOptions(LocalVars)
	local Alignments ={
		"BOTTOMLEFT",
		"BOTTOM",
		"BOTTOMRIGHT",
	}

	HideCooldownSpiral = LocalVars.HideCooldownSpiral
	HideAuraDuration = LocalVars.HideAuraDuration
	HideAuraStacks = LocalVars.HideAuraStacks
	ShowAuraTooltip = LocalVars.ShowAuraTooltip
	ShowImportantAurasOnly = LocalVars.ShowImportantAurasOnly
	AuraScale = LocalVars.AuraScale
	EmphasizedAuraScale = LocalVars.EmphasizedAuraScale
	AuraAlignment = Alignments[LocalVars.WidgetAuraAlignment]
	-- ScaleOptions = LocalVars.WidgetAuraScaleOptions
	EmphasizedScaleOptions = LocalVars.WidgetEmphasizedAuraScaleOptions
	HideInHeadlineMode = LocalVars.HideAuraInHeadline
	PreciseAuraThreshold = LocalVars.PreciseAuraThreshold
	BuffSeparationMode = LocalVars.BuffSeparationMode
end

local function SetPandemic(enabled, color)
	PandemicEnabled = enabled
	PandemicColor = color
end

local function SetBorderTypes(pandemic, magic, enrage)
	if pandemic == 2 then pandemic = true else pandemic = false end
	if magic == 2 then magic = true else magic = false end
	if enrage == 2 then enrage = true else enrage = false end
	ButtonGlowEnabled = {
		["Pandemic"] = pandemic,
		["Magic"] = magic,
		[""] = enrage,
	}
end

local function SetSpacerSlots(amount)
	SpacerSlots = math.min(amount, DebuffColumns-1)
end

local function SetEmphasizedSlots(amount)
	MaxEmphasizedAuras = amount
end

-- Set the filter modes for "Show Mine" vs "Show All" aura filtering
-- This controls whether |PLAYER is appended to the API filter strings
-- debuffMode/buffMode: 1 = Show None, 2 = Show Mine, 3 = Show All
local function SetAuraFilterModes(debuffMode, buffMode)
	WidgetDebuffFilterMode = debuffMode or 3
	WidgetBuffFilterMode = buffMode or 1

	if NEATPLATES_DEBUG_AURAS and NeatPlatesUtility and NeatPlatesUtility.Debug then
		NeatPlatesUtility.Debug.Log("Aura", "SetAuraFilterModes: debuff=" .. tostring(WidgetDebuffFilterMode) .. ", buff=" .. tostring(WidgetBuffFilterMode))
	end
end

-----------------------------------------------------
-- External
-----------------------------------------------------
-- NeatPlatesWidgets.GetAuraWidgetByGUID = GetAuraWidgetByGUID
NeatPlatesWidgets.IsAuraShown = IsAuraShown

NeatPlatesWidgets.SetAuraIconStyle = SetAuraIconStyle

NeatPlatesWidgets.SetAuraSortMode = SetAuraSortMode
NeatPlatesWidgets.SetAuraFilter = SetAuraFilter
NeatPlatesWidgets.SetEmphasizedAuraFilter = SetEmphasizedAuraFilter
NeatPlatesWidgets.SetAuraOptions = SetAuraOptions

NeatPlatesWidgets.SetPandemic = SetPandemic
NeatPlatesWidgets.SetBorderTypes = SetBorderTypes
NeatPlatesWidgets.SetSpacerSlots = SetSpacerSlots
NeatPlatesWidgets.SetEmphasizedSlots = SetEmphasizedSlots
NeatPlatesWidgets.SetAuraFilterModes = SetAuraFilterModes

NeatPlatesWidgets.CreateAuraWidget = CreateAuraWidget

NeatPlatesWidgets.EnableAuraWatcher = Enable
NeatPlatesWidgets.DisableAuraWatcher = Disable

-----------------------------------------------------
-- Soon to be deprecated
-----------------------------------------------------

local PlayerDispelCapabilities = {
	["Curse"] = false,
	["Disease"] = false,
	["Magic"] = false,
	["Poison"] = false,
}

local function UpdatePlayerDispelTypes()
	PlayerDispelCapabilities["Curse"] = IsSpellKnown(51886) or IsSpellKnown(475) or IsSpellKnown(2782)
	PlayerDispelCapabilities["Poison"] = IsSpellKnown(2782) or IsSpellKnown(32375) or IsSpellKnown(4987) or (IsSpellKnown(527) and IsSpellKnown(33167))
	PlayerDispelCapabilities["Magic"] = (IsSpellKnown(4987) and IsSpellKnown(53551)) or (IsSpellKnown(2782) and IsSpellKnown(88423)) or (IsSpellKnown(527) and IsSpellKnown(33167)) or (IsSpellKnown(51886) and IsSpellKnown(77130)) or IsSpellKnown(32375)
	PlayerDispelCapabilities["Disease"] = IsSpellKnown(4987) or IsSpellKnown(528)
end

local function CanPlayerDispel(debuffType)
	return PlayerDispelCapabilities[debuffType or ""]
end

NeatPlatesWidgets.CanPlayerDispel = CanPlayerDispel


