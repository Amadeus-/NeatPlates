---------------
-- Threat Percentage Widget
---------------

local font = "FONTS\\arialn.ttf"
local GetRelativeThreat = NeatPlatesUtility.GetRelativeThreat

-- Debug helpers for threat percentage widget
local function safeStr(val)
	if val == nil then return "nil" end
	if issecretvalue and issecretvalue(val) then return "<SECRET>" end
	local ok, str = pcall(tostring, val)
	return ok and str or "<UNKNOWN>"
end

local function ThreatDbg(msg)
	if NEATPLATES_DEBUG_THREAT and NeatPlatesUtility and NeatPlatesUtility.Debug then
		NeatPlatesUtility.Debug.Log("Threat", msg)
	end
end

local function UpdateThreatPercentageWidget(self, unit, showFriendly)
	ThreatDbg("UpdateThreatPercentageWidget called | unitid=" .. safeStr(unit))
	local threat, targetOf = GetRelativeThreat(unit)
	ThreatDbg("GetRelativeThreat => threat=" .. safeStr(threat) .. " targetOf=" .. safeStr(targetOf))
	local threatPercent

	if threat and threat > 0 then
		threatPercent = math.floor(threat)..'%'
		self.Text:SetText(threatPercent)
		self:Show()
		ThreatDbg("SHOWING widget | threatPercent=" .. safeStr(threatPercent))
	else
		self.Text:SetText("")
		self:Hide()
		ThreatDbg("HIDING widget | threat is nil or <= 0")
	end

end

local function UpdateWidget(frame)
	local unitid = frame.unitid
	ThreatDbg("UpdateWidget (OnEvent) | unitid=" .. safeStr(unitid))

	UpdateThreatPercentageWidget(frame, unitid)
end

local function UpdateWidgetContext(frame, unit)
	local unitid = unit.unitid

	ThreatDbg("UpdateWidgetContext | unitid=" .. safeStr(unitid) .. " reaction=" .. safeStr(unit.reaction) .. " inCombat=" .. safeStr(InCombatLockdown()) .. " inParty=" .. safeStr(UnitInParty("player")) .. " hasPet=" .. safeStr(HasPetUI()))

	if unit.reaction == "FRIENDLY" then
		ThreatDbg("EARLY HIDE: FRIENDLY reaction")
		frame:Hide()
		return
	end
	if not InCombatLockdown() then
		ThreatDbg("EARLY HIDE: NOT in combat")
		frame:Hide()
		return
	end
	if not (UnitInParty("player") or HasPetUI()) then
		ThreatDbg("EARLY HIDE: NOT in party and no pet")
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

	UpdateThreatPercentageWidget(frame, unitid)
end

local function CreateThreatPercentageWidget(parent)
	ThreatDbg("CreateThreatPercentageWidget called")
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(32); frame:SetHeight(12)

	-- frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	-- frame.Icon:SetAllPoints(frame)

	frame.Text = frame:CreateFontString(nil, "OVERLAY")
	frame.Text:SetFont(font, 10, "OUTLINE")
	frame.Text:SetAllPoints(frame)
	frame.Text:SetJustifyH("CENTER")

	frame:Hide()
	frame.Update = UpdateWidget
	frame.UpdateContext = UpdateWidgetContext
	ThreatDbg("CreateThreatPercentageWidget => frame created")
	return frame
end

NeatPlatesWidgets.CreateThreatPercentageWidget = CreateThreatPercentageWidget
