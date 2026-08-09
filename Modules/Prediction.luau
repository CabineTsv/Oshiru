-- cleanerst code :>
-- by Cabinet
-- for Oshiru
local Prediction = {
	Smoothing = 0.07,
	PingCompensation = true,
	PingMultiplier = 1.0,
	MaxHistory = 8,
	VelocityThreshold = 0.1,
	AccelerationScale = 0.5,
	PredictionTime = nil,
	JitterThreshold = 50,
	_Tracked = {},
	_History = {},
	_Velocity = {},
	_SmoothedVelocity = {},
	_Acceleration = {},
	_LastUpdateTime = {},
	_EntityConnections = {},
	_HeartbeatConnection = nil,
	_Enabled = false,
	_EntityLib = nil,
}

local cloneref = if type(cloneref) == "function" then
  cloneref
else
  function(obj)
    return obj
  end
end
local RunService = cloneref(game:GetService("RunService"))
local Players = cloneref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer

function Prediction.TrackEntity(entity)
	if not entity or not entity.Character then
		return
	end
	local char = entity.Character
	if Prediction._Tracked[char] then
		return
	end
	Prediction._Tracked[char] = entity
	Prediction._History[char] = {}
	Prediction._Velocity[char] = Vector3.zero
	Prediction._SmoothedVelocity[char] = Vector3.zero
	Prediction._Acceleration[char] = Vector3.zero
	Prediction._LastUpdateTime[char] = 0
	Prediction.UpdateEntity(entity)
end

function Prediction.UntrackEntity(entity)
	local char = entity and entity.Character
	if not char then
		return
	end
	Prediction._Tracked[char] = nil
	Prediction._History[char] = nil
	Prediction._Velocity[char] = nil
	Prediction._SmoothedVelocity[char] = nil
	Prediction._Acceleration[char] = nil
	Prediction._LastUpdateTime[char] = nil
end

function Prediction.UpdateEntity(entity)
	if not entity or not entity.Character then
		return
	end
	local char = entity.Character
	if not char.Parent then
		Prediction.UntrackEntity(entity)
		return
	end
	local root = entity.RootPart or entity.HumanoidRootPart
	if not root then
		return
	end
	local now = os.clock()
	local lastTime = Prediction._LastUpdateTime[char] or 0
	if now == lastTime then
		return
	end
	local pos = root.Position
	local hist = Prediction._History[char]
	if not hist then
		hist = {}
		Prediction._History[char] = hist
	end
	if #hist > 0 then
		local last = hist[1]
		local dt = now - last.Time
		if dt > 0 then
			local expectedDist = (Prediction._SmoothedVelocity[char] or Vector3.zero).Magnitude * dt
			local actualDist = (pos - last.Position).Magnitude
			if actualDist > math.max(expectedDist, 0.1) + Prediction.JitterThreshold and dt < 0.3 then
				Prediction._History[char] = {{Position = pos, Time = now}}
				Prediction._Velocity[char] = Vector3.zero
				Prediction._SmoothedVelocity[char] = Vector3.zero
				Prediction._Acceleration[char] = Vector3.zero
				Prediction._LastUpdateTime[char] = now
				return
			end
		end
	end
	table.insert(hist, 1, {Position = pos, Time = now})
	while #hist > Prediction.MaxHistory do
		table.remove(hist)
	end
	local rawVel = Vector3.zero
	if #hist >= 2 then
		local weightedVel = Vector3.zero
		local totalWeight = 0
		local sampleCount = math.min(#hist - 1, 4)
		for i = 2, sampleCount + 1 do
			local p1, p2 = hist[i], hist[i - 1]
			local dt = p2.Time - p1.Time
			if dt > 0.001 then
				local vel = (p2.Position - p1.Position) / dt
				local weight = (sampleCount - (i - 2)) / sampleCount
				weightedVel = weightedVel + vel * weight
				totalWeight = totalWeight + weight
			end
		end
		if totalWeight > 0 then
			rawVel = weightedVel / totalWeight
		end
	end
	Prediction._Velocity[char] = rawVel
	local oldSmooth = Prediction._SmoothedVelocity[char] or Vector3.zero
	local s = math.clamp(Prediction.Smoothing, 0, 1)
	local newSmooth = oldSmooth:Lerp(rawVel, s)
	if newSmooth.Magnitude < Prediction.VelocityThreshold then
		newSmooth = Vector3.zero
	end
	Prediction._SmoothedVelocity[char] = newSmooth
	local newAccel = Vector3.zero
	local dt = now - lastTime
	if lastTime > 0 and dt > 0.001 then
		newAccel = (newSmooth - oldSmooth) / dt
		local maxAccel = 500
		if newAccel.Magnitude > maxAccel then
			newAccel = newAccel.Unit * maxAccel
		end
	end
	local accelSmooth = math.clamp(Prediction.Smoothing * 1.5, 0, 1)
	local oldAccel = Prediction._Acceleration[char] or Vector3.zero
	Prediction._Acceleration[char] = oldAccel:Lerp(newAccel, accelSmooth)
	Prediction._LastUpdateTime[char] = now
end

function Prediction.GetPredictedPosition(entity, timeAhead)
	if not entity or not entity.Character then
		return nil
	end
	local char = entity.Character
	if not char.Parent then
		return nil
	end
	local root = entity.RootPart or entity.HumanoidRootPart
	if not root then
		return nil
	end
	local now = os.clock()
	local lastTime = Prediction._LastUpdateTime[char] or 0
	if now > lastTime then
		Prediction.UpdateEntity(entity)
	end
	local t = timeAhead
	if t == nil then
		if Prediction.PredictionTime ~= nil then
			t = Prediction.PredictionTime
		elseif Prediction.PingCompensation and LocalPlayer then
			local ping = LocalPlayer:GetNetworkPing() or 0
			t = ping * 0.5 * Prediction.PingMultiplier
		else
			t = 0
		end
	end
	if type(t) ~= "number" or t ~= t or t < 0 then
		t = 0
	end
	t = math.clamp(t, 0, 2)
	local vel = Prediction._SmoothedVelocity[char] or Vector3.zero
	local accel = Prediction._Acceleration[char] or Vector3.zero
	return root.Position + vel * t + 0.5 * accel * t * t * math.clamp(Prediction.AccelerationScale, 0, 1)
end

function Prediction.GetAimPosition(entity, partName)
	if not entity or not entity.Character then
		return nil
	end
	local char = entity.Character
	if not char.Parent then
		return nil
	end
	local part
	if partName then
		if partName == "Head" and entity.Head and entity.Head.Parent == char then
			part = entity.Head
		elseif partName == "HumanoidRootPart" and entity.HumanoidRootPart and entity.HumanoidRootPart.Parent == char then
			part = entity.HumanoidRootPart
		elseif partName == "RootPart" and entity.RootPart and entity.RootPart.Parent == char then
			part = entity.RootPart
		else
			part = char:FindFirstChild(partName)
		end
	else
		part = entity.Head or entity.HumanoidRootPart or entity.RootPart
	end
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local root = entity.RootPart or entity.HumanoidRootPart
	if not root then
		return part.Position
	end
	local predictedRoot = Prediction.GetPredictedPosition(entity, nil)
	if not predictedRoot then
		return part.Position
	end
	return part.Position + (predictedRoot - root.Position)
end

function Prediction.GetVelocity(entity)
	if not entity or not entity.Character then
		return Vector3.zero
	end
	return Prediction._SmoothedVelocity[entity.Character] or Vector3.zero
end

function Prediction.GetAcceleration(entity)
	if not entity or not entity.Character then
		return Vector3.zero
	end
	return Prediction._Acceleration[entity.Character] or Vector3.zero
end

function Prediction.BindToEntityLib(EntityLib)
	if not EntityLib then
		return
	end
	if Prediction._EntityLib and Prediction._EntityLib ~= EntityLib then
		Prediction.Clear()
	end
	Prediction._EntityLib = EntityLib
	for _, conn in ipairs(Prediction._EntityConnections) do
		conn:Disconnect()
	end
	table.clear(Prediction._EntityConnections)
	local function onAdded(ent)
		Prediction.TrackEntity(ent)
	end
	local function onRemoved(ent)
		Prediction.UntrackEntity(ent)
	end
	table.insert(Prediction._EntityConnections, EntityLib.Events.EntityAdded:Connect(onAdded))
	table.insert(Prediction._EntityConnections, EntityLib.Events.EntityRemoved:Connect(onRemoved))
	table.insert(Prediction._EntityConnections, EntityLib.Events.LocalAdded:Connect(onAdded))
	table.insert(Prediction._EntityConnections, EntityLib.Events.LocalRemoved:Connect(onRemoved))
	for _, ent in ipairs(EntityLib:GetEntityList()) do
		Prediction.TrackEntity(ent)
	end
	local localEnt = EntityLib:GetLocalEntity()
	if localEnt then
		Prediction.TrackEntity(localEnt)
	end
end

function Prediction.Enable()
	if Prediction._Enabled then
		return
	end
	Prediction._Enabled = true
	Prediction._HeartbeatConnection = RunService.Heartbeat:Connect(function()
		for char, entity in pairs(Prediction._Tracked) do
			if entity and entity.Character == char then
				if char.Parent then
					Prediction.UpdateEntity(entity)
				else
					Prediction.UntrackEntity(entity)
				end
			else
				Prediction._Tracked[char] = nil
				Prediction._History[char] = nil
				Prediction._Velocity[char] = nil
				Prediction._SmoothedVelocity[char] = nil
				Prediction._Acceleration[char] = nil
				Prediction._LastUpdateTime[char] = nil
			end
		end
	end)
end

function Prediction.Disable()
	if Prediction._HeartbeatConnection then
		Prediction._HeartbeatConnection:Disconnect()
		Prediction._HeartbeatConnection = nil
	end
	Prediction._Enabled = false
end

function Prediction.Clear()
	Prediction.Disable()
	for char in pairs(Prediction._Tracked) do
		Prediction._Tracked[char] = nil
		Prediction._History[char] = nil
		Prediction._Velocity[char] = nil
		Prediction._SmoothedVelocity[char] = nil
		Prediction._Acceleration[char] = nil
		Prediction._LastUpdateTime[char] = nil
	end
	for _, conn in ipairs(Prediction._EntityConnections) do
		conn:Disconnect()
	end
	table.clear(Prediction._EntityConnections)
	Prediction._EntityLib = nil
end

return Prediction
