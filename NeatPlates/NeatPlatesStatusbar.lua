
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
-- For 12.0.0+, we use a native StatusBar as the PRIMARY visible bar element.
-- This completely bypasses the secret value issue because the StatusBar natively handles
-- secret values for rendering without us ever needing to read them back.
--
-- TEXTURE COLOR HANDLING:
-- We use GetStatusBarTexture():SetVertexColor() instead of SetStatusBarColor() for coloring.
-- SetStatusBarColor() REPLACES the texture's color entirely, losing any gradients baked into
-- the texture. SetVertexColor() MULTIPLIES with the texture's pixel data, preserving grey
-- gradients in theme textures (like NeatPlates_Grey's Statusbar.tga) that give the muted look.
local isMidnight = select(4, GetBuildInfo()) >= 120000
local issecretvalue = issecretvalue or function() return false end

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
-- 12.0.0+ Native StatusBar Implementation
-- Uses native StatusBar as the primary visual element to handle secret values
----------------------------------------------------------------------

-- SetValue for native StatusBar wrapper
-- The native StatusBar.SetValue accepts secret values directly
local function SetValue_Native(self, val)
	-- Native StatusBar handles secret values natively
	self.NativeBar:SetValue(val)
	-- Store non-secret values for GetMinMaxValues compatibility
	if not issecretvalue or not issecretvalue(val) then
		self.Value = val
	end
end

-- SetValuePercent for native StatusBar - sets bar to a specific fraction (0-1)
local function SetValuePercent_Native(self, pct)
	if not pct or pct < 0 then pct = 0 end
	if pct > 1 then pct = 1 end
	-- Set min/max to 0,1 and value to the percentage
	self.NativeBar:SetMinMaxValues(0, 1)
	self.NativeBar:SetValue(pct)
	self.MinVal = 0
	self.MaxVal = 1
	self.Value = pct
end

-- SetValueFromUnit for native StatusBar
-- Passes UnitHealth/UnitHealthMax directly to the native StatusBar which handles secret values.
local function SetValueFromUnit_Native(self, unitid)
	if not unitid then
		return false
	end

	local health = UnitHealth(unitid)
	local maxHealth = UnitHealthMax(unitid)
	if health and maxHealth then
		self.NativeBar:SetMinMaxValues(0, maxHealth)
		self.NativeBar:SetValue(health)
		-- Store non-secret values for GetMinMaxValues compatibility
		if not issecretvalue or not issecretvalue(maxHealth) then
			if maxHealth > 0 then
				self.MinVal = 0
				self.MaxVal = maxHealth
			end
		end
		if not issecretvalue or not issecretvalue(health) then
			self.Value = health
		end
		return true
	end

	return false
end

-- SetPowerFromUnit for native StatusBar
-- Passes UnitPower/UnitPowerMax directly to the native StatusBar which handles secret values.
local function SetPowerFromUnit_Native(self, unitid, powerType)
	if not unitid then
		return false
	end

	local power = UnitPower(unitid, powerType)
	local maxPower = UnitPowerMax(unitid, powerType)
	if power and maxPower then
		self.NativeBar:SetMinMaxValues(0, maxPower)
		self.NativeBar:SetValue(power)
		-- Store non-secret values for GetMinMaxValues compatibility
		if not issecretvalue or not issecretvalue(maxPower) then
			if maxPower > 0 then
				self.MinVal = 0
				self.MaxVal = maxPower
			end
		end
		if not issecretvalue or not issecretvalue(power) then
			self.Value = power
		end
		return true
	end

	return false
end

-- SetMinMaxValues for native StatusBar wrapper
-- The native StatusBar.SetMinMaxValues accepts secret values directly
local function SetMinMaxValues_Native(self, minval, maxval)
	if not (minval or maxval) then return end
	-- Native StatusBar handles secret values natively
	self.NativeBar:SetMinMaxValues(minval, maxval)
	-- Store non-secret values for GetMinMaxValues compatibility
	if not issecretvalue or (not issecretvalue(minval) and not issecretvalue(maxval)) then
		if maxval > minval then
			self.MinVal = minval
			self.MaxVal = maxval
		else
			self.MinVal = 0
			self.MaxVal = 1
		end
	end
end

local function GetMinMaxValues_Native(self)
	return self.MinVal, self.MaxVal
end

-- SetStatusBarTexture for native StatusBar
local function SetStatusBarTexture_Native(self, texture)
	self.NativeBar:SetStatusBarTexture(texture)
	-- CRITICAL: After setting texture, ensure the StatusBar's own color is white!
	-- The StatusBar color and texture vertex color multiply together.
	-- We keep the StatusBar color at white so only the vertex color (which we control) affects rendering.
	-- This preserves grey gradients baked into theme textures.
	self.NativeBar:SetStatusBarColor(1, 1, 1, 1)

	-- Store reference to the texture for color operations
	self.Bar = self.NativeBar:GetStatusBarTexture()
	-- Also set neutral zone texture if it exists
	if self.Neutral then
		self.Neutral:SetTexture(texture)
	end
end

-- SetStatusBarColor for native StatusBar
-- IMPORTANT: We use GetStatusBarTexture():SetVertexColor() instead of SetStatusBarColor()
-- because SetStatusBarColor() REPLACES the texture's color entirely, while SetVertexColor()
-- MULTIPLIES with the texture's pixel data. This preserves grey gradients baked into
-- theme textures (like NeatPlates_Grey's Statusbar.tga).
local function SetStatusBarColor_Native(self, r, g, b, a)
	a = a or 1
	local barTex = self.NativeBar:GetStatusBarTexture()
	if barTex then
		barTex:SetVertexColor(r, g, b, a)
	end
	if self.Neutral then
		self.Neutral:SetVertexColor(0, 0, 1, a/2)
	end
end

-- SetStatusBarColorFromBoolean for native StatusBar (12.0.0+)
-- Uses SetVertexColorFromBoolean to resolve a secret boolean into one of two colors
-- at the C++ rendering level. This avoids intermediate secret number values that
-- can cause blank/colorless bars when passed through SetVertexColor.
-- secretBoolean: a potentially-secret boolean value
-- colorIfTrue: ColorMixin for when secretBoolean is true
-- colorIfFalse: ColorMixin for when secretBoolean is false
local function SetStatusBarColorFromBoolean_Native(self, secretBoolean, colorIfTrue, colorIfFalse)
	local barTex = self.NativeBar:GetStatusBarTexture()
	if barTex and barTex.SetVertexColorFromBoolean then
		barTex:SetVertexColorFromBoolean(secretBoolean, colorIfTrue, colorIfFalse)
	end
	-- Neutral zone doesn't need secret handling
end

-- No-op for legacy bars (secret values don't exist pre-12.0.0)
local function SetStatusBarColorFromBoolean_Legacy(self, secretBoolean, colorIfTrue, colorIfFalse)
	-- Not applicable for pre-12.0.0
end

-- SetStatusBarGradient for native StatusBar
-- Note: Native StatusBar doesn't support gradients directly, so we apply to the texture
local function SetStatusBarGradient_Native(self, r1, g1, b1, a1, r2, g2, b2, a2)
	local barTex = self.NativeBar:GetStatusBarTexture()
	if barTex then
		SetGradientCompat(barTex, self.Orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	end
end

-- SetAllColors for native StatusBar
-- IMPORTANT: We use GetStatusBarTexture():SetVertexColor() instead of SetStatusBarColor()
-- because SetStatusBarColor() REPLACES the texture's color entirely, while SetVertexColor()
-- MULTIPLIES with the texture's pixel data. This preserves grey gradients baked into
-- theme textures (like NeatPlates_Grey's Statusbar.tga).
local function SetAllColors_Native(self, rBar, gBar, bBar, aBar, rBackdrop, gBackdrop, bBackdrop, aBackdrop)
	-- Set bar color via texture's vertex color (preserves texture gradients)
	local barTex = self.NativeBar:GetStatusBarTexture()
	if barTex then
		barTex:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
		barTex.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}
	end

	-- Set neutral zone color
	if self.Neutral then
		self.Neutral:SetVertexColor(rBar or 1, gBar or 1, bBar or 1, aBar or 1)
		self.Neutral.color = {r = rBar or 1, g = gBar or 1, b = bBar or 1, a = aBar or 1}
	end

	-- Set backdrop color
	if self.Backdrop then
		self.Backdrop:SetVertexColor(rBackdrop or 1, gBackdrop or 1, bBackdrop or 1, aBackdrop or 1)
		self.Backdrop.color = {r = rBackdrop or 1, g = gBackdrop or 1, b = bBackdrop or 1, a = aBackdrop or 1}
	end
end

-- SetOrientation for native StatusBar
local function SetOrientation_Native(self, orientation)
	if orientation == "VERTICAL" then
		self.Orientation = orientation
		self.NativeBar:SetOrientation("VERTICAL")
		if self.Neutral then
			self.Neutral:ClearAllPoints()
			self.Neutral:SetPoint("BOTTOMLEFT")
			self.Neutral:SetPoint("BOTTOMRIGHT")
		end
	else
		self.Orientation = "HORIZONTAL"
		self.NativeBar:SetOrientation("HORIZONTAL")
		if self.Neutral then
			self.Neutral:ClearAllPoints()
			self.Neutral:SetPoint("TOPLEFT")
			self.Neutral:SetPoint("BOTTOMLEFT")
		end
	end
end

-- SetNeutralZone for native StatusBar
-- Note: Native StatusBar doesn't have a neutral zone concept, so we use an overlay texture
local function SetNeutralZone_Native(self, minval, maxval, center, barmax)
	if not (minval or maxval) then return end

	if maxval > minval then
		self.NeutralMin = minval
		self.NeutralMax = maxval
	else
		self.NeutralMin = 0
		self.NeutralMax = 0
	end

	self.NeutralCenter = center

	-- Update neutral zone overlay position
	if self.Neutral and barmax and barmax > 0 then
		local barsize = self:GetWidth()
		if self.Orientation == "VERTICAL" then
			barsize = self:GetHeight()
		end

		local neutralSize = (self.NeutralMax - self.NeutralMin) / barmax
		local neutralLeft = barsize * ((self.NeutralMin) / barmax)
		local neutralRight = barsize * ((barmax - self.NeutralMax) / barmax)

		if self.Orientation == "VERTICAL" then
			self.Neutral:ClearAllPoints()
			self.Neutral:SetPoint("BOTTOMLEFT", 0, neutralLeft)
			self.Neutral:SetPoint("TOPRIGHT", 0, -neutralRight)
		else
			self.Neutral:ClearAllPoints()
			self.Neutral:SetPoint("TOPLEFT", neutralLeft, 0)
			self.Neutral:SetPoint("BOTTOMRIGHT", -neutralRight, 0)
		end
	end
end

-- SetTexCoord for native StatusBar
-- Note: Native StatusBar doesn't support custom tex coords on the bar texture in the same way
-- We store the values for compatibility but they won't affect the native bar rendering
local function SetTexCoord_Native(self, left, right, top, bottom)
	self.Left, self.Right, self.Top, self.Bottom = left or 0, right or 1, top or 0, bottom or 1
	-- Can't apply tex coords to native StatusBar fill - it manages its own texture
end

-- SetBackdropTexCoord for native StatusBar
local function SetBackdropTexCoord_Native(self, left, right, top, bottom)
	if self.Backdrop then
		self.Backdrop:SetTexCoord(left or 0, right or 1, top or 0, bottom or 1)
	end
end

-- SetBackdropTexture for native StatusBar
local function SetBackdropTexture_Native(self, texture)
	if self.Backdrop then
		self.Backdrop:SetTexture(texture)
	end
end

-- SetDesaturated for native StatusBar
-- Allows themes to apply a desaturation effect to the bar for a muted/grey look
local function SetDesaturated_Native(self, desaturate)
	local barTex = self.NativeBar:GetStatusBarTexture()
	if barTex and barTex.SetDesaturated then
		barTex:SetDesaturated(desaturate)
	end
end

-- SetDesaturated for legacy StatusBar
local function SetDesaturated_Legacy(self, desaturate)
	if self.Bar and self.Bar.SetDesaturated then
		self.Bar:SetDesaturated(desaturate)
	end
end


----------------------------------------------------------------------
-- Factory Function
----------------------------------------------------------------------

function CreateNeatPlatesStatusbar(parent)
	if isMidnight then
		-- 12.0.0+: Use native StatusBar as primary visual element
		-- This handles secret values natively without any workarounds
		local frame = CreateFrame("Frame", nil, parent, NeatPlatesBackdrop)
		frame:SetHeight(1)
		frame:SetWidth(1)

		-- State variables (for compatibility)
		frame.Value, frame.MinVal, frame.MaxVal, frame.Orientation = 1, 0, 1, "HORIZONTAL"
		frame.NeutralMin, frame.NeutralMax, frame.NeutralCenter = 0, 0, 0.5
		frame.Left, frame.Right, frame.Top, frame.Bottom = 0, 1, 0, 1

		-- Create backdrop texture behind the bar
		frame.Backdrop = frame:CreateTexture(nil, "BACKGROUND")
		frame.Backdrop:SetAllPoints(frame)

		-- Create neutral zone overlay texture
		frame.Neutral = frame:CreateTexture(nil, "OVERLAY")
		frame.Neutral:Hide()

		-- Create native StatusBar as the primary bar element
		local nativeBar = CreateFrame("StatusBar", nil, frame)
		nativeBar:SetAllPoints(frame)
		nativeBar:EnableMouse(false)  -- Let clicks pass through to Blizzard's HitTestFrame for targeting
		nativeBar:SetMinMaxValues(0, 1)
		nativeBar:SetValue(1)
		nativeBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		-- CRITICAL: Set the StatusBar's own color to white!
		-- The StatusBar widget has its own color (SetStatusBarColor) that multiplies with
		-- the texture's vertex color. If we don't set it to white, it will tint the bar.
		-- We use SetVertexColor on the texture for actual coloring to preserve texture gradients.
		nativeBar:SetStatusBarColor(1, 1, 1, 1)
		frame.NativeBar = nativeBar

		-- Store reference to status bar texture as .Bar for compatibility
		frame.Bar = nativeBar:GetStatusBarTexture()

		-- Assign native StatusBar methods
		frame.SetValue = SetValue_Native
		frame.SetValuePercent = SetValuePercent_Native
		frame.SetValueFromUnit = SetValueFromUnit_Native
		frame.SetPowerFromUnit = SetPowerFromUnit_Native
		frame.SetNeutralZone = SetNeutralZone_Native
		frame.SetMinMaxValues = SetMinMaxValues_Native
		frame.GetMinMaxValues = GetMinMaxValues_Native
		frame.SetOrientation = SetOrientation_Native
		frame.SetStatusBarColor = SetStatusBarColor_Native
		frame.SetStatusBarColorFromBoolean = SetStatusBarColorFromBoolean_Native
		frame.SetStatusBarGradient = SetStatusBarGradient_Native
		frame.SetAllColors = SetAllColors_Native
		frame.SetStatusBarTexture = SetStatusBarTexture_Native
		frame.SetTexCoord = SetTexCoord_Native
		frame.SetBackdropTexCoord = SetBackdropTexCoord_Native
		frame.SetBackdropTexture = SetBackdropTexture_Native
		frame.SetDesaturated = SetDesaturated_Native

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
		frame.SetStatusBarColorFromBoolean = SetStatusBarColorFromBoolean_Legacy
		frame.SetStatusBarGradient = SetStatusBarGradient_Legacy
		frame.SetAllColors = SetAllColors_Legacy
		frame.SetStatusBarTexture = SetStatusBarTexture_Legacy
		frame.SetTexCoord = SetTexCoord_Legacy
		frame.SetBackdropTexCoord = SetBackdropTexCoord_Legacy
		frame.SetBackdropTexture = SetBackdropTexture_Legacy
		frame.SetDesaturated = SetDesaturated_Legacy

		frame:SetScript("OnSizeChanged", UpdateSize_Legacy)
		UpdateSize_Legacy(frame)
		return frame
	end
end
