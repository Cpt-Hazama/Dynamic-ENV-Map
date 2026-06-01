VJ = VJ or {}
VJ.CPT = VJ.CPT or {}

if SERVER then
	function VJ.CPT:SetClearPos(self,origin,disableGroundSnap)
		if !IsValid(self) then return end
		local mins = self:OBBMins()
		local maxs = self:OBBMaxs()
		local pos = origin || self:GetPos()
		local savePos = pos
		local nearents = ents.FindInBox(pos +mins,pos +maxs)
		maxs.x = maxs.x *2
		maxs.y = maxs.y *2
		local zMax = 0
		local entTgt
		for _,ent in ipairs(nearents) do
			if(ent != self && ent:GetSolid() != SOLID_NONE && ent:GetSolid() != SOLID_BSP && gamemode.Call("ShouldCollide",self,ent) != false) then
				local obbMaxs = ent:OBBMaxs()
				if(obbMaxs.z > zMax) then
					zMax = obbMaxs.z
					entTgt = ent
				end
			end
		end
		local tbl_filter = {self,entTgt}
		local stayaway = zMax > 0
		if(!stayaway) then
			pos.z = pos.z +10
		else
			zMax = zMax +10
		end
		local left = Vector(0,1,0)
		local right = left *-1
		local forward = Vector(1,0,0)
		local back = forward *-1
		local trace_left = util.TraceLine({
			start = pos,
			endpos = pos +left *maxs.y,
			filter = tbl_filter
		})
		local trace_right = util.TraceLine({
			start = pos,
			endpos = pos +right *maxs.y,
			filter = tbl_filter
		})
		if(trace_left.Hit || trace_right.Hit) then
			if(trace_left.Fraction < trace_right.Fraction) then
				pos = pos +right *((trace_right.Fraction -trace_left.Fraction) *maxs.y)
			elseif(trace_right.Fraction < trace_left.Fraction) then
				pos = pos +left *((trace_left.Fraction -trace_right.Fraction) *maxs.y)
			end
		elseif(stayaway) then
			pos = pos +(math.random(1,2) == 1 && left || right) *maxs.y *1.8
			stayaway = false
		end
		local trace_forward = util.TraceLine({
			start = pos,
			endpos = pos +forward *maxs.x,
			filter = tbl_filter
		})
		local trace_backward = util.TraceLine({
			start = pos,
			endpos = pos +back *maxs.x,
			filter = tbl_filter
		})
		if(trace_forward.Hit || trace_backward.Hit) then
			if(trace_forward.Fraction < trace_backward.Fraction) then
				pos = pos +back *((trace_backward.Fraction -trace_forward.Fraction) *maxs.x)
			elseif(trace_backward.Fraction < trace_forward.Fraction) then
				pos = pos +forward *((trace_forward.Fraction -trace_backward.Fraction) *maxs.x)
			end
		elseif(stayaway) then
			pos = pos +(math.random(1,2) == 1 && forward || back) *maxs.x *1.8
			stayaway = false
		end
		if(stayaway) then -- We can't avoid whatever it is we're stuck in,let's try to spawn on top of it
			local start = entTgt:GetPos()
			start.z = start.z +zMax
			local endpos = start
			endpos.z = endpos.z +maxs.z
			local tr = util.TraceLine({
				start = start,
				endpos = endpos,
				filter = tbl_filter
			})
			if(!tr.Hit || (!tr.HitWorld && gamemode.Call("ShouldCollide",self,tr.Entity) == false)) then
				pos.z = start.z
				stayaway = false
			else -- Just try to move to whatever direction seems best
				local trTgt = trace_left
				if(trace_right.Fraction < trTgt.Fraction) then trTgt = trace_right end
				if(trace_forward.Fraction < trTgt.Fraction) then trTgt = trace_forward end
				if(trace_backward.Fraction < trTgt.Fraction) then trTgt = trace_backward end
				pos = pos +trTgt.Normal *maxs.x
			end
		end
		if !disableGroundSnap then
			local trDown = util.TraceLine({
				start = pos,
				endpos = pos +Vector(0,0,maxs.z *-2),
				filter = tbl_filter,
				-- collisiongroup = COLLISION_GROUP_WORLD,
			})
			if(trDown.Hit) then
				debugoverlay.Line(pos,trDown.HitPos,5,Color(255,255,255))
				debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(255,255,255))
				pos.z = trDown.HitPos.z
			end
		end
		-- pos.z = pos.z + 3
		-- debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(0,26,255))
		local minC,maxC = self:GetCollisionBounds()
		local corners = { // 4 corners
			Vector(minC.x,minC.y,0),
			Vector(minC.x,maxC.y,0),
			Vector(maxC.x,minC.y,0),
			Vector(maxC.x,maxC.y,0)
		}
		for _,v in pairs(corners) do
			if !util.IsInWorld(pos +v) then
				-- print("BAD CORNER: ",pos +v)
				debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(255,0,0))
				local toSafeDir = (savePos - v):GetNormalized()
				local trace1 = util.TraceLine({
					start = v,
					endpos = savePos,
					filter = tbl_filter,
					collisiongroup = COLLISION_GROUP_WORLD,
					output = {}
				})
				debugoverlay.Line(v,trace1.HitPos,5,Color(255,0,230))
				if trace1.Hit && util.IsInWorld(trace1.HitPos) then
					-- print("Found possible entry point:",trace1.HitPos)
					debugoverlay.Box(trace1.HitPos,Vector(-4,-4,-4),Vector(4,4,4),5,Color(255,0,230))
					local trace2 = util.TraceLine({
						start = trace1.HitPos,
						endpos = v,
						filter = tbl_filter,
						collisiongroup = COLLISION_GROUP_WORLD,
						output = {}
					})
					debugoverlay.Line(v,trace2.HitPos,5,Color(67,227,255))
					if trace2.Hit && util.IsInWorld(trace2.HitPos) then
						-- print("Final valid position near world edge:",trace2.HitPos)
						debugoverlay.Box(trace2.HitPos,Vector(-4,-4,-4),Vector(4,4,4),5,Color(67,227,255))
						pos = trace2.HitPos + trace2.HitNormal *16
					else
						pos = savePos
					end
				else
					pos = savePos
				end
				break
			end
		end
		if !util.IsInWorld(pos) then
			pos = savePos
		end
		pos = pos +Vector(0,0,6)

		debugoverlay.Line(self:GetPos(),pos,5,Color(47,255,0))
		debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(13,255,0))
		self:SetPos(pos)

		return pos
	end
end