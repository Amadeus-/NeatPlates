
local AddonName, HubData = ...;
local LocalVars = NeatPlatesHubDefaults
local L = LibStub("AceLocale-3.0"):GetLocale("NeatPlates")

------------------------------------------------------------------
-- References
------------------------------------------------------------------
local GetFriendlyThreat = NeatPlatesUtility.GetFriendlyThreat

local IsFriend = NeatPlatesUtility.IsFriend
local IsGuildmate = NeatPlatesUtility.IsGuildmate

local IsOffTanked = NeatPlatesHubFunctions.IsOffTanked
local IsTankingAuraActive = NeatPlatesWidgets.IsPlayerTank
local InCombatLockdown = InCombatLockdown
local GetFriendlyClass = HubData.Functions.GetFriendlyClass
local GetEnemyClass = HubData.Functions.GetEnemyClass
local StyleDelegate = NeatPlatesHubFunctions.SetStyleNamed
local ColorFunctionByHealth = HubData.Functions.ColorFunctionByHealth
local CachedUnitDescription = NeatPlatesUtility.CachedUnitDescription

local GetUnitSubtitle = NeatPlatesUtility.GetUnitSubtitle
local GetUnitQuestInfo = NeatPlatesUtility.GetUnitQuestInfo
local GetArenaIndex = NeatPlatesUtility.GetArenaIndex
local round = NeatPlatesUtility.round


local AddHubFunction = NeatPlatesHubHelpers.AddHubFunction
-- 12.0.0+ Secret value helpers
local SafeHealthPercent = NeatPlatesHubHelpers.SafeHealthPercent
local SafeIsDamaged = NeatPlatesHubHelpers.SafeIsDamaged
local SafeNumber = NeatPlatesHubHelpers.SafeNumber

-- 12.0.0+ API availability check
local UnitHealthPercentAPI = UnitHealthPercent
local CurveConstantsRef = CurveConstants

local function DummyFunction() end

-- Helper to set format data on unit for secret value display via SetFormattedText
-- Returns true if format data was set (caller should return nil for text)
local function SetHealthPercentFormat(unit, formatStr, prefix, suffix)
    if not UnitHealthPercentAPI or not unit.unitid then return false end
    local percent = UnitHealthPercentAPI(unit.unitid, false, CurveConstantsRef and CurveConstantsRef.ScaleTo100 or nil)
    if percent and (issecretvalue and issecretvalue(percent)) then
        -- Store format data for NeatPlatesCore to use with SetFormattedText
        unit.healthTextFormat = formatStr
        unit.healthTextValue = percent
        unit.healthTextPrefix = prefix or ""
        unit.healthTextSuffix = suffix or ""
        return true
    end
    return false
end

-- Helper to set format data for exact health display using BreakUpLargeNumbers
-- BreakUpLargeNumbers accepts secret values and returns a formatted string with thousand separators
-- Returns true if format data was set (caller should return nil for text)
local function SetHealthExactFormat(unit, formatStr)
    if not unit.unitid then return false end
    local health = UnitHealth(unit.unitid)
    if health and (issecretvalue and issecretvalue(health)) then
        -- BreakUpLargeNumbers accepts secret values and returns formatted string
        local healthStr = BreakUpLargeNumbers(health)
        unit.healthTextFormat = formatStr
        unit.healthTextValue = healthStr
        return true
    end
    return false
end

-- Helper to set format data for abbreviated health display using AbbreviateNumbers
-- AbbreviateNumbers accepts secret values and returns a shortened string (e.g., "1.5M")
-- Returns true if format data was set (caller should return nil for text)
local function SetHealthApproxFormat(unit, formatStr)
    if not unit.unitid then return false end
    local health = UnitHealth(unit.unitid)
    if health and (issecretvalue and issecretvalue(health)) then
        -- AbbreviateNumbers accepts secret values and returns abbreviated string
        local healthStr = AbbreviateNumbers(health)
        unit.healthTextFormat = formatStr
        unit.healthTextValue = healthStr
        return true
    end
    return false
end

-- Colors
--local White = {r = 1, g = 1, b = 1}
--local WhiteColor = { r = 250/255, g = 250/255, b = 250/255, }





------------------------------------------------------------------------------
-- Unit name text
------------------------------------------------------------------------------

local function UnitNameDelegate(unit)
	local unitname = unit.name
	-- 12.0.0+: unit.name, unit.pvpname, unit.rawName can be secret values during combat
	-- Secret values cannot be used in string concatenation or as table indices
	local nameIsSecret = issecretvalue and issecretvalue(unitname)

	if LocalVars.TextShowUnitTitle then
		local pvpname = unit.pvpname
		if pvpname then
			if issecretvalue and issecretvalue(pvpname) then
				-- pvpname is secret, fall back to unitname as-is
			else
				unitname = pvpname
				nameIsSecret = false
			end
		end
	end

	if LocalVars.TextShowServerIndicator and unit.realm then
		if not nameIsSecret and not (issecretvalue and issecretvalue(unit.realm)) then
			unitname = unitname.." (*)"
		end
	end

	-- Overwrite current name with Arena ID
	local rawName = unit.rawName
	if not (issecretvalue and issecretvalue(rawName)) then
		local arenaindex = GetArenaIndex(rawName)
		if LocalVars.TextUnitNameArenaID and unit.type == "PLAYER" and arenaindex then unitname = tostring(arenaindex) end
	end

	return unitname
end


------------------------------------------------------------------------------
-- Optional/Health Text
------------------------------------------------------------------------------


local function GetLevelDescription(unit)
	local description = ""
	description = "Level "..unit.level
	if unit.isElite then description = description.." (Elite)" end
	return description
end


local function ShortenNumber(number)
	if not number then return "" end

	if LocalVars.AltShortening and number > 100000000 then
		return (ceil((number/10000000))/10).." "..L["SHORT_ONE_HUNDRED_MILLION"] --"亿"
	elseif not LocalVars.AltShortening and number > 1000000 then
		return (ceil((number/100000))/10).." "..L["SHORT_MILLION"]
	elseif LocalVars.AltShortening and number > 10000 then
		return (ceil((number/1000))/10).." "..L["SHORT_TEN_THOUSAND"]	--"万"
	elseif not LocalVars.AltShortening and number > 1000 then
		return (ceil((number/100))/10).." "..L["SHORT_THOUSAND"]
	else
		return number
	end
end

local function SepThousands(number)
	if not number then return "" end
	local n = tonumber(number)

	local left, num, right = string.match(n, '^([^%d]*%d)(%d*)(.-)')
	return left..(num:reverse():gsub('(%d%d%d)', '%1,'):reverse())..right
end


local function TextFunctionMana(unit)
	if (unit.isTarget or (LocalVars.FocusAsTarget and unit.isFocus)) then
		local unitPower = UnitPower("target")
		local unitPowerMax = UnitPowerMax("target")
		-- Check for secret values before arithmetic (12.0.0+)
		if issecretvalue and (issecretvalue(unitPower) or issecretvalue(unitPowerMax)) then
			return nil
		end
		if unitPowerMax == 0 then return nil end
		local power = ceil((unitPower / unitPowerMax)*100)
		--local r, g, b = UnitPowerType("target")
		--local powername = _G[select(2, UnitPowerType("target"))]
		--if power and power > 0 then	return power.."% "..powername end
		local powertype = select(2,UnitPowerType("target"))
		local powercolor = PowerBarColor[powertype]
		local powername = _G[powertype]
		---print(power, powertype, powercolor, powercolor.r, powercolor.g, powercolor.b)
		if power and power > 0 then return power.."% "..powername, powercolor.r, powercolor.g, powercolor.b, 1 end
	end
end

local function GetHealth(unit)
	-- Use safe value for display to handle 12.0.0+ secret values
	return SafeNumber(unit.health, unit.healthSafe or 0)
end

local function GetHealthMax(unit)
	-- Use safe value for display to handle 12.0.0+ secret values
	return SafeNumber(unit.healthmax, unit.healthmaxSafe or 1)
end

-- None
local function HealthFunctionNone() return "" end

local function GetHealthPercent(unit)
	local precision = LocalVars.TextHealthPercentPrecision
	local f = '1'
	for i=precision,1,-1 do f = f..'0' end
	f = tonumber(f)
	-- Use SafeHealthPercent for 12.0.0+ secret value handling
	local hpercent = 100 * SafeHealthPercent(unit) * f


	return tonumber(string.format("%." .. (precision or 0) .. "f", ceil(hpercent) / f)) --Ceil to prevent health from showing as 0 while still being alive
end
-- Percent
local function TextHealthPercent(unit)
	-- 12.0.0+: Use SetFormattedText approach for secret values
	local precision = LocalVars.TextHealthPercentPrecision or 0
	local formatStr = "%." .. precision .. "f%%"
	if SetHealthPercentFormat(unit, formatStr) then
		return nil  -- Signal to use format data via SetFormattedText
	end
	-- Fallback for non-secret values or older clients
	return GetHealthPercent(unit).."%"
end

local function TextHealthPercentColored(unit)
	local color = ColorFunctionByHealth(unit)
	-- 12.0.0+: Use SetFormattedText approach for secret values
	local precision = LocalVars.TextHealthPercentPrecision or 0
	local formatStr = "%." .. precision .. "f%%"
	if SetHealthPercentFormat(unit, formatStr) then
		return nil, color.r, color.g, color.b, .7  -- Signal to use format data
	end
	return GetHealthPercent(unit).."%", color.r, color.g, color.b, .7
end

local function HealthFunctionPercent(unit)
	-- Use SafeIsDamaged for 12.0.0+ secret value handling
	if SafeIsDamaged(unit) then
		return TextHealthPercent(unit)
	else return "" end
end

local function HealthFunctionPercentColored(unit)
	-- Use SafeIsDamaged for 12.0.0+ secret value handling
	if SafeIsDamaged(unit) then
		return TextHealthPercentColored(unit)
	else return "" end
end

-- Actual (Exact Health with thousand separators)
local function HealthFunctionExact(unit)
	-- 12.0.0+: Use SetFormattedText approach for secret values
	if SetHealthExactFormat(unit, "%s") then
		return nil  -- Signal to use format data via SetFormattedText
	end
	-- Fallback for non-secret values or older clients
	return SepThousands(GetHealth(unit))
end
-- Approximate (Shortened health like "1.5M" or "500K")
local function HealthFunctionApprox(unit)
	-- 12.0.0+: Use SetFormattedText approach for secret values
	if SetHealthApproxFormat(unit, "%s") then
		return nil  -- Signal to use format data via SetFormattedText
	end
	-- Fallback for non-secret values or older clients
	return ShortenNumber(GetHealth(unit))
end
-- Approximate Health and Percent
local function HealthFunctionApproxAndPercent(unit)
	local color = ColorFunctionByHealth(unit)
	-- 12.0.0+: For composite text, we need a two-part format
	-- SetFormattedText can handle: "%s  (%.0f%%)" with health string and percent number
	local precision = LocalVars.TextHealthPercentPrecision or 0
	local formatStr = "%s  (%." .. precision .. "f%%)"
	if UnitHealthPercentAPI and unit.unitid then
		local health = UnitHealth(unit.unitid)
		local percent = UnitHealthPercentAPI(unit.unitid, false, CurveConstantsRef and CurveConstantsRef.ScaleTo100 or nil)
		if percent and (issecretvalue and issecretvalue(percent)) then
			-- Use AbbreviateNumbers which accepts secret values
			local healthStr = AbbreviateNumbers(health)
			unit.healthTextFormat = formatStr
			unit.healthTextValue = percent
			unit.healthTextPrefix = healthStr
			unit.healthTextComposite = true  -- Signal this is a composite format
			return nil, color.r, color.g, color.b, .7
		end
	end
	return ShortenNumber(GetHealth(unit)).."  ("..GetHealthPercent(unit).."%)", color.r, color.g, color.b, .7
end
-- Deficit (Note: Cannot use secret values directly since arithmetic is required)
-- Falls back to safe values which provide reasonable estimates
local function HealthFunctionDeficit(unit)
	local health, healthmax = GetHealth(unit), GetHealthMax(unit)
	if health and healthmax and (health ~= healthmax) then return "-"..SepThousands(healthmax - health) end
end
-- Total and Percent (Abbreviated health with percent)
local function HealthFunctionTotal(unit)
	local color = ColorFunctionByHealth(unit)
	--local color = HubData.Colors.White
	-- 12.0.0+: For composite text with color codes, use special format
	local precision = LocalVars.TextHealthPercentPrecision or 0
	local formatStr = "%s|cffffffff (%." .. precision .. "f%%)"
	if UnitHealthPercentAPI and unit.unitid then
		local health = UnitHealth(unit.unitid)
		local percent = UnitHealthPercentAPI(unit.unitid, false, CurveConstantsRef and CurveConstantsRef.ScaleTo100 or nil)
		if percent and (issecretvalue and issecretvalue(percent)) then
			-- Use AbbreviateNumbers which accepts secret values
			local healthStr = AbbreviateNumbers(health)
			unit.healthTextFormat = formatStr
			unit.healthTextValue = percent
			unit.healthTextPrefix = healthStr
			unit.healthTextComposite = true
			return nil, color.r, color.g, color.b
		end
	end
	return ShortenNumber(GetHealth(unit)).."|cffffffff ("..GetHealthPercent(unit).."%)", color.r, color.g, color.b
end
-- Exact Health and Percent (Full number with thousand separators plus percent)
local function HealthFunctionExactTotal(unit)
	local color = ColorFunctionByHealth(unit)
	--local color = HubData.Colors.White
	-- 12.0.0+: For composite text with color codes, use special format
	local precision = LocalVars.TextHealthPercentPrecision or 0
	local formatStr = "%s|cffffffff (%." .. precision .. "f%%)"
	if UnitHealthPercentAPI and unit.unitid then
		local health = UnitHealth(unit.unitid)
		local percent = UnitHealthPercentAPI(unit.unitid, false, CurveConstantsRef and CurveConstantsRef.ScaleTo100 or nil)
		if percent and (issecretvalue and issecretvalue(percent)) then
			-- Use BreakUpLargeNumbers which accepts secret values and adds thousand separators
			local healthStr = BreakUpLargeNumbers(health)
			unit.healthTextFormat = formatStr
			unit.healthTextValue = percent
			unit.healthTextPrefix = healthStr
			unit.healthTextComposite = true
			return nil, color.r, color.g, color.b
		end
	end
	return SepThousands(GetHealth(unit)).."|cffffffff ("..GetHealthPercent(unit).."%)", color.r, color.g, color.b
end
-- TargetOf
local function HealthFunctionTargetOf(unit)
	if unit.isInCombat then
		local targetname
		-- Use UnitSpellTargetName (12.0.0+) with secret value handling and fallback
		if UnitSpellTargetName then
			targetname = UnitSpellTargetName(unit.unitid)
			if issecretvalue and issecretvalue(targetname) then targetname = nil end
		end
		-- Fallback to unit..target approach if API unavailable or returned secret/nil
		if not targetname then
			targetname = UnitName(unit.unitid.."target")
			if issecretvalue and issecretvalue(targetname) then targetname = nil end
		end
		return targetname
	end
	--[[
	if (unit.isTarget or (LocalVars.FocusAsTarget and unit.isFocus)) then return UnitName("targettarget")
	elseif unit.isMouseover then return UnitName("mouseovertarget")
	else return "" end
	--]]
end
-- TargetOf(Class Color)
local function HealthFunctionTargetOfClass(unit)
	if unit.isInCombat then
		local targetof = unit.unitid.."target"
		local name, targetclass

		-- Use UnitSpellTargetName/Class (12.0.0+) with secret value handling and fallback
		if UnitSpellTargetName then
			name = UnitSpellTargetName(unit.unitid)
			targetclass = UnitSpellTargetClass(unit.unitid)
			if issecretvalue and issecretvalue(name) then name = nil end
			if issecretvalue and issecretvalue(targetclass) then targetclass = nil end
		end

		-- Fallback to unit..target approach if API unavailable or returned secret/nil
		if not name then
			name = UnitName(targetof)
			if issecretvalue and issecretvalue(name) then name = nil end
		end
		if not targetclass and UnitIsPlayer(targetof) then
			targetclass = select(2, UnitClass(targetof))
			if issecretvalue and issecretvalue(targetclass) then targetclass = nil end
		end

		name = name or ""

		if targetclass and NEATPLATES_CLASS_COLORS[targetclass] then
			return ConvertRGBtoColorString(NEATPLATES_CLASS_COLORS[targetclass])..name
		else
			return name
		end
	end
end
-- Level
local function HealthFunctionLevel(unit)
	local level = unit.level
	if unit.isElite then level = level.." (Elite)" end
	return level, unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue, .9
end

-- Level and Health
local function HealthFunctionLevelHealth(unit)
	local level = unit.level
	if unit.isElite then level = level.."E" end
	-- 12.0.0+: Handle secret values with SetFormattedText
	local formatStr = "("..level..") |cffffffff%s"
	if unit.unitid then
		local health = UnitHealth(unit.unitid)
		if health and (issecretvalue and issecretvalue(health)) then
			local healthStr = AbbreviateNumbers(health)
			unit.healthTextFormat = formatStr
			unit.healthTextValue = healthStr
			return nil, unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue, .9
		end
	end
	return "("..level..") |cffffffff"..ShortenNumber(GetHealth(unit)), unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue, .9
end

-- Arena ID
local function HealthFunctionArenaIDOnly(unit)
	local powercolor = HubData.Colors.White
	local arenastring = ""
	local arenaindex = GetArenaIndex(unit.rawName)

	--arenaindex = 2	-- Tester
	if unit.type == "PLAYER" then

		if arenaindex and arenaindex > 0 then
			arenastring = "|cffffcc00["..(tostring(arenaindex)).."]  |r"
		end
	end

--[[
-- Test Strings
	--arenastring = "|cffffcc00["..(tostring(2)).."]  |r"
	arenastring = "|cffffcc00#"..(tostring(2)).."  |r"
	--powercolor = HubData.Colors.White
--]]

	return arenastring, powercolor.r, powercolor.g, powercolor.b, 1

	--[[
	Arena ID, HealthFraction, ManaPercent
	#1  65%  75%

	Arena ID, HealthK, ManaFraction
	#2  300k  75%

	--]]
end
local TextArenaIDOnly = HealthFunctionArenaIDOnly

-- Arena Vitals (ID, Mana, Health)
local function HealthFunctionArenaID(unit)
	local localid
	local powercolor = HubData.Colors.White
	local powerstring = ""
	local arenastring = ""
	local arenaindex = GetArenaIndex(unit.rawName)

	--arenaindex = 2	-- Tester
	if unit.type == "PLAYER" then

		if arenaindex and arenaindex > 0 then
			arenastring = "|cffffcc00["..(tostring(arenaindex)).."]  |r"
		end


		if (unit.isTarget or (LocalVars.FocusAsTarget and unit.isFocus)) then localid = "target"
		elseif unit.isMouseover then localid = "mouseover"
		end


		if localid then
			local unitPower = UnitPower(localid)
			local unitPowerMax = UnitPowerMax(localid)
			-- Check for secret values before arithmetic (12.0.0+)
			if not (issecretvalue and (issecretvalue(unitPower) or issecretvalue(unitPowerMax))) and unitPowerMax > 0 then
				local power = ceil((unitPower / unitPowerMax)*100)
				local powerindex, powertype = UnitPowerType(localid)

				--local powername = _G[powertype]

				if power and power > 0 then
					powerstring = "  "..power.."%"		--..powername
					powercolor = PowerBarColor[powerindex] or HubData.Colors.White
				end
			end
		end
	end

	-- 12.0.0+: Handle secret values with SetFormattedText
	if unit.unitid then
		local health = UnitHealth(unit.unitid)
		if health and (issecretvalue and issecretvalue(health)) then
			local healthStr = AbbreviateNumbers(health)
			local formatStr = arenastring.."|cffffffff%s|cff0088ff"..powerstring
			unit.healthTextFormat = formatStr
			unit.healthTextValue = healthStr
			return nil, powercolor.r, powercolor.g, powercolor.b, 1
		end
	end

	local health = ShortenNumber(GetHealth(unit))
	local healthstring = "|cffffffff"..health.."|cff0088ff"

--[[
-- Test Strings
	powerstring = "  ".."43".."%"
	--arenastring = "|cffffcc00["..(tostring(2)).."]  |r"
	arenastring = "|cffffcc00#"..(tostring(2)).."  |r"
	powercolor = PowerBarColor[2]
--]]

	--	return '4'.."|r"..(powerstring or "")
	return arenastring..healthstring..powerstring, powercolor.r, powercolor.g, powercolor.b, 1

	--[[
	Arena ID, HealthFraction, ManaPercent
	#1  65%  75%

	Arena ID, HealthK, ManaFraction
	#2  300k  75%

	--]]
end


local HealthTextModesCustom = {}


--[[
local hexChars = {
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"A",
	"B",
	"C",
	"D",
	"E",
	"F",
}


local function intToHex(num)
	--local sig, sep
	--sig = fmod(num, 16)
	sep = num - sig*16
	return hexChars[sig]..hexChars[sep]
end

--]]


-- Custom
local function HealthFunctionCustom(unit)

	local LeftText, RightText, CenterText = "", "", ""

	--HealthTextModesCustom[LocalVars.StatusTextLeft]


	return LeftText, RightText, CenterText
	--if LocalVars.CustomHealthFunction then return LocalVars.CustomHealthFunction(unit) end

	--HealthTextModesCustom(mode, addColor)

	--[[
	FriendlyStatusTextMode
	FriendlyStatusTextModeCenter
	FriendlyStatusTextModeRight

	EnemyStatusTextMode
	EnemyStatusTextModeCenter
	EnemyStatusTextModeRight
	--]]


	--[[
	StatusTextLeft = 8,
	StatusTextCenter = 5,
	StatusTextRight = 7,

	StatusTextLeftColor = true,
	StatusTextCenterColor = true,
	StatusTextRightColor = true,

	--]]
end

local HealthTextModeFunctions = {}


NeatPlatesHubDefaults.FriendlyStatusTextMode = "HealthFunctionNone"
NeatPlatesHubDefaults.EnemyStatusTextMode = "HealthFunctionNone"

AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionNone, L["None"], "HealthFunctionNone")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionPercent, L["Percent Health"], "HealthFunctionPercent")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionPercentColored, L["Percent Health (Colored)"], "HealthFunctionPercentColored")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionExact, L["Exact Health"], "HealthFunctionExact")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionApprox, L["Approximate Health"], "HealthFunctionApprox")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionDeficit, L["Health Deficit"], "HealthFunctionDeficit")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionTotal, L["Health Total & Percent"], "HealthFunctionTotal")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionExactTotal, L["Exact Health & Percent"], "HealthFunctionExactTotal")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionTargetOf, L["Target Of"], "HealthFunctionTargetOf")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionTargetOfClass, L["Target Of (Class Colored)"], "HealthFunctionTargetOfClass")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionLevel, L["Level"], "HealthFunctionLevel")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionLevelHealth, L["Level and Approx Health"], "HealthFunctionLevelHealth")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionArenaIDOnly, L["Arena ID"], "HealthFunctionArenaIDOnly")
AddHubFunction(HealthTextModeFunctions, NeatPlatesHubMenus.TextModes, HealthFunctionArenaID, L["Arena ID, Health, and Power"], "HealthFunctionArenaID")


local function HealthTextDelegate(unit)

	local func
	local mode = 1
	local showText = not (LocalVars.TextShowOnlyOnTargets or LocalVars.TextShowOnlyOnActive)

	if unit.reaction == "FRIENDLY" then mode = LocalVars.FriendlyStatusTextMode
	else mode = LocalVars.EnemyStatusTextMode end

	func = HealthTextModeFunctions[mode] or DummyFunction

	if LocalVars.TextShowOnlyOnTargets then
		if ((unit.isTarget or (LocalVars.FocusAsTarget and unit.isFocus)) or unit.isMouseover or unit.isMarked) then showText = true end
	end

	if LocalVars.TextShowOnlyOnActive then
		-- Use SafeIsDamaged for 12.0.0+ secret value handling
		if (unit.isMarked) or (unit.threatValue > 0) or SafeIsDamaged(unit) then showText = true end
	end

	if showText then return func(unit) end
end



------------------------------------------------------------------------------------
-- Binary/Headline Text Styles
------------------------------------------------------------------------------------
local function RoleOrGuildText(unit)
	if unit.type == "NPC" then
		return (GetUnitSubtitle(unit) or GetLevelDescription(unit) or "") , 1, 1, 1, .70
	end
end

-- Role, Guild or Level
local function TextRoleGuildLevel(unit)
	local description
	local r, g, b = 1,1,1

	if unit.type == "NPC" then
		description = GetUnitSubtitle(unit)

		if not description then --  and unit.reaction ~= "FRIENDLY" then
			description =  GetLevelDescription(unit)
			r, g, b = .7, .7, .9
			--r, g, b = unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue
		end

	elseif unit.type == "PLAYER" then
		description = GetGuildInfo(unit.unitid)
		r, g, b = .7, .7, .9
	end

	return description, r, g, b, .70
end



local function TextRoleGuild(unit)
	local description
	local r, g, b = 1,1,1

	if unit.type == "NPC" then
		description = GetUnitSubtitle(unit)

	elseif unit.type == "PLAYER" then
		description = GetGuildInfo(unit.unitid)
		--description = CachedUnitGuild(unit.name)
		r, g, b = .7, .7, .9
	end

	return description, r, g, b, .70
end

local function TextRoleClass(unit)
	local description, faction
	local r, g, b = 1,1,1

	if unit.type == "NPC" then
		description = GetUnitSubtitle(unit)
		if not description then
			faction, description = UnitFactionGroup(unit.unitid)
		end

	elseif unit.type == "PLAYER" then
		description = UnitClassBase(unit.unitid)
		local classColor = NEATPLATES_CLASS_COLORS[unit.class]
		r, g, b = classColor.r, classColor.g, classColor.b
	end

	return description, r, g, b, .70
end


-- NPC Role
local function TextNPCRole(unit)
	if unit.type == "NPC" then
		-- Prototype for displaying quest information on Nameplates
		--local questName, questObjective = GetUnitQuestInfo(unit)
		--return questObjective

		return GetUnitSubtitle(unit)
	end
end

local function TextUnitTitle(unit)
	local color = HubData.Colors.White
	if unit.pvpname and unit.name then
		-- 12.0.0+: pvpname and name can be secret values during combat; cannot use in string operations
		if issecretvalue and (issecretvalue(unit.pvpname) or issecretvalue(unit.name)) then return nil end
		return string.gsub(unit.pvpname, '%s*'..unit.name, ''), color.r, color.g, color.b, .7
	end
end

local function TextQuest(unit)
	if unit.type == "NPC" then

		-- Prototype for displaying quest information on Nameplates
		-- Return first incomplete questObjective found
		local questList = GetUnitQuestInfo(unit)
		for questName, questObjectives in pairs(questList) do
			for questObjective, questCompleted in pairs(questObjectives) do
				if not questCompleted then
					return questObjective
				end
			end
		end
	end
end

-- Role or Guild
local function TextRoleGuildQuest(unit)
	local r, g, b = 1, .9, .7
	return TextQuest(unit) or TextRoleGuild(unit), r, g, b, .70
end


-- Level
local function TextLevelColored(unit)
	--return GetLevelDescription(unit) , 1, 1, 1, .70
	return GetLevelDescription(unit) , unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue, .70
end

-- Guild, Role, Level, Health
local function TextAll(unit)
	-- local color = ColorFunctionByHealth(unit) --6.0
	local color = HubData.Colors.White
	-- Use SafeIsDamaged for 12.0.0+ secret value handling
	if SafeIsDamaged(unit) then
		-- 12.0.0+: Use SetFormattedText approach for secret values
		local precision = LocalVars.TextHealthPercentPrecision or 0
		local formatStr = "%." .. precision .. "f%%"
		if SetHealthPercentFormat(unit, formatStr) then
			return nil, color.r, color.g, color.b, .7
		end
		return GetHealthPercent(unit).."%", color.r, color.g, color.b, .7
	else
		--return GetLevelDescription(unit) , unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue, .7
		return TextQuest(unit) or TextRoleGuildLevel(unit)
	end
end


local EnemyNameSubtextFunctions = {}
NeatPlatesHubMenus.EnemyNameSubtextModes = {}
NeatPlatesHubDefaults.HeadlineEnemySubtext = "RoleGuildLevel"
NeatPlatesHubDefaults.HeadlineFriendlySubtext = "RoleGuildLevel"
NeatPlatesHubDefaults.EnemySubtext = "None"
NeatPlatesHubDefaults.FriendlySubtext = "None"
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, DummyFunction, L["None"], "None")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextHealthPercentColored, L["Percent Health (Colored)"], "PercentHealthColored")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextHealthPercent, L["Percent Health"], "PercentHealth")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextRoleGuildLevel, L["NPC Role, Guild, or Level"], "RoleGuildLevel")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextRoleGuildQuest, L["NPC Role, Guild, or Quest"], "RoleGuildQuest")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextRoleGuild, L["NPC Role, Guild"], "RoleGuild")
--AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextRoleClass, "Role or Class", "RoleClass")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextNPCRole, L["NPC Role"], "Role")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextUnitTitle, L["Unit Title"], "UnitTitle")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextLevelColored, L["Level"], "Level")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextQuest, L["Quest"], "Quest")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextArenaIDOnly, L["Arena ID"], "TextArenaIDOnly")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, TextAll, L["Everything"], "RoleGuildLevelHealth")

AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, HealthFunctionExact, L["Exact Health"], "HealthFunctionExact")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, HealthFunctionApprox, L["Approximate Health"], "HealthFunctionApprox")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, HealthFunctionDeficit, L["Health Deficit"], "HealthFunctionDeficit")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, HealthFunctionTotal, L["Health Total & Percent"], "HealthFunctionTotal")
AddHubFunction(EnemyNameSubtextFunctions, NeatPlatesHubMenus.EnemyNameSubtextModes, HealthFunctionExactTotal, L["Exact Health & Percent"], "HealthFunctionExactTotal")

--[[
local FriendlyNameSubtextFunctions = {}
NeatPlatesHubMenus.FriendlyNameSubtextModes = {}
NeatPlatesHubDefaults.HeadlineFriendlySubtext = "None"
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, DummyFunction, "None", "None")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextHealthPercentColored, "Percent Health", "PercentHealth")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextRoleGuildLevel, "Role, Guild or Level", "RoleGuildLevel")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextRoleGuild, "Role or Guild", "RoleGuild")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextNPCRole, "NPC Role", "Role")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextLevelColored, "Level", "Level")
AddHubFunction(FriendlyNameSubtextFunctions, NeatPlatesHubMenus.FriendlyNameSubtextModes, TextAll, "Role, Guild, Level or Health Percent", "RoleGuildLevelHealth")
--]]

local function SubTextDelegate(unit)
	--if unit.style == "NameOnly" then
	local func
	if StyleDelegate(unit) == "NameOnly" then
		if unit.reaction == "FRIENDLY" then
			func = EnemyNameSubtextFunctions[LocalVars.HeadlineFriendlySubtext or 0] or DummyFunction
		else
			func = EnemyNameSubtextFunctions[LocalVars.HeadlineEnemySubtext or 0] or DummyFunction
		end
	else
		if unit.reaction == "FRIENDLY" then
			func = EnemyNameSubtextFunctions[LocalVars.FriendlySubtext or 0] or DummyFunction
		else
			func = EnemyNameSubtextFunctions[LocalVars.EnemySubtext or 0] or DummyFunction
		end
	end

	local text, r, g, b, a = func(unit)
	local c = {}

	-- Override the color from the function with the color chosen by the user
	if unit.reaction == "FRIENDLY" and (LocalVars.FriendlySubtextColor["a"] > 0 and text and text ~= "") then
		c = LocalVars.FriendlySubtextColor
	elseif unit.reaction ~= "FRIENDLY" and (LocalVars.EnemySubtextColor["a"] > 0 and text and text ~= "") then
		c = LocalVars.EnemySubtextColor
	end

	return text, (c.r or r), (c.g or g), (c.b or b), (c.a or a)
end

local function CastbarDurationRemaining(currentTime, startTime, endTime, isChannel)
	local text = tonumber(round((endTime - currentTime)/1000, 1))
	if text <= 0 then text = "" end
	return text
end

local function CastbarDurationElapsed(currentTime, startTime, endTime, isChannel)
	local maxCast = round((endTime - startTime)/1000, 1)
	return math.min(maxCast, round((currentTime - startTime)/1000, 1))
end

local function CastbarDurationCastTime(currentTime, startTime, endTime, isChannel)
	local text = ""
	local maxCast = round((endTime - startTime)/1000, 1)
	if isChannel then
		text = math.max(0, round((endTime - currentTime)/1000, 1)).."/"..maxCast
	else
		text = math.min(maxCast, round((currentTime - startTime)/1000, 1)).."/"..maxCast
	end
	return text
end

local CastbarDurationFunctions = {}
NeatPlatesHubMenus.CastbarDurationModes = {}
NeatPlatesHubDefaults.CastbarDurationMode = "None"
AddHubFunction(CastbarDurationFunctions, NeatPlatesHubMenus.CastbarDurationModes, DummyFunction, L["None"], "None")
AddHubFunction(CastbarDurationFunctions, NeatPlatesHubMenus.CastbarDurationModes, CastbarDurationRemaining, L["Time Remaining"], "TimeRemaining")
AddHubFunction(CastbarDurationFunctions, NeatPlatesHubMenus.CastbarDurationModes, CastbarDurationElapsed, L["Time Elapsed"], "TimeElapsed")
AddHubFunction(CastbarDurationFunctions, NeatPlatesHubMenus.CastbarDurationModes, CastbarDurationCastTime, L["Time Elapsed/Cast Time"], "TimeCastTime")

local function CastbarDurationDelegate(...)
	local func = CastbarDurationFunctions[LocalVars.CastbarDurationMode or 0] or DummyFunction
	return func(...)
end

------------------------------------------------------------------------------
-- Local Variable
------------------------------------------------------------------------------

local function OnVariableChange(vars) LocalVars = vars end
HubData.RegisterCallback(OnVariableChange)


------------------------------------------------------------------------------
-- Add References
------------------------------------------------------------------------------



NeatPlatesHubFunctions.SetCustomText = HealthTextDelegate
NeatPlatesHubFunctions.SetSubText = SubTextDelegate
NeatPlatesHubFunctions.SetCastbarDuration = CastbarDurationDelegate
NeatPlatesHubFunctions.GetArenaIndex = GetArenaIndex
NeatPlatesHubFunctions.SetUnitName = UnitNameDelegate

