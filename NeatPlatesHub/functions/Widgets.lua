
local AddonName, HubData = ...;
local LocalVars = NeatPlatesHubDefaults
local L = LibStub("AceLocale-3.0"):GetLocale("NeatPlates")

-- Version detection for 12.0.0+ (Midnight)
-- In WoW 12.0+, aura ownership (caster) is a secret value during combat.
-- The main "Show Mine" filter now uses the |PLAYER API filter (handled in AuraWidget.lua).
-- This flag is still used for custom aura lists with "my" prefix, which need special handling
-- since the |PLAYER filter is applied globally and custom lists may need different behavior.
local isWoW12Plus = NeatPlatesHubHelpers and NeatPlatesHubHelpers.isMidnight or (select(4, GetBuildInfo()) >= 120000)

-- Widget Helpers
local WidgetLib = NeatPlatesWidgets
local copytable = NeatPlatesUtility.copyTable

local CreateThreatLineWidget = WidgetLib.CreateThreatLineWidget
local CreateAuraWidget = WidgetLib.CreateAuraWidget
local CreateArenaWidget = WidgetLib.CreateArenaWidget
local CreateClassWidget = WidgetLib.CreateClassWidget
local CreateRangeWidget = WidgetLib.CreateRangeWidget
local CreateComboPointWidget = WidgetLib.CreateComboPointWidget
local CreateTotemIconWidget = WidgetLib.CreateTotemIconWidget
local CreateAbsorbWidget = WidgetLib.CreateAbsorbWidget
local CreateQuestWidget = WidgetLib.CreateQuestWidget
local CreateThreatPercentageWidget = WidgetLib.CreateThreatPercentageWidget
local CreateResourceWidget = WidgetLib.CreateResourceWidget
local issecretvalue = issecretvalue or function() return false end

NeatPlatesHubDefaults.WidgetRangeMode = 1
NeatPlatesHubMenus.RangeModes = {
				{ text = L["Simple"]} ,
				{ text = L["Advanced"]} ,
			}

NeatPlatesHubDefaults.WidgetRangeStyle = 1
NeatPlatesHubMenus.RangeStyles = {
				{ text = L["Line"]} ,
				{ text = L["Icon"]} ,
			}

NeatPlatesHubDefaults.WidgetRangeUnits = 2
NeatPlatesHubMenus.RangeUnits = {
				{ text = L["Target Only"]} ,
				{ text = L["All Units"]} ,
			}

NeatPlatesHubDefaults.WidgetAbsorbMode = 1
NeatPlatesHubMenus.AbsorbModes = {
				{ text = L["Blizzlike"]} ,
				{ text = L["Overlay"]} ,
			}

NeatPlatesHubDefaults.WidgetAbsorbUnits = 1
NeatPlatesHubMenus.AbsorbUnits = {
				{ text = L["Target Only"]} ,
				{ text = L["All Units"]} ,
			}

NeatPlatesHubDefaults.WidgetDebuffStyle = 1
NeatPlatesHubMenus.DebuffStyles = {
				{ text = L["Wide"],  } ,
				{ text = L["Compact"],  } ,
				{ text = L["Blizzlike"],  } ,
			}

NeatPlatesHubDefaults.WidgetDebuffFilter = 2 -- Show Mine by default
NeatPlatesHubDefaults.WidgetBuffFilter = 1 -- Show None by default
NeatPlatesHubMenus.PrimaryAuraFilters = {
				{ text = L["Show None"],  } ,
				{ text = L["Show Mine"],  } ,
				{ text = L["Show All"],  } ,
			}

NeatPlatesHubDefaults.WidgetComboPoints = 1
NeatPlatesHubMenus.ComboPointsModes = {
				{ text = L["Enemy Units"],  } ,
				{ text = L["Friendly Units"],  } ,
				{ text = L["All Units"],  } ,
				{ text = L["None"],  } ,
			}

NeatPlatesHubDefaults.WidgetComboPointsStyle = 2
NeatPlatesHubMenus.ComboPointsStyles = {
				{ text = L["Blizzlike"],  } ,
				{ text = L["NeatPlates"],  } ,
				{ text = L["NeatPlatesTraditional"],  } ,
			}

NeatPlatesHubDefaults.WidgetResourceSpacing = 0
NeatPlatesHubDefaults.WidgetResourceMode = 1
NeatPlatesHubMenus.WidgetResourceModes = {
				{ text = L["Enemy Units"],  } ,
				{ text = L["Friendly Units"],  } ,
				{ text = L["All Units"],  } ,
				{ text = L["None"],  } ,
			}
NeatPlatesHubDefaults.WidgetResourceStyle = "Neat"
NeatPlatesHubMenus.WidgetResourceStyles = {
				{ text = L["Blizzlike"], value = "Blizzard" } ,
				{ text = L["NeatPlates"], value = "Neat" } ,
			}

NeatPlatesHubDefaults.BorderPandemic = 1
NeatPlatesHubDefaults.BorderBuffPurgeable = 1
NeatPlatesHubDefaults.BorderBuffEnrage = 1
NeatPlatesHubMenus.BorderTypes = {
				{ text = L["Border Color"],  },
				{ text = L["Glow"],  },
			}

NeatPlatesHubDefaults.HighlightTargetMode = 1
NeatPlatesHubDefaults.HighlightFocustMode = 1
NeatPlatesHubDefaults.HighlightMouseoverMode = 1
NeatPlatesHubMenus.HighlightTypes = {
	{ text = L["None"],  },
	{ text = L["Healthbar"],  },
	{ text = L["Theme Default"],  },
	{ text = L["Arrow(Top)"],  },
	{ text = L["Arrow(Sides)"],  },
	{ text = L["Arrow(Right)"],  },
	{ text = L["Arrow(Left)"],  },
	{ text = L["Neon Arrow(Sides)"],  },
}

NeatPlatesHubDefaults.WidgetAuraSort = 1
NeatPlatesHubMenus.AuraSortModes = {
				{ text = L["Default"],  },
				{ text = L["By Duration"],  },
			}

NeatPlatesHubDefaults.WidgetAuraAlignment = 1
NeatPlatesHubMenus.AuraAlignmentModes = {
				{ text = L["Left"],  },
				{ text = L["Center"],  },
				{ text = L["Right"],  },
			}

NeatPlatesHubDefaults.BuffSeparationMode = 1
NeatPlatesHubMenus.BuffSeparationModes = {
				{ text = L["Separate Row"],  },
				{ text = L["Space Between"],  },
				{ text = L["No Space"],  },
			}

NeatPlatesHubMenus.StyleOptions = {
	{
		text = L["customtext"],
		value = "customtext",
		tooltip = L["customtext_tooltip"],
	},
	--{
	--	text = L["targetindicator"],
	--	value = "targetindicator",
	--	tooltip = L["targetindicator_tooltip"],
	--},
	{
		text = L["eliteicon"],
			value = "eliteicon",
		tooltip = L["eliteicon_tooltip"],
	},
	{
		text = L["castnostop"],
		value = "castnostop",
		tooltip = L["castnostop_tooltip"],
	},
	{
		text = L["spellicon"],
		value = "spellicon",
		tooltip = L["spellicon_tooltip"],
	},
	{
		text = L["extratext"],
		value = "extratext",
		tooltip = L["extratext_tooltip"],
	},
	{
		text = L["extrabar"],
		value = "extrabar",
		tooltip = L["extrabar_tooltip"],
	},
	--{
	--	text = L["hitbox"],
	--	value = "hitbox",
	--	tooltip = L["hitbox_tooltip"],
	--},
	{
		text = L["focus"],
		value = "focus",
		tooltip = L["focus_tooltip"],
		options = {
			enable = false
		},
	},
	{
		text = L["target"],
		value = "target",
		tooltip = L["target_tooltip"],
		options = {
			enable = false
		},
	},
	{
		text = L["mouseover"],
		value = "mouseover",
		tooltip = L["mouseover_tooltip"],
		options = {
			enable = false
		},
	},
	{
		text = L["level"],
		value = "level",
		tooltip = L["level_tooltip"],
	},
	{
		text = L["name"],
		value = "name",
		tooltip = L["name_tooltip"],
	},
	{
		text = L["subtext"],
		value = "subtext",
		tooltip = L["subtext_tooltip"],
	},
	{
		text = L["extraborder"],
		value = "extraborder",
		tooltip = L["extraborder_tooltip"],
	},
	{
		text = L["castbar"],
		value = "castbar",
		tooltip = L["castbar_tooltip"],
	},
	{
		text = L["spelltext"],
		value = "spelltext",
		tooltip = L["spelltext_tooltip"],
	},
	{
		text = L["spelltarget"],
		value = "spelltarget",
		tooltip = L["spelltarget_tooltip"],
	},
	{
		text = L["healthbar"],
		value = "healthbar",
		tooltip = L["healthbar_tooltip"],
	},
	{
		text = L["powerbar"],
		value = "powerbar",
		tooltip = L["powerbar_tooltip"],
	},
	--{
	--	text = L["targetindicator_arrowleft"],
	--	value = "targetindicator_arrowleft",
	--	tooltip = L["targetindicator_arrowleft_tooltip"],
	--},
	--{
	--	text = L["targetindicator_arrowright"],
	--	value = "targetindicator_arrowright",
	--	tooltip = L["targetindicator_arrowright_tooltip"],
	--},
	{
		text = L["threatborder"],
		value = "threatborder",
		tooltip = L["threatborder_tooltip"],
	},
	{
		text = L["healthborder"],
		value = "healthborder",
		tooltip = L["healthborder_tooltip"],
	},
	{
		text = L["skullicon"],
		value = "skullicon",
		tooltip = L["skullicon_tooltip"],
	},
	{
		text = L["durationtext"],
		value = "durationtext",
		tooltip = L["durationtext_tooltip"],
	},
	{
		text = L["castborder"],
		value = "castborder",
		tooltip = L["castborder_tooltip"],
	},
	--{
	--	text = L["targetindicator_arrowsides"],
	--	value = "targetindicator_arrowsides",
	--	tooltip = L["targetindicator_arrowsides_tooltip"],
	--},
	{
		text = L["highlight"],
		value = "highlight",
		tooltip = L["highlight_tooltip"],
	},
	--{
	--	text = L["targetindicator_arrowtop"],
	--	value = "targetindicator_arrowtop",
	--	tooltip = L["targetindicator_arrowtop_tooltip"],
	--},
	--{
	--	text = L["rangeindicator"],
	--	value = "rangeindicator",
	--	tooltip = L["rangeindicator_tooltip"],
	--},
	{
		text = L["raidicon"],
		value = "raidicon",
		tooltip = L["raidicon_tooltip"],
	},
}

NeatPlatesHubMenus.WidgetOptions = {
	{
		text = L["ComboWidget"],
		value = "ComboWidget",
		tooltip = L["ComboWidget_tooltip"],
	},
	{
		text = L["ResourceWidget"],
		value = "ResourceWidget",
		tooltip = L["ResourceWidget_tooltip"],
	},
	{
		text = L["AbsorbWidget"],
		value = "AbsorbWidget",
		tooltip = L["AbsorbWidget_tooltip"],
	},
	{
		text = L["QuestWidgetNameOnly"],
		value = "QuestWidgetNameOnly",
		tooltip = L["QuestWidgetNameOnly_tooltip"],
	},
	{
		text = L["ThreatPercentageWidget"],
		value = "ThreatPercentageWidget",
		tooltip = L["ThreatPercentageWidget_tooltip"],
	},
	{
		text = L["DebuffWidget"],
		value = "DebuffWidget",
		tooltip = L["DebuffWidget_tooltip"],
	},
	{
		text = L["ThreatLineWidget"],
		value = "ThreatLineWidget",
		tooltip = L["ThreatLineWidget_tooltip"],
	},
	{
		text = L["TotemIcon"],
		value = "TotemIcon",
		tooltip = L["TotemIcon_tooltip"],
	},
	--{
	--	text = L["ThreatWheelWidget"],
	--	value = "ThreatWheelWidget",
	--	tooltip = L["ThreatWheelWidget_tooltip"],
	--},
	{
		text = L["QuestWidget"],
		value = "QuestWidget",
		tooltip = L["QuestWidget_tooltip"],
	},
	{
		text = L["RangeWidget"],
		value = "RangeWidget",
		tooltip = L["RangeWidget_tooltip"],
	},
	{
		text = L["ClassIcon"],
		value = "ClassIcon",
		tooltip = L["ClassIcon_tooltip"],
	},
	{
		text = L["ArenaIcon"],
		value = "ArenaWidget",
		tooltip = L["ArenaIcon_tooltip"],
	},
}


------------------------------------------------------------------------------
-- Aura Widget
------------------------------------------------------------------------------
NeatPlatesHubPrefixList = {
	-- ALL
	["ALL"] = 1,
	["All"] = 1,
	["all"] = 1,

	-- MY
	["MY"] = 2,
	["My"] = 2,
	["my"] = 2,

	-- OTHER
	["OTHER"] = 3,
	["Other"] = 3,
	["other"] = 3,

	-- CC
	["CC"] = 4,
	["cc"] = 4,
	["Cc"] = 4,

	-- NOT
	["NOT"] = 5,
	["Not"] = 5,
	["not"] = 5,
}

--[[
* Debuffs are color coded, with poison debuffs having a green border,
magic debuffs a blue border, physical debuffs a red border, diseases a
brown border, and curses a purple border

Information from Widget:
aura.spellid, aura.name, aura.expiration, aura.stacks,
aura.caster, aura.duration, aura.texture,
aura.type, aura.reaction
--]]

local AURA_TYPE_DEBUFF = 6
local AURA_TYPE_BUFF = 1

local AURA_TARGET_HOSTILE = 1
local AURA_TARGET_FRIENDLY = 2

local AURA_TYPE = { "Buff", "Curse", "Disease", "Magic", "Poison", "Debuff", }
-- local AURA_TYPE_COLORS = { nil, {1,0,1}, {.5, .2, 0}, {0,.4,1}, {0,1,0}, nil, }
local AURA_TYPE_COLORS = {
	["Buff"] = nil,
	["Curse"] = {1,0,1},
	["Disease"] = {.5, .2, 0},
	["Magic"] = {0,.4,1},
	["Poison"] = {0,1,0},
	["Debuff"] = nil,
}




local function GetPrefixPriority(aura, auraType)
	-- In WoW 12.0+, aura data (name, spellId) is secret during combat, making custom
	-- aura list matching non-functional. Skip all custom list processing.
	if isWoW12Plus then return nil, nil end

	if not auraType then auraType = "normal" end

	local filter, priority

	local spellid = aura.spellid
	local name = aura.name
	-- Check if values are secret (12.0.0+ combat protection)
	local nameIsSecret = issecretvalue and issecretvalue(name)
	local spellIdIsSecret = issecretvalue and issecretvalue(spellid)

	-- Convert spellid to string only if not secret
	if not spellIdIsSecret and spellid then
		spellid = tostring(spellid)
	end

	local function lookup(auraTable)
		for i,a in pairs(auraTable) do
			-- Skip comparisons if values are secret
			local nameMatch = not nameIsSecret and a.name == name
			local spellMatch = not spellIdIsSecret and a.name == spellid
			local typeMatch = auraType == a.type

			if (nameMatch or spellMatch) and typeMatch then
				return a.filter, i
			end
		end
	end

	filter, priority = lookup(LocalVars.WidgetAdditionalAuras)
	if not filter and not priority then
		filter, priority = lookup(NeatPlatesSettings.GlobalAdditonalAuras)
	end
	return filter, priority -- prefix/filter, priority
end

local function GetAuraColor(aura)
	local auraType = aura.type
	-- Check if auraType is a secret value (12.0.0+ combat protection)
	if not auraType or (issecretvalue and issecretvalue(auraType)) then
		return nil
	end
	local color = AURA_TYPE_COLORS[auraType]
	if color then return unpack(color) end
end

-- Helper function to safely check if caster matches a value (handles 12.0.0+ secret values)
-- For pre-12.0: Returns true/false based on caster comparison
-- For 12.0+: This function is typically bypassed by isWoW12Plus checks,
--            but if called, it will return false when values are secret
local function CasterMatches(caster, value, isFromPlayer)
	-- In 12.0.0+, caster (sourceUnit) can be a secret value
	-- Use the isFromPlayer flag when available (set from isFromPlayerOrPlayerPet aura field)
	if value == "player" or value == "pet" then
		-- For player/pet checks, prefer the isFromPlayer flag
		if isFromPlayer ~= nil then
			-- Check if isFromPlayer itself is a secret value
			if issecretvalue and issecretvalue(isFromPlayer) then
				return false
			end
			return isFromPlayer
		end
	end
	-- Fallback to direct comparison if caster is not secret
	if issecretvalue and issecretvalue(caster) then
		return false
	end
	return caster == value
end

local DebuffPrefixModes = {
	["all"] = function(aura)
		return true
	end,
	["my"] = function(aura)
		-- For WoW 12.0+, ownership checks are bypassed at a higher level (SmartFilterMode)
		-- This function is only called for pre-12.0 or for custom aura lists
		local playerMatch = CasterMatches(aura.caster, "player", aura.isFromPlayer)
		local petMatch = CasterMatches(aura.caster, "pet", aura.isFromPlayer)
		return playerMatch or petMatch
	end,
	-- ["other"] = function(aura)
	-- 	--print(aura.caster, aura.name)
	-- 	if (aura.caster ~= "player" or aura.caster ~= "pet") then return true end
	-- end,
	-- ["cc"] = function(aura)
	-- 	--return true, .5, .4, 0
	-- 	return true, 1, 1, 0
	-- end,
	["not"] = function(aura)
		return false
	end
}

local function SmartFilterMode(aura)
	local ShowThisAura = false
	local AuraPriority = 20

	-- FILTER MODE HANDLING:
	-- Filter mode 1 = "Show None" - don't show anything from this filter path
	-- Filter mode 2 = "Show Mine" - API uses |PLAYER filter, so all returned auras are player's
	-- Filter mode 3 = "Show All" - show everything
	--
	-- For "Show Mine" (mode 2): The |PLAYER filter is applied at the API level in AuraWidget.lua,
	-- meaning all auras returned are already filtered to player auras. We treat them as "show all"
	-- since everything we received is already "mine". This works in both pre-12.0 and 12.0+.

	-- Show buffs: mode 2 (Show Mine - API pre-filtered) or mode 3 (Show All)
	if aura.effect == "HELPFUL" and (LocalVars.WidgetBuffFilter == 2 or LocalVars.WidgetBuffFilter == 3) then
		ShowThisAura = true
	end

	-- Show debuffs: mode 2 (Show Mine - API pre-filtered) or mode 3 (Show All)
	if aura.effect == "HARMFUL" and (LocalVars.WidgetDebuffFilter == 2 or LocalVars.WidgetDebuffFilter == 3) then
		ShowThisAura = true
	end

	-- Evaluate for further filtering via custom aura lists
	local prefix, priority = GetPrefixPriority(aura)

	-- If the aura is mentioned in the list, evaluate the instruction...
	if prefix then
		local show

		-- For WoW 12.0+ with "my" prefix in custom lists, treat as "all" since ownership is unknowable
		if isWoW12Plus and prefix == "my" then
			show = true
		else
			show = DebuffPrefixModes[prefix](aura)
		end

		if show then
			return true, (priority or 20)
		else
			return false
		end
	-- When no prefix is mentioned, return the aura filter result
	else
		return ShowThisAura, 20
	end

end




local DispelTypeHandlers = {
	-- Curse
	["Curse"] = function()
		return LocalVars.WidgetAuraTrackCurse
	end,
	-- Disease
	["Disease"] = function()
		return LocalVars.WidgetAuraTrackDisease
	end,
	-- Magic
	["Magic"] = function()
		return LocalVars.WidgetAuraTrackMagic
	end,
	-- Poison
	["Poison"] = function()
		return LocalVars.WidgetAuraTrackPoison
	end,
	}

local function TrackDispelType(dispelType)
	-- Check if dispelType is a secret value (12.0.0+ combat protection)
	if not dispelType or (issecretvalue and issecretvalue(dispelType)) then
		return nil
	end
	local handlerfunction = DispelTypeHandlers[dispelType]
	if handlerfunction then return handlerfunction() end
end

local function DebuffFilter(aura)
	-- Get aura type safely (may be secret value in 12.0.0+)
	local auraType = aura.type
	local auraTypeIsSecret = issecretvalue and issecretvalue(auraType)

	-- Purgeable Buff
	if LocalVars.WidgetBuffPurgeable and aura.effect == "HELPFUL" and (not auraTypeIsSecret and auraType == "Magic") and aura.reaction == 1 then
		local color = LocalVars.ColorBuffPurgeable
		return true, 10, color.r, color.g, color.b, color.a
	end
	-- Sootheable Enrage Buff
	if LocalVars.WidgetBuffEnrage and aura.effect == "HELPFUL" and (not auraTypeIsSecret and auraType == "") and aura.reaction == 1 then
		local color = LocalVars.ColorBuffEnrage
		return true, 10, color.r, color.g, color.b, color.a
	end
	-- Dispellable Debuff
	if (LocalVars.WidgetAuraTrackDispelFriendly and aura.reaction == AURA_TARGET_FRIENDLY) then
		if (aura.effect == "HARMFUL" and TrackDispelType(auraType)) then
			local r, g, b = GetAuraColor(aura)
			return true, 10, r, g, b, a
		end
	end

	return SmartFilterMode(aura)
end

local function EmphasizedFilter(aura)
	local prefix, priority = GetPrefixPriority(aura, "emphasized")
	local r, g, b = GetAuraColor(aura)

	if prefix and priority then
		local show
		-- For WoW 12.0+ with "my" prefix, treat as "all" since ownership is unknowable
		if isWoW12Plus and prefix == "my" then
			show = true
		else
			show = DebuffPrefixModes[prefix](aura)
		end
		if show then
			return true, priority, r, g, b
		end
	elseif priority then
		return true, priority, r, g, b
	end

	return false -- Return false if aura isn't one to be emphasized
end

local function AuraSortFunction(a,b)
	if LocalVars.WidgetAuraSort == 2 then
		return a.expiration < b.expiration	-- By Duration
	else
		return a.priority < b.priority -- Default
	end
end

---------------------------------------------------------------------------------------------------------
-- Widget Initializers
---------------------------------------------------------------------------------------------------------

local function SetWidgetPoints(widget, rel, config)
	if widget.SetCustomPoint then
		widget:SetCustomPoint(config.anchor or "TOP", rel, config.anchorRel or config.anchor or "TOP", config.x or 0, config.y or 0)
	else
		widget:ClearAllPoints()
		widget:SetPoint(config.anchor or "TOP", rel, config.anchorRel or config.anchor or "TOP", config.x or 0, config.y or 0)
	end
end

local function InitWidget( widgetName, extended, config, createFunction, enabled)
	local widget = extended.widgets[widgetName]

	if enabled and createFunction and config then
		--[[ Data from Themes passed to parent ]] --
		extended.widgetParent.config = config
		if config.h ~= nil then extended.widgetParent._height = config.h end
		if config.h ~= nil then extended.widgetParent._width = config.w end
		if config.o ~= nil then extended.widgetParent._orientation = config.o else extended.widgetParent._orientation = "HORIZONTAL" end

		if widget then
			if widget.UpdateConfig then widget:UpdateConfig() end
		else
			widget = createFunction(extended.widgetParent)
			extended.widgets[widgetName] = widget
		end

		SetWidgetPoints(widget, extended, config)

	elseif widget and widget.Hide then
		widget:Hide()
	end

end



------------------------------------------------------------------------------
-- Widget Activation
------------------------------------------------------------------------------
local function OnInitializeWidgets(extended, configTable)

	local EnableClassWidget = (LocalVars.ClassEnemyIcon or LocalVars.ClassPartyIcon)
	local EnableTotemWidget = LocalVars.WidgetTotemIcon
	local EnableComboWidget = LocalVars.WidgetComboPoints ~= 4 and LocalVars.WidgetResourceMode == 4
	local EnableResourceWidget = LocalVars.WidgetResourceMode ~= 4
	local EnableThreatWidget = LocalVars.WidgetThreatIndicator
	local EnableAuraWidget = LocalVars.WidgetDebuff
	local EnableArenaWidget = LocalVars.WidgetArenaIcon
	local EnableAbsorbWidget = LocalVars.WidgetAbsorbIndicator
	local EnableQuestWidget = LocalVars.WidgetQuestIcon
	local EnableThreatPercentageWidget = LocalVars.WidgetThreatPercentage
	local EnableRangeWidget = LocalVars.WidgetRangeIndicator

	if NEATPLATES_IS_CLASSIC then
		EnableAbsorbWidget = false
	end

	InitWidget( "ClassWidgetHub", extended, configTable.ClassIcon, CreateClassWidget, EnableClassWidget)
	InitWidget( "TotemWidgetHub", extended, configTable.TotemIcon, CreateTotemIconWidget, EnableTotemWidget)
	InitWidget( "ComboWidgetHub", extended, configTable.ComboWidget, CreateComboPointWidget, EnableComboWidget)
	InitWidget( "ResourceWidgetHub", extended, configTable.ResourceWidget, CreateResourceWidget, EnableResourceWidget)
	InitWidget( "ThreatWidgetHub", extended, configTable.ThreatLineWidget, CreateThreatLineWidget, EnableThreatWidget)
	InitWidget( "AbsorbWidgetHub", extended, configTable.AbsorbWidget, CreateAbsorbWidget, EnableAbsorbWidget)
	InitWidget( "QuestWidgetHub", extended, configTable.QuestWidget, CreateQuestWidget, EnableQuestWidget)
	InitWidget( "ThreatPercentageWidgetHub", extended, configTable.ThreatPercentageWidget, CreateThreatPercentageWidget, EnableThreatPercentageWidget)
	InitWidget( "RangeWidgetHub", extended, configTable.RangeWidget, CreateRangeWidget, EnableRangeWidget)
	InitWidget( "ArenaWidgetHub", extended, configTable.ArenaWidget, CreateArenaWidget, EnableArenaWidget)

	InitWidget( "AuraWidgetHub", extended, configTable.DebuffWidget, CreateAuraWidget, EnableAuraWidget)

end

local function OnContextUpdateDelegate(extended, unit)
	local widgets = extended.widgets
	local EnableComboWidget =  widgets.ComboWidgetHub and (LocalVars.WidgetComboPoints == 3 or (LocalVars.WidgetComboPoints == 1 and unit.reaction ~= "FRIENDLY") or (LocalVars.WidgetComboPoints == 2 and unit.reaction == "FRIENDLY"))
	local EnableResourceWidget =  widgets.ResourceWidgetHub and (LocalVars.WidgetResourceMode == 3 or (LocalVars.WidgetResourceMode == 1 and unit.reaction ~= "FRIENDLY") or (LocalVars.WidgetResourceMode == 2 and unit.reaction == "FRIENDLY"))

	if EnableResourceWidget then
		widgets.ResourceWidgetHub:UpdateContext(unit)
	elseif widgets.ResourceWidgetHub then
		widgets.ResourceWidgetHub:Hide()
	end

	if EnableComboWidget and LocalVars.WidgetResourceMode == 4 then
		widgets.ComboWidgetHub:UpdateContext(unit)
	elseif widgets.ComboWidgetHub then
		widgets.ComboWidgetHub:Hide()
	end

	if LocalVars.WidgetThreatIndicator and widgets.ThreatWidgetHub then
		widgets.ThreatWidgetHub:UpdateContext(unit) end		-- Tug-O-Threat

	if LocalVars.WidgetDebuff and widgets.AuraWidgetHub then
		-- Reposition if combo widget is enabled for some themes
		local config = copytable(extended.widgetParent.config)
		if (EnableComboWidget or EnableResourceWidget) and unit.isTarget then
			config.anchor = config.anchor2 or config.anchor
			config.anchorRel = config.anchorRel2 or config.anchorRel
			config.x = config.x2 or config.x
			config.y = config.y2 or config.y
		end

		SetWidgetPoints(widgets.AuraWidgetHub, extended, config)
		widgets.AuraWidgetHub:UpdateContext(unit)
	end


	if LocalVars.WidgetDebuff and widgets.AuraWidget then
		widgets.AuraWidget:UpdateContext(unit) end

	if LocalVars.WidgetAbsorbIndicator and widgets.AbsorbWidgetHub then
		widgets.AbsorbWidgetHub:UpdateContext(unit) end

	if LocalVars.WidgetThreatPercentage and widgets.ThreatPercentageWidgetHub then
		widgets.ThreatPercentageWidgetHub:UpdateContext(unit) end

	if LocalVars.WidgetRangeIndicator and widgets.RangeWidgetHub then
		widgets.RangeWidgetHub:UpdateContext(unit) end

	if LocalVars.WidgetArenaIcon and widgets.ArenaWidgetHub then
		widgets.ArenaWidgetHub:UpdateContext(unit) end

	if LocalVars.WidgetQuestIcon and widgets.QuestWidgetHub then
		widgets.QuestWidgetHub:UpdateContext(unit, extended) end
end

local function OnUpdateDelegate(extended, unit)
	local widgets = extended.widgets

	if widgets.ClassWidgetHub and ( (LocalVars.ClassEnemyIcon and unit.reaction ~= "FRIENDLY") or (LocalVars.ClassPartyIcon and unit.reaction == "FRIENDLY")) then
		widgets.ClassWidgetHub:Update(unit, LocalVars.ClassPartyIcon)
	end

	if widgets.QuestWidgetHub and LocalVars.WidgetQuestIcon then
		widgets.QuestWidgetHub:Update(unit)
	end

	if LocalVars.WidgetTotemIcon and widgets.TotemWidgetHub then
		widgets.TotemWidgetHub:Update(unit)
	end
end


------------------------------------------------------------------------------
-- Local Variable
------------------------------------------------------------------------------

local function OnVariableChange(vars)

	LocalVars = vars

	if LocalVars.WidgetDebuff then
		NeatPlatesWidgets:EnableAuraWatcher()
		NeatPlatesWidgets.SetAuraFilter(DebuffFilter)
		NeatPlatesWidgets.SetAuraSortMode(AuraSortFunction)
		NeatPlatesWidgets.SetAuraOptions(LocalVars)
		NeatPlatesWidgets.SetEmphasizedAuraFilter(EmphasizedFilter, LocalVars.EmphasizedUnique)
		-- Pass filter modes to AuraWidget for server-side |PLAYER filtering
		-- This enables "Show Mine" to work in WoW 12.0+ by filtering at the API level
		if NeatPlatesWidgets.SetAuraFilterModes then
			NeatPlatesWidgets.SetAuraFilterModes(LocalVars.WidgetDebuffFilter, LocalVars.WidgetBuffFilter)
		end
	else NeatPlatesWidgets:DisableAuraWatcher() end

	if LocalVars.WidgetAbsorbIndicator then
		NeatPlatesWidgets.SetAbsorbType(LocalVars.WidgetAbsorbMode, LocalVars.WidgetAbsorbUnits)
	end

	if LocalVars.WidgetComboPoints then
		NeatPlatesWidgets.SetComboPointsWidgetOptions(LocalVars)
	end

	if LocalVars.WidgetResourceMode then
		NeatPlatesWidgets.SetResourceWidgetOptions(LocalVars)
	end

	--if (LocalVars.ClassEnemyIcon or LocalVars.ClassPartyIcon) then
	--	NeatPlatesWidgets.SetClassWidgetOptions(LocalVars)
	--end

	if LocalVars.WidgetPandemic then
		NeatPlatesWidgets.SetPandemic(LocalVars.WidgetPandemic, LocalVars.ColorPandemic)
	end

	if LocalVars.WidgetPandemic or LocalVars.WidgetBuffPurgeable or LocalVars.WidgetBuffEnrage then
		NeatPlatesWidgets.SetBorderTypes(LocalVars.BorderPandemic, LocalVars.BorderBuffPurgeable, LocalVars.BorderBuffEnrage)
	end

	if LocalVars.WidgetRangeIndicator then
		NeatPlatesWidgets.SetRangeWidgetOptions(LocalVars)
	end
end
HubData.RegisterCallback(OnVariableChange)


------------------------------------------------------------------------------
-- Add References
------------------------------------------------------------------------------

NeatPlatesHubFunctions.OnUpdate = OnUpdateDelegate
NeatPlatesHubFunctions.OnInitializeWidgets = OnInitializeWidgets
NeatPlatesHubFunctions.OnContextUpdate = OnContextUpdateDelegate
NeatPlatesHubFunctions._WidgetDebuffFilter = DebuffFilter
