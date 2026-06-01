if !CLIENT then return end

EmissiveSys = EmissiveSys or {}

local math_Clamp = math.Clamp
local math_floor = math.floor
local math_max = math.max
local tonumber = tonumber
local tostring = tostring
local isstring = isstring
local istable = istable
local Vector = Vector
local Material = Material
local CreateMaterial = CreateMaterial
local IsValid = IsValid
local LocalPlayer = LocalPlayer
local GetViewEntity = GetViewEntity
local CurTime = CurTime
local ScrW = ScrW
local ScrH = ScrH
local pairs = pairs
local ipairs = ipairs
local timer_Simple = timer.Simple
local table_concat = table.concat
local table_Empty = table.Empty
local table_IsEmpty = table.IsEmpty
local string_Trim = string.Trim
local string_TrimLeft = string.TrimLeft
local string_lower = string.lower
local render_GetScreenEffectTexture = render.GetScreenEffectTexture
local render_GetRenderTarget = render.GetRenderTarget
local render_CopyRenderTargetToTexture = render.CopyRenderTargetToTexture
local render_Clear = render.Clear
local render_SuppressEngineLighting = render.SuppressEngineLighting
local render_MaterialOverrideByIndex = render.MaterialOverrideByIndex
local render_MaterialOverride = render.MaterialOverride
local render_SetRenderTarget = render.SetRenderTarget
local render_SetMaterial = render.SetMaterial
local render_DrawScreenQuad = render.DrawScreenQuad
local render_DrawScreenQuadEx = render.DrawScreenQuadEx
local render_PushRenderTarget = render.PushRenderTarget
local render_BlurRenderTarget = render.BlurRenderTarget
local render_PopRenderTarget = render.PopRenderTarget
local render_DepthRange = render.DepthRange
local cam_Start3D = cam.Start3D
local cam_End3D = cam.End3D
local cam_IgnoreZ = cam.IgnoreZ
local hook_Add = hook.Add
local ents_GetAll = ents.GetAll

EmissiveSys.Enabled = true
EmissiveSys.EnableViewModel = false
EmissiveSys.ViewModelDepth = 0.06
EmissiveSys.ResolutionScale = 1.00
EmissiveSys.PassTotal = 4
EmissiveSys.PassInterval = 2
EmissiveSys.PassIntensity = 1.0
EmissiveSys.BlurInitial = 2.0
EmissiveSys.BlurIncrement = 0.5
EmissiveSys.BlurX = 1.0
EmissiveSys.BlurY = 1.0

EmissiveSys.Defs = EmissiveSys.Defs or {}
EmissiveSys.Queue = EmissiveSys.Queue or {}
EmissiveSys.EntityCache = EmissiveSys.EntityCache or {}
EmissiveSys.MatCache = EmissiveSys.MatCache or {}
EmissiveSys.Rev = EmissiveSys.Rev or 0
local matBlackStr = "vgui/black"
local matBlack = Material(matBlackStr)
local matScreen = Material("pp/bleach_em")
local matCopy = Material("pp/copy")
local rtStore = render_GetScreenEffectTexture(0)
local rtBlur  = render_GetScreenEffectTexture(1)

local function clamp01(x)
	return math_Clamp(tonumber(x) or 0, 0, 1)
end

local function vecFromColorTbl(t)
	if istable(t) then
		return Vector(clamp01(t[1] or t.r or 1), clamp01(t[2] or t.g or 1), clamp01(t[3] or t.b or 1))
	end
	return Vector(1, 1, 1)
end

local function normalizeMatName(s)
	if !isstring(s) then return "" end
	s = string_Trim(s)
	s = string_TrimLeft(s, "!")
	s = string_TrimLeft(s, "/")
	s = string_lower(s)
	return s
end

function EmissiveSys:EvalMaterial(materialName)
	local def = self.Defs[materialName]
	if !def then return nil end

	def._rt = def._rt or {}
	local rt = def._rt
	local now = CurTime()
	if rt._lastT != now then
		rt._lastT = now
		local baseColor = vecFromColorTbl(def.Color)
		local baseBrightness = tonumber(def.Brightness) or 1
		local baseMask = def.Mask

		rt.color = baseColor
		rt.brightness = baseBrightness
		rt.mask = baseMask

		if def.Think then
			local ok, c, b, m = pcall(def.Think, now, rt, def)
			if ok then
				if c != nil then
					if isvector(c) then
						rt.color = c
					elseif istable(c) then
						rt.color = vecFromColorTbl(c)
					elseif tonumber(c) then
						rt.color = baseColor * tonumber(c)
					end
				end
				if b != nil then
					rt.brightness = tonumber(b) or rt.brightness
				end
				if m != nil then
					rt.mask = m && normalizeMatName(m) or nil
				end
			end
		end
	end
	return rt.color, rt.brightness, rt.mask
end

local function makeQueueKey(ent)
	local id = ent:EntIndex()
	if ent.EmissiveSys_CSEntity or ent:GetClass() == "class C_BaseFlex" then
		ent.EmissiveSys_CSEntity = true
		id = id +2050
	end
	return id
end

local function shouldSkipEntity(ent)
	if !IsValid(ent) then return true end
	if ent.ForceNoEmissivePass or ent:GetMaterial() != "" then return true end

	if !EmissiveSys.EnableViewModel then
		local ply = LocalPlayer()
		if IsValid(ply) then
			if ent == ply:GetViewModel() or ent == ply:GetHands() then return true end
		end
	end

	return false
end

local function offCam(ent)
	local viewEnt = GetViewEntity()
	if !IsValid(viewEnt) then return false end
	return ((ent:GetPos() +ent:OBBCenter()) -viewEnt:EyePos()):Dot(viewEnt:GetForward()) < 0
end

local function instEmissiveMat(ent, slotIndex)
	local key = ent:EntIndex() .. ":" .. slotIndex
	local m = EmissiveSys.MatCache[key]
	if IsValid(m) then return m end
	local safeEnt = math_max(0, ent:EntIndex())
	local name = ("emissivesys_e%d_mi_%d"):format(safeEnt, slotIndex)
	m = CreateMaterial(name, "UnlitGeneric", {
		["$basetexture"] = "vgui/black",
		["$model"] = 1,
		["$nodecal"] = 1,
		["$color2"] = Vector(1, 1, 1),
	})
	EmissiveSys.MatCache[key] = m
	return m
end

local function buildEntSignature(ent)
	local mdl  = ent:GetModel() or ""
	local skin = ent:GetSkin() or 0
	local mat  = ent:GetMaterial() or ""
	local mats = ent:GetMaterials()
	local n    = mats && #mats or 0

	local sub = {}
	for i = 0, (n > 0 && (n - 1) or 0) do
		local sm = ent:GetSubMaterial(i)
		if sm && sm != "" then
			sub[#sub + 1] = i .. "=" .. sm
		end
	end

	return table_concat({
		mdl, "|", tostring(skin), "|", mat, "|", tostring(n), "|", table_concat(sub, ";")
	}, "")
end

local function compileProxies(def)
	local proxies = def && def.Proxies
	if !istable(proxies) or #proxies == 0 then return nil end

	local function doSine(vars, now, p)
		local period = tonumber(p.sineperiod or p.period) or 1
		if period <= 0 then period = 1 end
		local vmin = tonumber(p.sinemin) or 0
		local vmax = tonumber(p.sinemax) or 1
		local phase = (now / period) * (math.pi * 2)
		local s = (math.sin(phase) + 1) * 0.5
		vars[p.resultVar] = vmin + (vmax - vmin) * s
	end

	local function doEquals(vars, p)
		vars[p.resultVar] = vars[p.srcVar1]
	end

	return function(now, rt, baseDef)
		rt.vars = rt.vars or {}
		local vars = rt.vars
		vars["$emissiveglow"] = vars["$emissiveglow"] or 1
		vars["$emissivebrightness"] = vars["$emissivebrightness"] or (tonumber(baseDef.Brightness) or 1)
		vars["$selfillummask"] = vars["$selfillummask"] or (baseDef.Mask or nil)
		local outColor, outBrightness, outMask
		for i = 1, #proxies do
			local p = proxies[i]
			local t = p.Type or p.type
			if t == "Sine" then
				doSine(vars, now, p)
			elseif t == "Equals" then
				doEquals(vars, p)
			elseif t == "EfxEmissive" then
				local c = p.color
				local b = p.brightness
				local m = p.emissivetexture
				if isstring(c) then c = vars[c] end
				if isstring(b) then b = vars[b] end
				if isstring(m) then m = vars[m] end
				outColor = c
				outBrightness = b
				outMask = m
			end
		end
		local baseColor = vecFromColorTbl(baseDef.Color)
		if isvector(outColor) then
			outColor = outColor
		elseif istable(outColor) then
			outColor = vecFromColorTbl(outColor)
		elseif tonumber(outColor) then
			outColor = baseColor * tonumber(outColor)
		else
			outColor = baseColor
		end
		outBrightness = tonumber(outBrightness)
		outMask = outMask && normalizeMatName(outMask) or nil
		return outColor, outBrightness, outMask
	end
end

local function rebuildEntCache(ent)
	local mats = ent:GetMaterials()
	if !mats or #mats == 0 then return nil end

	local dataBySlot = nil
	for slot = 1, #mats do
		local matName = normalizeMatName(mats[slot])
		local def = EmissiveSys.Defs[matName]
		if def then
			dataBySlot = dataBySlot or {}
			dataBySlot[slot] = {
				matName = matName,
				mask = def.Mask && normalizeMatName(def.Mask) or nil,
				color = vecFromColorTbl(def.Color),
				brightness = tonumber(def.Brightness) or 1,
			}
		end
	end

	if dataBySlot then
		local cache = EmissiveSys.EntityCache[ent] or {}
		cache.signature = buildEntSignature(ent)
        cache.rev = EmissiveSys.Rev or 0
		cache.dataBySlot = dataBySlot
		cache.numMats = #mats
		cache.boneMerge = ent:IsEffectActive(EF_BONEMERGE) or ent:IsEffectActive(EF_BONEMERGE_FASTCULL) or false
		EmissiveSys.EntityCache[ent] = cache
		EmissiveSys.Queue[makeQueueKey(ent)] = ent
		return cache
	else
		EmissiveSys.EntityCache[ent] = nil
		EmissiveSys.Queue[makeQueueKey(ent)] = nil
		return nil
	end
end

local function verifyCache(ent)
	local cache = EmissiveSys.EntityCache[ent]
	local sig = buildEntSignature(ent)
	if !cache or cache.signature != sig or cache.rev != (EmissiveSys.Rev or 0) then
		return rebuildEntCache(ent)
	end
	return cache
end

function EmissiveSys:Add(materialName, def)
	materialName = normalizeMatName(materialName)
	if materialName == "" then return end

	def = def or {}
	local compiledThink = def.Think
	if !compiledThink and def.Proxies then
		compiledThink = compileProxies(def)
	end
	self.Defs[materialName] = {
		matName = materialName,
		Color = def.Color or {1,1,1},
		Brightness = tonumber(def.Brightness) or 1,
		Mask = def.Mask && normalizeMatName(def.Mask) or nil,
		Think = compiledThink,
		Proxies = def.Proxies,
		_rt = nil,
	}
    self.Rev = (self.Rev or 0) + 1
    self:InvalidateAll()
	self.NextScan = 0
end

function EmissiveSys:Remove(materialName)
	materialName = normalizeMatName(materialName)
	self.Defs[materialName] = nil
	self.Rev = (self.Rev or 0) + 1
	self:InvalidateAll()
end

function EmissiveSys:ClearAll()
	table_Empty(self.Defs)
	self.Rev = (self.Rev or 0) + 1
	self:InvalidateAll()
	table_Empty(self.MatCache)
end

function EmissiveSys:InvalidateAll()
	table_Empty(self.Queue)
	table_Empty(self.EntityCache)
	self.NextScan = 0
end

hook_Add("Think", "EmissiveSys.AutoScan", function()
	if !EmissiveSys.Enabled then return end
	if table_IsEmpty(EmissiveSys.Defs) then return end
	EmissiveSys.NextScan = EmissiveSys.NextScan or 0
	if CurTime() < EmissiveSys.NextScan then return end
	EmissiveSys.NextScan = CurTime() +1
	for _, ent in ipairs(ents_GetAll()) do
		if shouldSkipEntity(ent) then
			EmissiveSys.Queue[makeQueueKey(ent)] = nil
			EmissiveSys.EntityCache[ent] = nil
		else
			verifyCache(ent)
		end
	end
end)

hook_Add("OnEntityCreated", "EmissiveSys.AutoScan", function(ent)
	if !EmissiveSys.Enabled then return end
	if table_IsEmpty(EmissiveSys.Defs) then return end
	timer_Simple(0, function()
		if !IsValid(ent) then return end
		if shouldSkipEntity(ent) then
			EmissiveSys.Queue[makeQueueKey(ent)] = nil
			EmissiveSys.EntityCache[ent] = nil
		else
			verifyCache(ent)
		end
	end)
end)

hook_Add("PreDrawHalos", "EmissiveSys.Render", function()
	if !EmissiveSys.Enabled then return end
	if table_IsEmpty(EmissiveSys.Queue) then return end
	local w, h = ScrW(), ScrH()
	local scale = math_Clamp(tonumber(EmissiveSys.ResolutionScale) or 1, 0.01, 1)
	local nResW, nResH = w * scale, h * scale
	local nonNative = (scale != 1)
	local rtScene = render_GetRenderTarget()
	render_CopyRenderTargetToTexture(rtStore)
	render_Clear(0, 0, 0, 255, false, true)
	cam_Start3D(nil, nil, nil, 0, 0, nResW, nResH)
	cam_IgnoreZ(false)
	render_SuppressEngineLighting(true)
	for key, ent in pairs(EmissiveSys.Queue) do
		if !IsValid(ent) or shouldSkipEntity(ent) then
			EmissiveSys.Queue[key] = nil
			EmissiveSys.EntityCache[ent] = nil
			continue
		end
		-- if offCam(ent) then
		-- 	continue
		-- end
		local cache = verifyCache(ent)
		if !cache or !cache.dataBySlot then
			EmissiveSys.Queue[key] = nil
			continue
		end
		if IsValid(ent:GetParent()) then continue end
		local isVM = false
		local ply = LocalPlayer()
		local vm, hands = IsValid(ply) && ply:GetViewModel() or nil, IsValid(ply) && ply:GetHands() or nil
		if EmissiveSys.EnableViewModel && IsValid(ply) && !ply:ShouldDrawLocalPlayer() then
			if ent == vm or ent == hands or ent.AttachToViewModel or ent.AttachToViewmodel then
				isVM = true
			end
		end
		if isVM then
			cam_IgnoreZ(true)
			render_DepthRange(0, math_Clamp(tonumber(EmissiveSys.ViewModelDepth) or 0.06, 0, 1))
		else
			cam_IgnoreZ(false)
			render_DepthRange(0, 1)
		end
		for slot = 1, cache.numMats do
			local im1 = slot - 1
			local ed = cache.dataBySlot[slot]
			local color, brightness, mask = ed && ed.color, ed && ed.brightness, ed && ed.mask
			if ed && ed.matName then
				color, brightness, mask = EmissiveSys:EvalMaterial(ed.matName)
			end
			
			if mask then
				local m = instEmissiveMat(ent,slot)
				m:SetTexture("$basetexture", mask)
				m:SetVector("$color2", (color or Vector(1,1,1)) * (tonumber(brightness) or 1))
				if cache.boneMerge then
					ent:SetSubMaterial(im1, "!" .. m:GetName())
				else
					render_MaterialOverrideByIndex(im1, m)
				end
			else
				if cache.boneMerge then
					ent:SetSubMaterial(im1, matBlackStr)
				else
					render_MaterialOverrideByIndex(im1, matBlack)
				end
			end
		end
		ent:DrawModel()
		for slot = 1, cache.numMats do
			local im1 = slot - 1
			if cache.boneMerge then
				ent:SetSubMaterial(im1, "")
			else
				render_MaterialOverrideByIndex(im1, nil)
			end
		end
	end
	render_MaterialOverride()
	render_SuppressEngineLighting(false)
	cam_End3D()
	render_CopyRenderTargetToTexture(rtBlur)
	render_SetRenderTarget(rtScene)
	matCopy:SetTexture("$basetexture", rtStore)
	render_SetMaterial(matCopy)
	render_DrawScreenQuad()
	local passTotal = math_max(1, math_floor(tonumber(EmissiveSys.PassTotal) or 1))
	local passInterval = math_max(1, math_floor(tonumber(EmissiveSys.PassInterval) or 1))
	local intensity = tonumber(EmissiveSys.PassIntensity) or 1
	local blurFactor = tonumber(EmissiveSys.BlurInitial) or 2
	local blurInc = tonumber(EmissiveSys.BlurIncrement) or 0.5
	local blurX = tonumber(EmissiveSys.BlurX) or 1
	local blurY = tonumber(EmissiveSys.BlurY) or 1
	local passCount = 0
	local procPass  = 0
	for i = 0, passTotal do
		passCount = passCount + 1
		if (i % passInterval) == 0 then
			procPass = procPass + 1
			blurFactor = blurFactor + (blurInc * i)

			render_PushRenderTarget(rtBlur)
			render_BlurRenderTarget(rtBlur, blurX * blurFactor, blurY * blurFactor, 1)
			render_PopRenderTarget()
		end
		matScreen:SetTexture("$basetexture", rtBlur)
		matScreen:SetFloat("$colormul", intensity)
		render_SetMaterial(matScreen)
		if nonNative then
			local up = scale ^ -1
			render_DrawScreenQuadEx(0, 0, w * up, h * up)
		else
			render_DrawScreenQuad()
		end
	end
end)