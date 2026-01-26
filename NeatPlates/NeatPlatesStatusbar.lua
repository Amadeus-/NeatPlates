
-- obj:SetTexCoord(crop.left, crop.right, crop.top, crop.bottom)

-- SetGradientAlpha compatibility (deprecated in 10.0.0, use SetGradient with ColorMixin)
local function SetGradientCompat(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    if texture.SetGradient then
        -- New API (10.0.0+) - use CreateColor for color objects
        local minColor = CreateColor(r1, g1, b1, a1)
        local maxColor = CreateColor(r2, g2, b2, a2)
        texture:SetGradient(orientation, minColor, maxColor)
    elseif texture.SetGradientAlpha then
        -- Legacy API
        texture:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    end
end

-- 12.0.0+ Secret Value Handling
-- In 12.0.0+, UnitHealth/UnitHealthMax return "secret values" during combat that can't be used
-- in arithmetic operations. The native WoW StatusBar widget has SetValue() and SetMinMaxValues()
-- methods that ACCEPT SECRET VALUES directly (SecretArguments = "AllowedWhenTainted").
--
-- For 12.0.0+, we use a HYBRID approach:
-- 1. Native StatusBar (INVISIBLE) - Used only for VALUE handling, accepts secret values
-- 2. Visual TEXTURE layer (VISIBLE) - Used for APPEARANCE, preserves rounded corners via SetTexCoord
--
-- This approach solves two problems:
-- - Secret values: The native StatusBar accepts them without arithmetic
-- - Visual appearance: The custom texture uses SetTexCoord to create the rounded look
--
-- The key insight is that NeatPlates typically uses SetValueFromUnit() or SetValuePercent()
-- which calculate percentages BEFORE passing to the bar, so we can track the percentage
-- and use it to update both the native bar (for correctness) and the visual bar (for appearance).
local isMidnight = select(4, GetBuildInfo()) >= 120000

----------------------------------------------------------------------
-- Legacy Implementation (pre-12.0.0)
-- Uses custom texture manipulation with SetTexCoord for bar fill
----------------------------------------------------------------------

local fraction, range, value, barsize, final

local function UpdateBar_Legacy(self)
	range = self.MaxVal - self.MinVal
	value = self.Value - self.MinVal

	barsize = self.Dim or 1

	local neutralSize = (self.NeutralMax - self.NeutralMin) / self.MaxVal
	local neutralLeft = barsize * ((self.NeutralMin) / self.MaxVal)
	local neutralRight = barsize * ((self.MaxVal -  self.NeutralMax) / self.MaxVal)

	if range > 0 and value > 0 and range >= value then
		fraction = value / range
	else fraction = .01 end
	if self.Orientation == "VERTICAL" then
		self.Bar:SetHeight(barsize * fraction)
		final = self.Bottom - ((self.Bottom - self.Top) * fraction)		-- bottom = 1, top = 0
		self.Bar:SetTexCoord(self.Left, self.Right, final, self.Bottom)
		--self.Bar:SetTexCoord(0, 1, 1-fraction, 1)

		-- Set neutral zone size
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("BOTTOMLEFT", 0, neutralLeft)
		self.Neutral:SetPoint("TOPRIGHT", 0, -neutralRight)
	else
		self.Bar:SetWidth(barsize * fraction)
		self.Neutral:SetWidth(barsize * neutralSize)
		final = ((self.Right - self.Left) * fraction) + self.Left
		self.Bar:SetTexCoord(self.Left, final, self.Top, self.Bottom)
		self.Neutral:SetTexCoord(self.Left, self.Right, self.Top, self.Bottom)

		-- Set neutral zone size
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("TOPLEFT", neutralLeft, 0)
		self.Neutral:SetPoint("BOTTOMRIGHT", -neutralRight, 0)
	end
end

local function UpdateSize_Legacy(self)
	if self.Orientation == "VERTICAL" then self.Dim = self:GetHeight()
	else self.Dim = self:GetWidth() end
	UpdateBar_Legacy(self)
end

local function SetValue_Legacy(self, value)
	if value >= self.MinVal and value <= self.MaxVal then self.Value = value end;
	UpdateBar_Legacy(self)
end

local function SetValuePercent_Legacy(self, pct)
	if not pct or pct < 0 then pct = 0 end
	if pct > 1 then pct = 1 end

	local bsize = self.Dim or 1

	if self.Orientation == "VERTICAL" then
		self.Bar:SetHeight(bsize * pct)
		local fin = self.Bottom - ((self.Bottom - self.Top) * pct)
		self.Bar:SetTexCoord(self.Left, self.Right, fin, self.Bottom)
	else
		self.Bar:SetWidth(bsize * pct)
		local fin = ((self.Right - self.Left) * pct) + self.Left
		self.Bar:SetTexCoord(self.Left, fin, self.Top, self.Bottom)
	end
end

-- SetValueFromUnit_Legacy: Not applicable for pre-12.0.0 (no secret values)
-- Provided for API compatibility - returns false to indicate caller should use regular SetValue
local function SetValueFromUnit_Legacy(self, unitid)
	return false
end

-- SetPowerFromUnit_Legacy: Not applicable for pre-12.0.0 (no secret values)
-- Provided for API compatibility - returns false to indicate caller should use regular SetValue
local function SetPowerFromUnit_Legacy(self, unitid, powerType)
	return false
end

local function SetStatusBarTexture_Legacy(self, texture)
	self.Bar:SetTexture(texture)
	self.Neutral:SetTexture(texture)
end

local function SetStatusBarColor_Legacy(self, r, g, b, a)
	a = a or 1
	self.Bar:SetVertexColor(r,g,b,a)
	self.Neutral:SetVertexColor(0,0,1,a/2)
end

local function SetStatusBarGradient_Legacy(self, r1, g1, b1, a1, r2, g2, b2, a2)
	SetGradientCompat(self.Bar, self.Orientation, r1, g1, b1, a1, r2, g2, b2, a2)
end

local function SetAllColors_Legacy(self, rBar, gBar, bBar, aBar, rBackdrop, gBackdrop, bBackdrop, aBackdrop)
	self.Bar:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
	self.Bar.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}
	self.Neutral:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
	self.Neutral.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}
	self.Backdrop:SetVertexColor(rBackdrop or 1, gBackdrop or 1, bBackdrop or 1, aBackdrop or 1)
	self.Backdrop.color = {r = rBackdrop or 1, g = gBackdrop or 1, b = bBackdrop or 1, a = aBackdrop or 1}
end

local function SetOrientation_Legacy(self, orientation)
	if orientation == "VERTICAL" then
		self.Orientation = orientation
		self.Bar:ClearAllPoints()
		self.Bar:SetPoint("BOTTOMLEFT")
		self.Bar:SetPoint("BOTTOMRIGHT")
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("BOTTOMLEFT")
		self.Neutral:SetPoint("BOTTOMRIGHT")
	else
		self.Orientation = "HORIZONTAL"
		self.Bar:ClearAllPoints()
		self.Bar:SetPoint("TOPLEFT")
		self.Bar:SetPoint("BOTTOMLEFT")
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("TOPLEFT")
		self.Neutral:SetPoint("BOTTOMLEFT")
	end
	UpdateSize_Legacy(self)
end

local function GetMinMaxValues_Legacy(self)
	return self.MinVal, self.MaxVal
end

local function SetMinMaxValues_Legacy(self, minval, maxval)
	if not (minval or maxval) then return end

	if maxval > minval then
		self.MinVal = minval
		self.MaxVal = maxval
	else
		self.MinVal = 0
		self.MaxVal = 1
	end

	if self.Value > self.MaxVal then self.Value = self.MaxVal
	elseif self.Value < self.MinVal then self.Value = self.MinVal end

	UpdateBar_Legacy(self)
end

local function SetNeutralZone_Legacy(self, minval, maxval, center, barmax)
	if not (minval or maxval) then return end

	if maxval > minval then
		self.NeutralMin = minval
		self.NeutralMax = maxval
	else
		self.NeutralMin = 0
		self.NeutralMax = 0
	end

	self.NeutralCenter = center

	UpdateBar_Legacy(self)
end

local function SetTexCoord_Legacy(self, left,right,top,bottom)		-- 0. 1. 0. 1
	self.Left, self.Right, self.Top, self.Bottom = left or 0, right or 1, top or 0, bottom or 1
	UpdateBar_Legacy(self)
end

local function SetBackdropTexCoord_Legacy(self, left,right,top,bottom)		-- 0. 1. 0. 1
	self.Backdrop:SetTexCoord(left or 0, right or 1,top or 0, bottom or 1)
end

local function SetBackdropTexture_Legacy(self, texture)		-- 0. 1. 0. 1
	self.Backdrop:SetTexture(texture)
end


----------------------------------------------------------------------
-- 12.0.0+ Hybrid StatusBar Implementation
-- Uses native StatusBar for VALUE handling (accepts secret values)
-- Uses separate visual TEXTURE layer for APPEARANCE (preserves rounded look via SetTexCoord)
----------------------------------------------------------------------

-- Helper to update the visual bar based on stored percentage
local function UpdateVisualBar_Hybrid(self)
	local pct = self.LastPercent or 0
	local barsize = self.Dim or 1

	-- Calculate neutral zone positioning
	local neutralSize = (self.NeutralMax - self.NeutralMin) / self.MaxVal
	local neutralLeft = barsize * ((self.NeutralMin) / self.MaxVal)
	local neutralRight = barsize * ((self.MaxVal - self.NeutralMax) / self.MaxVal)

	if self.Orientation == "VERTICAL" then
		self.VisualBar:SetHeight(barsize * pct)
		local fin = self.Bottom - ((self.Bottom - self.Top) * pct)
		self.VisualBar:SetTexCoord(self.Left, self.Right, fin, self.Bottom)

		-- Set neutral zone size
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("BOTTOMLEFT", 0, neutralLeft)
		self.Neutral:SetPoint("TOPRIGHT", 0, -neutralRight)
	else
		self.VisualBar:SetWidth(barsize * pct)
		self.Neutral:SetWidth(barsize * neutralSize)
		local fin = ((self.Right - self.Left) * pct) + self.Left
		self.VisualBar:SetTexCoord(self.Left, fin, self.Top, self.Bottom)
		self.Neutral:SetTexCoord(self.Left, self.Right, self.Top, self.Bottom)

		-- Set neutral zone size
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("TOPLEFT", neutralLeft, 0)
		self.Neutral:SetPoint("BOTTOMRIGHT", -neutralRight, 0)
	end
end

-- Helper to update dimension on size change
local function UpdateSize_Hybrid(self)
	if self.Orientation == "VERTICAL" then
		self.Dim = self:GetHeight()
	else
		self.Dim = self:GetWidth()
	end
	UpdateVisualBar_Hybrid(self)
end

-- SetValue for hybrid StatusBar wrapper
-- The native StatusBar.SetValue accepts secret values directly
-- We also update the visual bar if we can determine the percentage
local function SetValue_Hybrid(self, val)
	-- Native StatusBar handles secret values natively (but is invisible)
	self.NativeBar:SetValue(val)

	-- Update visual bar and store non-secret values
	if not issecretvalue or not issecretvalue(val) then
		self.Value = val
		-- Calculate percentage from stored min/max
		local range = self.MaxVal - self.MinVal
		if range > 0 then
			self.LastPercent = (val - self.MinVal) / range
			if self.LastPercent < 0.01 then self.LastPercent = 0.01 end
			if self.LastPercent > 1 then self.LastPercent = 1 end
		else
			self.LastPercent = 0.01
		end
		UpdateVisualBar_Hybrid(self)
	end
	-- If it's a secret value, we can't update the visual bar directly here
	-- The caller should use SetValueFromUnit or SetValuePercent instead
end

-- SetValuePercent for hybrid StatusBar - sets bar to a specific fraction (0-1)
-- This is the preferred method for 12.0.0+ as it works with secret values
local function SetValuePercent_Hybrid(self, pct)
	if not pct or pct < 0 then pct = 0 end
	if pct > 1 then pct = 1 end

	-- Update native bar (set to 0-1 range for simplicity)
	self.NativeBar:SetMinMaxValues(0, 1)
	self.NativeBar:SetValue(pct)

	-- Store values
	self.MinVal = 0
	self.MaxVal = 1
	self.Value = pct
	self.LastPercent = pct
	if self.LastPercent < 0.01 then self.LastPercent = 0.01 end

	-- Update visual bar with the percentage
	UpdateVisualBar_Hybrid(self)
end

-- SetValueFromUnit for hybrid StatusBar
-- Uses UnitHealthPercent with CurveConstants.ScaleTo100 to get a usable percentage
local function SetValueFromUnit_Hybrid(self, unitid)
	if not unitid or not UnitHealthPercent then
		return false
	end

	if not CurveConstants or not CurveConstants.ScaleTo100 then
		return false
	end

	local percent = UnitHealthPercent(unitid, true, CurveConstants.ScaleTo100)

	if percent and type(percent) == "number" then
		local frac = percent / 100
		SetValuePercent_Hybrid(self, frac)
		return true
	end

	return false
end

-- SetPowerFromUnit for hybrid StatusBar
local function SetPowerFromUnit_Hybrid(self, unitid, powerType)
	if not unitid or not UnitPowerPercent then
		return false
	end

	if not CurveConstants or not CurveConstants.ScaleTo100 then
		return false
	end

	local percent = UnitPowerPercent(unitid, powerType, false, CurveConstants.ScaleTo100)

	if percent and type(percent) == "number" then
		local frac = percent / 100
		SetValuePercent_Hybrid(self, frac)
		return true
	end

	return false
end

-- SetMinMaxValues for hybrid StatusBar wrapper
-- The native StatusBar.SetMinMaxValues accepts secret values directly
local function SetMinMaxValues_Hybrid(self, minval, maxval)
	if not (minval or maxval) then return end

	-- Native StatusBar handles secret values natively
	self.NativeBar:SetMinMaxValues(minval, maxval)

	-- Store non-secret values for GetMinMaxValues compatibility and visual updates
	if not issecretvalue or (not issecretvalue(minval) and not issecretvalue(maxval)) then
		if maxval > minval then
			self.MinVal = minval
			self.MaxVal = maxval
		else
			self.MinVal = 0
			self.MaxVal = 1
		end

		-- Clamp Value within new range
		if self.Value > self.MaxVal then self.Value = self.MaxVal
		elseif self.Value < self.MinVal then self.Value = self.MinVal end

		-- Recalculate percentage
		local range = self.MaxVal - self.MinVal
		if range > 0 then
			self.LastPercent = (self.Value - self.MinVal) / range
			if self.LastPercent < 0.01 then self.LastPercent = 0.01 end
		end

		UpdateVisualBar_Hybrid(self)
	end
end

local function GetMinMaxValues_Hybrid(self)
	return self.MinVal, self.MaxVal
end

-- SetStatusBarTexture for hybrid StatusBar
-- Sets texture on BOTH the native bar (unused but kept for consistency) and the visual bar
local function SetStatusBarTexture_Hybrid(self, texture)
	-- Set on native bar (invisible, but keeps API consistent)
	self.NativeBar:SetStatusBarTexture(texture)
	-- Set on visual bar (this is what the user actually sees)
	self.VisualBar:SetTexture(texture)
	-- Also set neutral zone texture
	self.Neutral:SetTexture(texture)
	-- Store reference for compatibility (point to visual bar)
	self.Bar = self.VisualBar
end

-- SetStatusBarColor for hybrid StatusBar
local function SetStatusBarColor_Hybrid(self, r, g, b, a)
	a = a or 1
	-- Set on native bar (invisible)
	self.NativeBar:SetStatusBarColor(r, g, b, a)
	-- Set on visual bar (what user sees)
	self.VisualBar:SetVertexColor(r, g, b, a)
	-- Set neutral zone
	self.Neutral:SetVertexColor(0, 0, 1, a/2)
end

-- SetStatusBarGradient for hybrid StatusBar
local function SetStatusBarGradient_Hybrid(self, r1, g1, b1, a1, r2, g2, b2, a2)
	-- Apply gradient to visual bar
	SetGradientCompat(self.VisualBar, self.Orientation, r1, g1, b1, a1, r2, g2, b2, a2)
end

-- SetAllColors for hybrid StatusBar
local function SetAllColors_Hybrid(self, rBar, gBar, bBar, aBar, rBackdrop, gBackdrop, bBackdrop, aBackdrop)
	-- Set bar color on both native and visual
	self.NativeBar:SetStatusBarColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
	self.VisualBar:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
	self.VisualBar.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}

	-- Set neutral zone color
	self.Neutral:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
	self.Neutral.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}

	-- Set backdrop color
	self.Backdrop:SetVertexColor(rBackdrop or 1, gBackdrop or 1, bBackdrop or 1, aBackdrop or 1)
	self.Backdrop.color = {r = rBackdrop or 1, g = gBackdrop or 1, b = bBackdrop or 1, a = aBackdrop or 1}
end

-- SetOrientation for hybrid StatusBar
local function SetOrientation_Hybrid(self, orientation)
	if orientation == "VERTICAL" then
		self.Orientation = orientation
		self.NativeBar:SetOrientation("VERTICAL")
		-- Update visual bar anchoring
		self.VisualBar:ClearAllPoints()
		self.VisualBar:SetPoint("BOTTOMLEFT")
		self.VisualBar:SetPoint("BOTTOMRIGHT")
		-- Update neutral zone anchoring
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("BOTTOMLEFT")
		self.Neutral:SetPoint("BOTTOMRIGHT")
	else
		self.Orientation = "HORIZONTAL"
		self.NativeBar:SetOrientation("HORIZONTAL")
		-- Update visual bar anchoring
		self.VisualBar:ClearAllPoints()
		self.VisualBar:SetPoint("TOPLEFT")
		self.VisualBar:SetPoint("BOTTOMLEFT")
		-- Update neutral zone anchoring
		self.Neutral:ClearAllPoints()
		self.Neutral:SetPoint("TOPLEFT")
		self.Neutral:SetPoint("BOTTOMLEFT")
	end
	UpdateSize_Hybrid(self)
end

-- SetNeutralZone for hybrid StatusBar
local function SetNeutralZone_Hybrid(self, minval, maxval, center, barmax)
	if not (minval or maxval) then return end

	if maxval > minval then
		self.NeutralMin = minval
		self.NeutralMax = maxval
	else
		self.NeutralMin = 0
		self.NeutralMax = 0
	end

	self.NeutralCenter = center

	UpdateVisualBar_Hybrid(self)
end

-- SetTexCoord for hybrid StatusBar
-- This now works properly because we control the visual texture directly
local function SetTexCoord_Hybrid(self, left, right, top, bottom)
	self.Left, self.Right, self.Top, self.Bottom = left or 0, right or 1, top or 0, bottom or 1
	UpdateVisualBar_Hybrid(self)
end

-- SetBackdropTexCoord for hybrid StatusBar
local function SetBackdropTexCoord_Hybrid(self, left, right, top, bottom)
	self.Backdrop:SetTexCoord(left or 0, right or 1, top or 0, bottom or 1)
end

-- SetBackdropTexture for hybrid StatusBar
local function SetBackdropTexture_Hybrid(self, texture)
	self.Backdrop:SetTexture(texture)
end


----------------------------------------------------------------------
-- Factory Function
----------------------------------------------------------------------

function CreateNeatPlatesStatusbar(parent)
	if isMidnight then
		-- 12.0.0+: Hybrid approach
		-- - Native StatusBar for VALUE handling (accepts secret values, but is INVISIBLE)
		-- - Visual TEXTURE layer for APPEARANCE (preserves rounded look via SetTexCoord)
		local frame = CreateFrame("Frame", nil, parent, NeatPlatesBackdrop)
		frame:SetHeight(1)
		frame:SetWidth(1)

		-- State variables (same as legacy)
		frame.Value, frame.MinVal, frame.MaxVal, frame.Orientation = 1, 0, 1, "HORIZONTAL"
		frame.NeutralMin, frame.NeutralMax, frame.NeutralCenter = 0, 0, 0.5
		frame.Left, frame.Right, frame.Top, frame.Bottom = 0, 1, 0, 1
		frame.LastPercent = 1  -- Track last known percentage for visual updates

		-- Create backdrop texture behind the bar (same as legacy)
		frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
		frame.Backdrop:SetAllPoints(frame)

		-- Create the VISUAL bar texture (this is what the user sees)
		-- Uses BORDER layer like legacy implementation
		frame.VisualBar = frame:CreateTexture(nil, "BORDER")
		frame.VisualBar:SetPoint("TOPLEFT")
		frame.VisualBar:SetPoint("BOTTOMLEFT")

		-- Create neutral zone overlay texture (same as legacy)
		frame.Neutral = frame:CreateTexture(nil, "OVERLAY")
		frame.Neutral:Hide()

		-- Create native StatusBar for VALUE STORAGE ONLY (invisible)
		-- This accepts secret values but we don't use it for display
		local nativeBar = CreateFrame("StatusBar", nil, frame)
		nativeBar:SetAllPoints(frame)
		nativeBar:SetMinMaxValues(0, 1)
		nativeBar:SetValue(1)
		-- Make the native bar's texture invisible - we only use it for value storage
		nativeBar:SetStatusBarTexture("")
		nativeBar:SetAlpha(0)  -- Extra safety: make entire StatusBar invisible
		frame.NativeBar = nativeBar

		-- Store reference to visual bar as .Bar for compatibility
		frame.Bar = frame.VisualBar

		-- Assign hybrid methods
		frame.SetValue = SetValue_Hybrid
		frame.SetValuePercent = SetValuePercent_Hybrid
		frame.SetValueFromUnit = SetValueFromUnit_Hybrid
		frame.SetPowerFromUnit = SetPowerFromUnit_Hybrid
		frame.SetNeutralZone = SetNeutralZone_Hybrid
		frame.SetMinMaxValues = SetMinMaxValues_Hybrid
		frame.GetMinMaxValues = GetMinMaxValues_Hybrid
		frame.SetOrientation = SetOrientation_Hybrid
		frame.SetStatusBarColor = SetStatusBarColor_Hybrid
		frame.SetStatusBarGradient = SetStatusBarGradient_Hybrid
		frame.SetAllColors = SetAllColors_Hybrid
		frame.SetStatusBarTexture = SetStatusBarTexture_Hybrid
		frame.SetTexCoord = SetTexCoord_Hybrid
		frame.SetBackdropTexCoord = SetBackdropTexCoord_Hybrid
		frame.SetBackdropTexture = SetBackdropTexture_Hybrid

		-- OnSizeChanged handler (like legacy)
		frame:SetScript("OnSizeChanged", UpdateSize_Hybrid)
		UpdateSize_Hybrid(frame)

		return frame
	else
		-- Pre-12.0.0: Use legacy custom texture implementation
		local frame = CreateFrame("Frame", nil, parent, NeatPlatesBackdrop)
		frame:SetHeight(1)
		frame:SetWidth(1)
		frame.Value, frame.MinVal, frame.MaxVal, frame.Orientation = 1, 0, 1, "HORIZONTAL"
		frame.NeutralMin, frame.NeutralMax, frame.NeutralCenter = 0, 0, 0.5
		frame.Left, frame.Right, frame.Top, frame.Bottom = 0, 1, 0, 1
		frame.Bar = frame:CreateTexture(nil, "BORDER")
		frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
		frame.Backdrop:SetAllPoints(frame)
		frame.Neutral = frame:CreateTexture(nil, "OVERLAY")
		frame.Neutral:Hide()

		frame.SetValue = SetValue_Legacy
		frame.SetValuePercent = SetValuePercent_Legacy
		frame.SetValueFromUnit = SetValueFromUnit_Legacy
		frame.SetPowerFromUnit = SetPowerFromUnit_Legacy
		frame.SetNeutralZone = SetNeutralZone_Legacy
		frame.SetMinMaxValues = SetMinMaxValues_Legacy
		frame.GetMinMaxValues = GetMinMaxValues_Legacy
		frame.SetOrientation = SetOrientation_Legacy
		frame.SetStatusBarColor = SetStatusBarColor_Legacy
		frame.SetStatusBarGradient = SetStatusBarGradient_Legacy
		frame.SetAllColors = SetAllColors_Legacy
		frame.SetStatusBarTexture = SetStatusBarTexture_Legacy
		frame.SetTexCoord = SetTexCoord_Legacy
		frame.SetBackdropTexCoord = SetBackdropTexCoord_Legacy
		frame.SetBackdropTexture = SetBackdropTexture_Legacy

		frame:SetScript("OnSizeChanged", UpdateSize_Legacy)
		UpdateSize_Legacy(frame)
		return frame
	end
end
