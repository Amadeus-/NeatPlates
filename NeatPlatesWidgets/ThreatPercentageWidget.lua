---------------
-- Threat Percentage Widget
---------------

local font = "FONTS\\arialn.ttf"
local GetRelativeThreat = NeatPlatesUtility.GetRelativeThreat

-- WoW 12.0.0+: UnitDetailedThreatSituation returns nil/secret from addon code.
-- This widget requires numeric threat percentages and cannot function.
local isMidnight = select(4, GetBuildInfo()) >= 120000

-- Debug helpers
local function safeStr(val)
	if val == nil then return "nil" end
	if issecretvalue and issecretvalue(val) then return "<SECRET>" end
	local ok, str = pcall(tostring, val)
	return ok and str or "<UNKNOWN>"
end

local function ThreatDbg(msg)
	if not NEATPLATES_DEBUG_THREAT then return end
	if NeatPlatesUtility and NeatPlatesUtility.Debug and NeatPlatesUtility.Debug.Log then
		NeatPlatesUtility.Debug.Log("Threat", msg)
	end
end

local function UpdateThreatPercentageWidget(self, unit, showFriendly)
	if isMidnight then self:Hide(); return end

	ThreatDbg("UpdateThreatPercentageWidget called | unit=" .. safeStr(unit) .. " | isMidnight=" .. safeStr(isMidnight))

	local threat, targetOf = GetRelativeThreat(unit)

	ThreatDbg("  GetRelativeThreat => threat=" .. safeStr(threat) .. " targetOf=" .. safeStr(targetOf))

	local threatPercent

	if threat and threat > 0 then
		threatPercent = math.floor(threat)..'%'
		self.Text:SetText(threatPercent)
		self:Show()
		ThreatDbg("  SHOWING widget | text=" .. threatPercent)
	else
		self.Text:SetText("")
		self:Hide()
		ThreatDbg("  HIDING widget | threat=" .. safeStr(threat))
	end

end

local function UpdateWidget(frame)
	local unitid = frame.unitid

	ThreatDbg("UpdateWidget (OnEvent) | unitid=" .. safeStr(unitid))

	UpdateThreatPercentageWidget(frame, unitid)
end

local function UpdateWidgetContext(frame, unit)
	if isMidnight then frame:Hide(); return end

	local unitid = unit.unitid

	ThreatDbg("UpdateWidgetContext | unitid=" .. safeStr(unitid) .. " | reaction=" .. safeStr(unit.reaction) .. " | InCombat=" .. safeStr(InCombatLockdown()) .. " | InParty=" .. safeStr(UnitInParty("player")) .. " | HasPet=" .. safeStr(HasPetUI()))

	if unit.reaction == "FRIENDLY" then
		ThreatDbg("  EARLY HIDE: FRIENDLY")
		frame:Hide()
		return
	end
	if not InCombatLockdown() then
		ThreatDbg("  EARLY HIDE: NOT in combat")
		frame:Hide()
		return
	end
	if not (UnitInParty("player") or HasPetUI()) then
		ThreatDbg("  EARLY HIDE: NOT in party and no pet")
		frame:Hide()
		return
	end

	frame.unitid = unitid

	-- Make it self-aware
	frame:UnregisterAllEvents()
	frame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
	frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	frame:RegisterUnitEvent("UNIT_HEALTH", unitid)
	frame:SetScript("OnEvent", UpdateWidget);

	ThreatDbg("  Events registered, calling UpdateThreatPercentageWidget")

	UpdateThreatPercentageWidget(frame, unitid)
end

local function CreateThreatPercentageWidget(parent)
	ThreatDbg("CreateThreatPercentageWidget called | parent=" .. safeStr(parent) .. " parentShown=" .. safeStr(parent and parent:IsShown()))

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(32); frame:SetHeight(12)

	frame.Text = frame:CreateFontString(nil, "OVERLAY")
	frame.Text:SetFont(font, 10, "OUTLINE")
	frame.Text:SetAllPoints(frame)
	frame.Text:SetJustifyH("CENTER")

	frame:Hide()
	frame.Update = UpdateWidget
	frame.UpdateContext = UpdateWidgetContext

	ThreatDbg("  Widget frame created successfully")

	return frame
end

NeatPlatesWidgets.CreateThreatPercentageWidget = CreateThreatPercentageWidget
