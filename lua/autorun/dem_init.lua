if CLIENT then
	local math_Clamp = math.Clamp
	local render_GetLightColor = render.GetLightColor
	local default0 = Vector(0,0,0)
	local defaultTint = Vector()

    matproxy.Add({
        name = "DynamicEnvMap",
        init = function(self,mat,values)
            self.Result = values.resultvar

			self.TintScale = mat:GetVector("$DEM_TintScale") or defaultTint
			self.Multiplier = mat:GetFloat("$DEM_Multiplier") or 1
			self.ClampMin = mat:GetVector("$DEM_ClampMin") or default0
			self.ClampMax = mat:GetVector("$DEM_ClampMax")
        end,
        bind = function(self,mat,ent)
            if (!IsValid(ent)) then return end

			local finalResult = defaultTint
			local mult = self.Multiplier
			local clampMin = self.ClampMin
			local clampMax = self.ClampMax
			local luminance = render_GetLightColor(ent:GetPos() +ent:OBBCenter()) *mult
			finalResult = (self.TintScale *luminance) *mult
			if clampMax then
				finalResult.x = math_Clamp(finalResult.x,clampMin.x,clampMax.x)
				finalResult.y = math_Clamp(finalResult.y,clampMin.y,clampMax.y)
				finalResult.z = math_Clamp(finalResult.z,clampMin.z,clampMax.z)
			end

			-- print(finalResult)
			mat:SetVector(self.Result,finalResult)
        end
    })

    print("DynamicEnvMap proxy successfully loaded!")
end

/*
    Add this to your VMT to initialize the proxy:

	"$DEM_TintScale" 			"[1 1 1]" // Color scaling essentially, if you want default envmap tint, leave this as is
	"$DEM_Multiplier" 			"1" // Multiplies the output, should change this based on other $envmap settings that alter the strength/color
	"$DEM_ClampMin" 			"[0 0 0]" // Optional, clamps the output to a minimum value
	"$DEM_ClampMax" 			"[1 1 1]" // Optional, clamps the output to a maximum value

	"Proxies" 
	{
		"DynamicEnvMap"
		{
			resultVar	"$envmaptint"
		}
    }
*/