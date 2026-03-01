local L = LibStub("AceLocale-3.0"):GetLocale("NeatPlates")
NeatPlatesWidgetSettings = {
	RaidTankList = {}
}

-- 12.0.0 API compatibility wrappers
local CombatLogGetCurrentEventInfo = C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
local GetSpecializationRole = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole or GetSpecializationRole
local issecretvalue = issecretvalue or function() return false end

-- UnitBuff deprecation compatibility - returns spellId from buff at index
local function GetBuffSpellId(unit, index)
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local auraData = C_UnitAuras.GetBuffDataByIndex(unit, index)
		return auraData and auraData.spellId
	else
		return select(10, UnitBuff(unit, index))
	end
end

local function _IsEquippedItemType(type)
	local result
	if C_Item and C_Item.IsEquippedItemType then
		result = C_Item.IsEquippedItemType(type)
	else
		result = IsEquippedItemType(type)
	end
	return result or false
end

local function _GetSpecialization(...)
    if GetSpecialization then
        return GetSpecialization(...)
    elseif GetPrimaryTalentTree then
        return GetPrimaryTalentTree(...)
    end
    return nil
end

------------------------------
-- Tank Aura/Role Tracking
------------------------------

local GetGroupInfo = NeatPlatesUtility.GetGroupInfo

-- Interface Functions...
---------------------------
local RaidTankList = {}
local inRaid = false
local playerTankRole = false
local currentSpec = 0
local playerClass = select(2, UnitClass("player"))
local rfSpellId = {
	[25780] = true, -- Righteous Fury
	[407627] = true, -- Righteous Fury (Hand of reckoning)
}
local woeSpellId = 408680 -- Way of Earth
local playerGUID = UnitGUID("player")

local cachedAura = false
local cachedRole = false
local TankWatcher
local white, orange, blue, green, red = "|cffffffff", "|cFFFF6906", "|cFF3782D1", "|cFF60E025", "|cFFFF1100"

local function GetSpellID(spellname)
	local id
	if C_Spell and C_Spell.GetSpellID then
		id = C_Spell.GetSpellID(spellname)
	else
		id = select(7, GetSpellInfo(spellname))
	end

	return id
end

local function IsEnemyTanked(unit)
	if NEATPLATES_IS_CLASSIC then
		local unitid = unit.unitid
		local targetOf = unitid.."target"
		--local targetIsTank = UnitIsUnit(targetOf, "pet") or GetPartyAssignment("MAINTANK", targetOf)
		local targetOfGUID = UnitGUID(targetOf)
		local guidTankResult
		if targetOfGUID and not (issecretvalue and issecretvalue(targetOfGUID)) then
			guidTankResult = RaidTankList[targetOfGUID]
		end
		local isUnitPet = UnitIsUnit(targetOf, "pet")
		if issecretvalue and issecretvalue(isUnitPet) then isUnitPet = false end
		local targetIsTank = guidTankResult or isUnitPet

		return targetIsTank
	else
		local unitid = unit.unitid
		local targetOf = unitid.."target"
		local rawTargetGUID = UnitGUID(targetOf)
		local targetGUID
		local targetIsGuardian = false
		local guardians = {
			["61146"] = true, 	-- Black Ox Statue(61146)
			["103822"] = true,	-- Treant(103822)
			["61056"] = true, 	-- Primal Earth Elemental(61056)
			["95072"] = true, 	-- Greater Earth Elemental(95072)
		}

		if rawTargetGUID and not (issecretvalue and issecretvalue(rawTargetGUID)) then
			targetGUID = select(6, strsplit("-", rawTargetGUID))
			targetIsGuardian = guardians[targetGUID]
		end
		-- GetPartyAssignment("MAINTANK", raidid)
		local isUnitPet = UnitIsUnit(targetOf, "pet")
		if issecretvalue and issecretvalue(isUnitPet) then isUnitPet = false end
		local targetIsTank = isUnitPet or targetIsGuardian or ("TANK" ==  UnitGroupRolesAssigned(targetOf))

		return targetIsTank
	end
end

local function IsPlayerTank()
	return playerTankRole
end

local function HasClassicTankAura()
	if playerClass == "WARRIOR" then
		return GetShapeshiftForm() == 2 or _IsEquippedItemType("Shields") -- Defensive Stance or shield
	elseif playerClass == "DRUID" then
		return GetShapeshiftForm() == 1 -- Bear Form
	elseif playerClass == "PALADIN" then
		-- Righteous Fury
		for i=1,40 do
			local spellId = GetBuffSpellId("player", i)
			if rfSpellId[spellId] then
				return true
			end
		end
	elseif playerClass == "DEATHKNIGHT" then
		if NEATPLATES_IS_CLASSIC_CATA then
			return GetShapeshiftForm() == 1 -- Blood Presence
		else
			return GetShapeshiftForm() == 2 -- Frost Presence
		end
	elseif playerClass == "WARLOCK" then
		return NEATPLATES_IS_CLASSIC_ERA and GetShapeshiftForm() == 1 -- SoD: Metamorphosis
	elseif playerClass == "SHAMAN" then
		-- SoD: Way of Earth
		for i=1,40 do
			local spellId = GetBuffSpellId("player", i)
			if woeSpellId == spellId then
				return true
			end
		end
	elseif playerClass == "ROGUE" then
		return IsSpellKnownOrOverridesKnown(400014) -- SoD: Just a Flesh Wound
	end

	return false
end

local function UpdatePlayerRole(playerTankAura)
	if NEATPLATES_IS_CLASSIC and not NEATPLATES_IS_CLASSIC_MISTS then
		if playerTankAura or HasClassicTankAura() then
			playerTankRole = true
		else
			playerTankRole = false
		end
	else
		-- Look at the Player's Specialization
		local specializationIndex = tonumber(_GetSpecialization())

		if specializationIndex and GetSpecializationRole(specializationIndex) == "TANK" then
			playerTankRole = true
		else
			playerTankRole = false
		end
	end
end

------------------------------------------------------------------------
-- UpdateGroupRoles: Builds a list of tanks and squishies
------------------------------------------------------------------------
local function UpdateGroupRoles()
	if NEATPLATES_IS_CLASSIC then
		if not IsInGroup() then
			RaidTankList = wipe(NeatPlatesWidgetSettings.RaidTankList)
		else

			local groupType, groupSize = GetGroupInfo()
			local raidIndex

			for raidIndex = 1, groupSize do
				local raidid = "raid"..tostring(raidIndex)
				local guid = UnitGUID(raidid)

				local isTank = GetPartyAssignment("MAINTANK", raidid)

				if isTank and guid and not (issecretvalue and issecretvalue(guid)) then
					RaidTankList[guid] = true
				end

			end
		end
	else
		RaidTankList = wipe(RaidTankList)
		-- If a player is in a dungeon, no need for multi-tanking
		if UnitInRaid("player") then
			inRaid = true

			local groupType, groupSize = GetGroupInfo()
			local raidIndex

			for raidIndex = 1, groupSize do
				local raidid = "raid"..tostring(raidIndex)
				local guid = UnitGUID(raidid)

				local isTank = GetPartyAssignment("MAINTANK", raidid) or ("TANK" == UnitGroupRolesAssigned(raidid))

				if isTank and guid and not (issecretvalue and issecretvalue(guid)) then
					RaidTankList[guid] = true
				end

			end

		-- If not in a raid, try to use guardian pet
		-- as a tank..
		else
			inRaid = false
			if HasPetUI("player") and UnitName("pet") then
				local petGUID = UnitGUID("pet")
				if petGUID and not (issecretvalue and issecretvalue(petGUID)) then
					RaidTankList[petGUID] = true
				end
			end
		end

	end
end

local function ToggleTank(arg)
	local isUnitSelf = UnitIsUnit("player", "target")
	if issecretvalue and issecretvalue(isUnitSelf) then isUnitSelf = false end
	if not IsInGroup() or not UnitExists("target") or isUnitSelf or not UnitIsPlayer("target") or not UnitIsFriend("player", "target") then
		if arg ~= "noError" then print(orange..L["NeatPlates"]..": "..red..L["Couldn't update the targets role."]) end
	else
		local name = UnitName("target")
		local guid = UnitGUID("target")
		if not guid or (issecretvalue and issecretvalue(guid)) then return end
		local isTank = GetPartyAssignment("MAINTANK", "target") or not RaidTankList[guid]
		local role
		if isTank then role = blue..L["Tank"] else role = white..L["None"] end

		RaidTankList[guid] = isTank

		print(orange..L["NeatPlates"]..": "..white..name.." - "..role)
	end
end

local function TankWatcherEvents(self, event, ...)
	if NEATPLATES_IS_CLASSIC then
		local tankAura = false
		local triggerUpdate = event ~= "COMBAT_LOG_EVENT_UNFILTERED"

		-- Check for Tank Aura application/removal
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			local _,event,_,sourceGUID,sourceName,sourceFlags,_,destGUID,destName,_,_,spellId,spellName = CombatLogGetCurrentEventInfo()
			if (event == "SPELL_AURA_REMOVED" or event == "SPELL_AURA_APPLIED") and sourceGUID == playerGUID and destGUID == playerGUID then
				spellId = GetSpellID(spellName)
				if rfSpellId[spellId] or woeSpellId == spellId then
					if event == "SPELL_AURA_APPLIED" then tankAura = true end
					triggerUpdate = true
				end
			end
		end

		if triggerUpdate then
			UpdateGroupRoles()
			UpdatePlayerRole(tankAura)
		end
	else
		UpdateGroupRoles()
		UpdatePlayerRole()
	end
end

if not TankWatcher then TankWatcher = CreateFrame("Frame") end
TankWatcher:SetScript("OnEvent", TankWatcherEvents)
TankWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
TankWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
TankWatcher:RegisterEvent("UNIT_PET")
TankWatcher:RegisterEvent("PET_BAR_UPDATE_USABLE")
if not NEATPLATES_IS_CLASSIC then
	TankWatcher:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	TankWatcher:RegisterEvent("PLAYER_TALENT_UPDATE")
else
	if playerClass == "PALADIN" or playerClass == "SHAMAN" then
		TankWatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end
TankWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")


NeatPlatesWidgets.IsEnemyTanked = IsEnemyTanked
NeatPlatesWidgets.IsPlayerTank = IsPlayerTank


--[[
local function Dummy() end
NeatPlatesWidgets.EnableTankWatch = Dummy
NeatPlatesWidgets.DisableTankWatch = Dummy
--]]

if NEATPLATES_IS_CLASSIC then
	SLASH_NeatPlatesTank1 = '/nptank'
	SlashCmdList['NeatPlatesTank'] = ToggleTank;
end