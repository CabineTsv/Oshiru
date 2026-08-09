-- cleanest code :>
-- by Cabinet
-- for Oshiru
local cloneref = cloneref or function(obj)
  return obj
end
if type(cloneref) ~= "function" then
  warn("cloneref broken")
end

local Players = cloneref(game:GetService("Players"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Workspace = cloneref(game:GetService("Workspace"))

export type TargetMode = "Closest" | "Vulnerable" | "Smart"

export type Entity = {
   Connections: { RBXScriptConnection },
   Character: Model,
   Health: number,
   Head: BasePart,
   Humanoid: Humanoid,
   HumanoidRootPart: BasePart,
   HipHeight: number,
   MaxHealth: number,
   NPC: boolean,
   Player: Player?,
   RootPart: BasePart,
   SpawnTime: number,
   TeamCheck: (() -> boolean)?,
   Targetable: boolean?,
   Target: boolean?,
   Alive: boolean,
}

export type TargetSettings = {
   Mode: TargetMode?,
   UseMouse: boolean?,
   MouseOrigin: Vector2?,
   Origin: Vector3?,
   Range: number?,
   Part: string?,
   Players: boolean?,
   NPCs: boolean?,
   Wallcheck: (Instance | { Instance })?,
   VisibilityCheck: (Instance | { Instance })?,
   VisibilityIgnore: { Instance }?,
   SmartHealthWeight: number?,
   SmartDistanceWeight: number?,
   IgnoreTeam: boolean?,
}

local LocalPlayer = Players.LocalPlayer

local Enabled = false
local Destroyed = false
local IsAlive = false
local LocalEntity: Entity? = nil

local EntityList: { Entity } = {}
local ActiveConnections: { RBXScriptConnection } = {}

local PlayerConnections: { [Player]: { RBXScriptConnection } } = {}
local EntityThreads: { [Model]: thread } = {}

local Events = setmetatable({}, {
   __index = function(self, Index: string)
   	local Event = {
   		Connections = {},
   		Connect = function(EventSelf: any, Callback: (...any) -> ()): { Disconnect: () -> () }
   			table.insert(EventSelf.Connections, Callback)
   			return {
   				Disconnect = function()
   					local CallbackIndex = table.find(EventSelf.Connections, Callback)
   					if CallbackIndex then
   						table.remove(EventSelf.Connections, CallbackIndex)
   					end
   				end,
   			}
   		end,
   		Fire = function(EventSelf: any, ...: any): ()
   			for _, Callback in ipairs(EventSelf.Connections) do
   				task.spawn(Callback, ...)
   			end
   		end,
   		Destroy = function(EventSelf: any): ()
   			table.clear(EventSelf.Connections)
   			table.clear(EventSelf)
   		end,
   	}
   	self[Index] = Event
   	return Event
   end,
})

local function GetCamera(): Camera?
   return Workspace.CurrentCamera
end

local function GetMousePosition(): Vector2
   local Camera = GetCamera()
   if UserInputService.TouchEnabled and Camera then
   	return Camera.ViewportSize / 2
   end
   return UserInputService:GetMouseLocation()
end

local function LoopClean(Table: { [any]: any }): ()
   for Index, Value in pairs(Table) do
   	if type(Value) == "table" then
   		LoopClean(Value)
   	end
   	Table[Index] = nil
   end
end

local function WaitForChildOfType(Obj: Instance, Name: string, Timeout: number, Prop: boolean?): Instance?
   local CheckTick = os.clock() + Timeout
   local Returned: Instance? = nil
   repeat
   	Returned = if Prop then (Obj :: any)[Name] else Obj:FindFirstChildOfClass(Name)
   	if Returned or CheckTick < os.clock() then
   		break
   	end
   	task.wait()
   until false
   return Returned
end

local function IsSameTeam(TargetPlayer: Player?): boolean
   if not TargetPlayer then
   	return false
   end
   if not LocalPlayer.Team or not TargetPlayer.Team then
   	return false
   end
   return LocalPlayer.Team == TargetPlayer.Team
end

local function TargetCheck(TargetEntity: Entity): boolean
   if TargetEntity.TeamCheck then
   	return TargetEntity.TeamCheck()
   end
   if TargetEntity.NPC then
   	return true
   end
   if IsSameTeam(TargetEntity.Player) then
   	return false
   end
   return true
end

local function IsValidEntity(TargetEntity: Entity?): boolean
   if not TargetEntity then
   	return false
   end
   if not TargetEntity.Character or not TargetEntity.Character.Parent then
   	return false
   end
   if not TargetEntity.Humanoid or not TargetEntity.RootPart or not TargetEntity.Head then
   	return false
   end
   return true
end

local function GetUpdateConnections(TargetEntity: Entity): { RBXScriptSignal }
   local TargetHumanoid = TargetEntity.Humanoid
   return {
   	TargetHumanoid:GetPropertyChangedSignal("Health"),
   	TargetHumanoid:GetPropertyChangedSignal("MaxHealth"),
   	TargetHumanoid.Died,
   	TargetHumanoid.StateChanged,
   }
end

local function IsAttackable(TargetEntity: Entity): boolean
   if not IsValidEntity(TargetEntity) then
   	return false
   end
   if not TargetEntity.Alive then
   	return false
   end
   if TargetEntity.Character:FindFirstChildWhichIsA("ForceField") then
   	return false
   end
   return true
end

local function GetEntityPart(TargetEntity: Entity, PartName: string): BasePart?
   if PartName == "Head" then
   	return TargetEntity.Head
   elseif PartName == "HumanoidRootPart" then
   	return TargetEntity.HumanoidRootPart
   elseif PartName == "RootPart" then
   	return TargetEntity.RootPart
   end
   local Part = TargetEntity.Character:FindFirstChild(PartName)
   return if Part and Part:IsA("BasePart") then Part else nil
end

local function BuildRaycastParams(IgnoreData: any, ExtraIgnore: { Instance }?): RaycastParams
   local Params = RaycastParams.new()
   Params.RespectCanCollide = true
   local IgnoreList: { Instance } = {}

   if LocalPlayer.Character then
   	table.insert(IgnoreList, LocalPlayer.Character)
   end

   local Camera = GetCamera()
   if Camera then
   	table.insert(IgnoreList, Camera)
   end

   for _, TrackedEntity in ipairs(EntityList) do
   	if TrackedEntity.Character and TrackedEntity.Character ~= LocalPlayer.Character then
   		table.insert(IgnoreList, TrackedEntity.Character)
   	end
   end

   if typeof(IgnoreData) == "table" then
   	for _, Obj in ipairs(IgnoreData) do
   		if typeof(Obj) == "Instance" then
   			table.insert(IgnoreList, Obj)
   		end
   	end
   end

   if ExtraIgnore then
   	for _, Obj in ipairs(ExtraIgnore) do
   		if typeof(Obj) == "Instance" then
   			table.insert(IgnoreList, Obj)
   		end
   	end
   end

   Params.FilterDescendantsInstances = IgnoreList
   return Params
end

local function PerformVisibilityCheck(Origin: Vector3, Position: Vector3, IgnoreData: any, ExtraIgnore: { Instance }?): RaycastResult?
   local Params: RaycastParams
   if typeof(IgnoreData) == "Instance" and IgnoreData:IsA("RaycastParams") then
   	Params = IgnoreData
   else
   	Params = BuildRaycastParams(IgnoreData, ExtraIgnore)
   end
   return Workspace:Raycast(Origin, Position - Origin, Params)
end

local EntityLib = {
   Events = Events,
}

function EntityLib.GetBestTarget(Settings: TargetSettings): Entity?
   if not IsAlive or not LocalEntity then
   	return nil
   end

   local BestEntity: Entity? = nil
   local BestScore = math.huge
   local Mode = Settings.Mode or "Closest"
   local UseMouse = Settings.UseMouse or false
   local Origin2D = if UseMouse then (Settings.MouseOrigin or GetMousePosition()) else nil
   local Origin3D = if not UseMouse then (Settings.Origin or LocalEntity.RootPart.Position) else nil
   local Range = Settings.Range or math.huge
   local PartName = Settings.Part or "HumanoidRootPart"
   local Camera = GetCamera()
   local HealthWeight = Settings.SmartHealthWeight or 1
   local DistanceWeight = Settings.SmartDistanceWeight or 1
   local IgnoreTeam = Settings.IgnoreTeam or false

   for _, TargetEntity in ipairs(EntityList) do
   	if not IsAttackable(TargetEntity) then
   		continue
   	end
   	if not Settings.Players and TargetEntity.Player then
   		continue
   	end
   	if not Settings.NPCs and TargetEntity.NPC then
   		continue
   	end
   	if not TargetEntity.Targetable and not IgnoreTeam then
   		continue
   	end

   	local TargetPart = GetEntityPart(TargetEntity, PartName)
   	if not TargetPart then
   		continue
   	end

   	local PartPosition = TargetPart.Position
   	local Magnitude = 0
   	local IsVisible = true

   	if UseMouse and Origin2D then
   		if not Camera then
   			continue
   		end
   		local ScreenPosition, OnScreen = Camera:WorldToViewportPoint(PartPosition)
   		IsVisible = OnScreen
   		if not IsVisible then
   			continue
   		end
   		Magnitude = (Origin2D - Vector2.new(ScreenPosition.X, ScreenPosition.Y)).Magnitude
   	elseif Origin3D then
   		Magnitude = (Origin3D - PartPosition).Magnitude
   	else
   		continue
   	end

   	if Magnitude > Range then
   		continue
   	end

   	local VisibilityConfig = Settings.VisibilityCheck or Settings.Wallcheck
   	if VisibilityConfig then
   		local StartPosition = if UseMouse and Camera then Camera.CFrame.Position else (Origin3D :: Vector3)
   		if PerformVisibilityCheck(StartPosition, PartPosition, VisibilityConfig, Settings.VisibilityIgnore) then
   			continue
   		end
   	end

   	local Score = math.huge
   	if TargetEntity.Target then
   		Score = -math.huge
   	else
   		if Mode == "Closest" then
   			Score = Magnitude
   		elseif Mode == "Vulnerable" then
   			Score = TargetEntity.Health
   		elseif Mode == "Smart" then
   			local HealthPercent = TargetEntity.Health / math.max(TargetEntity.MaxHealth, 1)
   			local HealthFactor = HealthPercent * 100 * HealthWeight
   			local DistanceFactor = math.clamp(Magnitude / math.max(Range, 1), 0, 1) * 100 * DistanceWeight
   			Score = HealthFactor + DistanceFactor
   		end
   	end

   	if Score < BestScore then
   		BestScore = Score
   		BestEntity = TargetEntity
   	end
   end

   return BestEntity
end

function EntityLib.GetEntity(Character: Model | Player): (Entity?, number?)
   for Index, TargetEntity in ipairs(EntityList) do
   	if TargetEntity.Player == Character or TargetEntity.Character == Character then
   		return TargetEntity, Index
   	end
   end
   return nil, nil
end

function EntityLib.AddEntity(Character: Model?, TargetPlayer: Player?, TeamFunc: (() -> boolean)?, SpawnTime: number?): ()
   if not Character then
   	return
   end

   if EntityThreads[Character] then
   	task.cancel(EntityThreads[Character])
   end

   EntityThreads[Character] = task.spawn(function()
   	if Destroyed or not Enabled then
   		EntityThreads[Character] = nil
   		return
   	end

   	if TargetPlayer == LocalPlayer and LocalEntity then
   		EntityLib.RemoveEntity(nil, true)
   	end

   	local TargetHumanoid = WaitForChildOfType(Character, "Humanoid", 10) :: Humanoid?
   	if not TargetHumanoid or Destroyed or not Enabled then
   		EntityThreads[Character] = nil
   		return
   	end

   	local TargetRootPart = WaitForChildOfType(TargetHumanoid, "RootPart", Workspace.StreamingEnabled and 30 or 10, true) :: BasePart?
   	if not TargetRootPart or Destroyed or not Enabled then
   		EntityThreads[Character] = nil
   		return
   	end

   	local HeadChild = Character:WaitForChild("Head", 10)
   	local TargetHead: BasePart? = if HeadChild and HeadChild:IsA("BasePart") then HeadChild else TargetRootPart

   	if not Character.Parent or Destroyed or not Enabled then
   		EntityThreads[Character] = nil
   		return
   	end

   	local HipHeight = 0
   	pcall(function()
   		HipHeight = (TargetHumanoid.HipHeight or 0) + (TargetRootPart.Size.Y / 2) + (TargetHumanoid.RigType == Enum.HumanoidRigType.R6 and 2 or 0)
   	end)

   	local NewEntity: Entity = {
   		Connections = {},
   		Character = Character,
   		Health = TargetHumanoid.Health,
   		Head = TargetHead,
   		Humanoid = TargetHumanoid,
   		HumanoidRootPart = TargetRootPart,
   		HipHeight = HipHeight,
   		MaxHealth = TargetHumanoid.MaxHealth,
   		NPC = TargetPlayer == nil,
   		Player = TargetPlayer,
   		RootPart = TargetRootPart,
   		SpawnTime = SpawnTime or 0,
   		TeamCheck = TeamFunc,
   		Alive = TargetHumanoid.Health > 0 and TargetHumanoid:GetState() ~= Enum.HumanoidStateType.Dead,
   	}

   	if TargetPlayer == LocalPlayer then
   		LocalEntity = NewEntity
   		IsAlive = NewEntity.Alive
   		Events.LocalAdded:Fire(NewEntity)

   		table.insert(NewEntity.Connections, TargetHumanoid:GetPropertyChangedSignal("Health"):Connect(function()
   			if not LocalEntity then
   				return
   			end
   			LocalEntity.Health = TargetHumanoid.Health
   			LocalEntity.Alive = TargetHumanoid.Health > 0 and TargetHumanoid:GetState() ~= Enum.HumanoidStateType.Dead
   			IsAlive = LocalEntity.Alive
   			Events.EntityUpdated:Fire(LocalEntity)
   		end))

   		table.insert(NewEntity.Connections, TargetHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
   			if not LocalEntity then
   				return
   			end
   			LocalEntity.MaxHealth = TargetHumanoid.MaxHealth
   			Events.EntityUpdated:Fire(LocalEntity)
   		end))

   		table.insert(NewEntity.Connections, TargetHumanoid.Died:Connect(function()
   			if not LocalEntity then
   				return
   			end
   			LocalEntity.Alive = false
   			LocalEntity.Health = 0
   			IsAlive = false
   			Events.EntityUpdated:Fire(LocalEntity)
   		end))

   		table.insert(NewEntity.Connections, TargetHumanoid.StateChanged:Connect(function()
   			if not LocalEntity then
   				return
   			end
   			LocalEntity.Alive = TargetHumanoid.Health > 0 and TargetHumanoid:GetState() ~= Enum.HumanoidStateType.Dead
   			IsAlive = LocalEntity.Alive
   			Events.EntityUpdated:Fire(LocalEntity)
   		end))
   	else
   		NewEntity.Targetable = TargetCheck(NewEntity)

   		local function UpdateEntity()
   			if not NewEntity.Character or not NewEntity.Character.Parent then
   				return
   			end
   			NewEntity.Health = TargetHumanoid.Health
   			NewEntity.MaxHealth = TargetHumanoid.MaxHealth
   			NewEntity.Alive = TargetHumanoid.Health > 0 and TargetHumanoid:GetState() ~= Enum.HumanoidStateType.Dead
   			Events.EntityUpdated:Fire(NewEntity)
   		end

   		for _, ConnectionSignal in ipairs(GetUpdateConnections(NewEntity)) do
   			table.insert(NewEntity.Connections, ConnectionSignal:Connect(UpdateEntity))
   		end

   		table.insert(EntityList, NewEntity)
   		Events.EntityAdded:Fire(NewEntity)
   	end

   	EntityThreads[Character] = nil
   end)
end

function EntityLib.RemoveEntity(Character: Model?, IsLocal: boolean?): ()
   if IsLocal then
   	if LocalEntity then
   		IsAlive = false
   		for _, Connection in ipairs(LocalEntity.Connections) do
   			Connection:Disconnect()
   		end
   		table.clear(LocalEntity.Connections)
   		Events.LocalRemoved:Fire(LocalEntity)
   		LocalEntity = nil
   	end
   	return
   end

   if Character then
   	if EntityThreads[Character] then
   		task.cancel(EntityThreads[Character])
   		EntityThreads[Character] = nil
   	end

   	local TargetEntity, Index = EntityLib.GetEntity(Character)
   	if TargetEntity and Index then
   		for _, Connection in ipairs(TargetEntity.Connections) do
   			Connection:Disconnect()
   		end
   		table.clear(TargetEntity.Connections)
   		table.remove(EntityList, Index)
   		Events.EntityRemoved:Fire(TargetEntity)
   	end
   end
end

function EntityLib.RefreshEntity(Character: Model, TargetPlayer: Player, SpawnTime: number?): ()
   local ExistingEntity = EntityLib.GetEntity(TargetPlayer)
   EntityLib.RemoveEntity(Character)
   EntityLib.AddEntity(Character, TargetPlayer, if ExistingEntity then ExistingEntity.TeamCheck else nil, SpawnTime)
end

function EntityLib.AddPlayer(TargetPlayer: Player): ()
   if PlayerConnections[TargetPlayer] then
   	EntityLib.RemovePlayer(TargetPlayer)
   end

   if TargetPlayer.Character then
   	EntityLib.RefreshEntity(TargetPlayer.Character, TargetPlayer)
   end

   PlayerConnections[TargetPlayer] = {
   	TargetPlayer.CharacterAdded:Connect(function(Character: Model)
   		EntityLib.RefreshEntity(Character, TargetPlayer, os.clock() + 0.4)
   	end),
   	TargetPlayer.CharacterRemoving:Connect(function(Character: Model)
   		EntityLib.RemoveEntity(Character, TargetPlayer == LocalPlayer)
   	end),
   	TargetPlayer:GetPropertyChangedSignal("Team"):Connect(function()
   		if TargetPlayer == LocalPlayer then
   			for _, TargetEntity in ipairs(EntityList) do
   				local NewTargetable = TargetCheck(TargetEntity)
   				if TargetEntity.Targetable ~= NewTargetable then
   					TargetEntity.Targetable = NewTargetable
   					Events.EntityUpdated:Fire(TargetEntity)
   				end
   			end
   		else
   			local TargetEntity = EntityLib.GetEntity(TargetPlayer)
   			if TargetEntity then
   				EntityLib.RefreshEntity(TargetEntity.Character, TargetPlayer)
   			end
   		end
   	end),
   }
end

function EntityLib.RemovePlayer(TargetPlayer: Player): ()
   local Connections = PlayerConnections[TargetPlayer]
   if Connections then
   	for _, Connection in ipairs(Connections) do
   		Connection:Disconnect()
   	end
   	table.clear(Connections)
   	PlayerConnections[TargetPlayer] = nil
   end

   if TargetPlayer.Character then
   	EntityLib.RemoveEntity(TargetPlayer.Character)
   end
end

function EntityLib:Enable(): ()
   assert(not Destroyed, "EntityLib:Enable was called after Destroy")
   if Enabled then
   	self:Disable()
   end

   ActiveConnections = {
   	Players.PlayerAdded:Connect(function(TargetPlayer: Player)
   		EntityLib.AddPlayer(TargetPlayer)
   	end),
   	Players.PlayerRemoving:Connect(function(TargetPlayer: Player)
   		EntityLib.RemovePlayer(TargetPlayer)
   	end),
   }

   Enabled = true

   for _, TargetPlayer in ipairs(Players:GetPlayers()) do
   	EntityLib.AddPlayer(TargetPlayer)
   end
end

function EntityLib:Disable(): ()
   for _, Connection in ipairs(ActiveConnections) do
   	Connection:Disconnect()
   end

   for _, Connections in pairs(PlayerConnections) do
   	for _, Connection in ipairs(Connections) do
   		Connection:Disconnect()
   	end
   	table.clear(Connections)
   end

   EntityLib.RemoveEntity(nil, true)

   local ClonedList = table.clone(EntityList)
   for _, TargetEntity in ipairs(ClonedList) do
   	EntityLib.RemoveEntity(TargetEntity.Character)
   end

   for _, Thread in pairs(EntityThreads) do
   	task.cancel(Thread)
   end

   table.clear(PlayerConnections)
   table.clear(EntityThreads)
   table.clear(ActiveConnections)
   table.clear(ClonedList)

   Enabled = false
end

function EntityLib:Refresh(): ()
   local ClonedList = table.clone(EntityList)
   for _, TargetEntity in ipairs(ClonedList) do
   	if TargetEntity.Character and TargetEntity.Player then
   		EntityLib.RefreshEntity(TargetEntity.Character, TargetEntity.Player)
   	end
   end
   table.clear(ClonedList)
end

function EntityLib:Destroy(): ()
   if Destroyed then
   	return
   end
   if Enabled then
   	self:Disable()
   end

   for _, Event in pairs(Events :: any) do
   	if type(Event) == "table" and Event.Destroy then
   		Event:Destroy()
   	end
   end

   LoopClean(EntityLib)
   Destroyed = true
end

function EntityLib:IsAlive(): boolean
   return IsAlive
end

function EntityLib:GetLocalEntity(): Entity?
   return LocalEntity
end

function EntityLib:GetEntityList(): { Entity }
   return EntityList
end

function EntityLib:IsValid(TargetEntity: Entity?): boolean
   return IsValidEntity(TargetEntity)
end

EntityLib:Enable()

return EntityLib
