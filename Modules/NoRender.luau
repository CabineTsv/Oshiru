-- cleanest code :>
-- by Cabinet
-- for Oshiru
local cloneref = cloneref or function(obj)
  return obj
end
if typeof(cloneref) ~= "function" then
  warn("Support Issues")
end

local CollectionService = cloneref(game:GetService("CollectionService"))
local Lighting = cloneref(game:GetService("Lighting"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

-- types, tags, and other stuff
export type NoRenderMode = "Low" | "Medium" | "Extreme" | "Auto"
type NoRenderTier = "Low" | "Medium" | "Extreme"

type OptimizationSettings = {
	DisableParticles: boolean,
	DisablePostEffects: boolean,
	DisableHighlights: boolean,
	DisableAtmosphere: boolean,
	DetachSurfaceAppearances: boolean,
	OptimizeMeshes: boolean,
	OptimizeMaterials: boolean,
	OptimizeReflectance: boolean,
	DisableShadows: boolean,
	DisableLights: boolean,
	HideTaggedDecorative: boolean,
	DistanceOptimization: boolean,
	OptimizeGuis: boolean,
}

local IgnoreTag = "NoRenderIgnore"
local DecorativeTag = "NoRenderDecorative"

local ExpensiveMaterials: { [string]: boolean } = {
	Neon = true,
	Glass = true,
	ForceField = true,
	Metal = true,
	DiamondPlate = true,
	CorrodedMetal = true,
	Foil = true,
	Ice = true,
}

local WeakKeys = {
  __mode = "k"
}

-- auto variables
local AutoSampleInterval = 1
local AutoMinSwitchInterval = 5
local AutoRequiredSamples = 3
local AutoFpsThresholdLow = 50
local AutoFpsThresholdMedium = 30

local LightBrightnessMultiplier = 0.5
local LightRangeMultiplier = 0.6

local DefaultDistanceThreshold = 250
local DistanceCheckInterval = 2

local ScanBudget = 0.004

-- Config
local ModeSettings: { [string]: OptimizationSettings } = {
	Low = {
		DisableParticles = false,
		DisablePostEffects = false,
		DisableHighlights = false,
		DisableAtmosphere = false,
		DetachSurfaceAppearances = false,
		OptimizeMeshes = true,
		OptimizeMaterials = false,
		OptimizeReflectance = false,
		DisableShadows = false,
		DisableLights = false,
		HideTaggedDecorative = false,
		DistanceOptimization = false,
		OptimizeGuis = false,
	},
	Medium = {
		DisableParticles = true,
		DisablePostEffects = true,
		DisableHighlights = false,
		DisableAtmosphere = false,
		DetachSurfaceAppearances = false,
		OptimizeMeshes = true,
		OptimizeMaterials = true,
		OptimizeReflectance = true,
		DisableShadows = true,
		DisableLights = true,
		HideTaggedDecorative = false,
		DistanceOptimization = false,
		OptimizeGuis = false,
	},
	Extreme = {
		DisableParticles = true,
		DisablePostEffects = true,
		DisableHighlights = true,
		DisableAtmosphere = true,
		DetachSurfaceAppearances = true,
		OptimizeMeshes = true,
		OptimizeMaterials = true,
		OptimizeReflectance = true,
		DisableShadows = true,
		DisableLights = true,
		HideTaggedDecorative = true,
		DistanceOptimization = false,
		OptimizeGuis = true,
	},
}

local ValidConfigKeys: { [string]: boolean } = {}

for Key in pairs(ModeSettings.Low) do
	ValidConfigKeys[Key] = true
end

-- Settings Key
local CategorySettingKeys: { [string]: string } = {
	Particles = "DisableParticles",
	PostEffects = "DisablePostEffects",
	Highlights = "DisableHighlights",
	Atmosphere = "DisableAtmosphere",
	SurfaceAppearances = "DetachSurfaceAppearances",
	Meshes = "OptimizeMeshes",
	Materials = "OptimizeMaterials",
	Reflectance = "OptimizeReflectance",
	Shadows = "DisableShadows",
	Lights = "DisableLights",
	Decorative = "HideTaggedDecorative",
	Distance = "DistanceOptimization",
	Guis = "OptimizeGuis",
}

local DefaultMode: NoRenderTier = "Medium"

-- utilities
local Enabled = false
local Destroyed = false

local CurrentMode: NoRenderMode = DefaultMode
local EffectiveMode: NoRenderTier = DefaultMode

local ManualOverrides: { [string]: boolean } = {}
local ActiveSettings: OptimizationSettings = ModeSettings[DefaultMode]

local LastOptimizationTime: number? = nil
local LastScanDuration = 0
local EnabledSince: number? = nil
local ScanGeneration = 0

local ActiveConnections: { RBXScriptConnection } = {}

local function NewWeakKeyTable(): any
	return setmetatable({}, WeakKeys)
end

local ProcessedInstances: { [Instance]: boolean } = NewWeakKeyTable()
local OriginalProperties: { [Instance]: { [string]: any } } = NewWeakKeyTable()
local PropertyCategories: { [Instance]: { [string]: string } } = NewWeakKeyTable()
local DetachedInstances: { [Instance]: Instance } = {}
local CleanupTracked: { [Instance]: boolean } = NewWeakKeyTable()

local Whitelist: { [Instance]: boolean } = NewWeakKeyTable()
local Blacklist: { [Instance]: boolean } = NewWeakKeyTable()

local CategoryMembers: { [string]: { [Instance]: boolean } } = {}
local InstanceCategories: { [Instance]: { string } } = NewWeakKeyTable()

local function HasIgnoreTag(Instance: Instance): boolean
	return CollectionService:HasTag(Instance, IgnoreTag)
end

local function HasDecorativeTag(Instance: Instance): boolean
	return CollectionService:HasTag(Instance, DecorativeTag)
end

local function ShouldSkipInstance(Instance: Instance): boolean
	if Whitelist[Instance] then
		return true
	end
	if Blacklist[Instance] then
		return false
	end
	return HasIgnoreTag(Instance)
end

local function SetPropertySafely(Instance: Instance, PropertyName: string, Value: any): boolean
	local Success = pcall(function()
		(Instance :: any)[PropertyName] = Value
	end)
	return Success
end

local function CacheOriginalProperty(Instance: Instance, PropertyName: string, Value: any, Category: string): ()
	local Properties = OriginalProperties[Instance]
	if not Properties then
		Properties = {}
		OriginalProperties[Instance] = Properties
	end
	if Properties[PropertyName] == nil then
		Properties[PropertyName] = Value
	end
	local Categories = PropertyCategories[Instance]
	if not Categories then
		Categories = {}
		PropertyCategories[Instance] = Categories
	end
	if Categories[PropertyName] == nil then
		Categories[PropertyName] = Category
	end
end

local function DetachInstance(Instance: Instance): ()
	if DetachedInstances[Instance] ~= nil then
		return
	end
	local OriginalParent = Instance.Parent
	if OriginalParent == nil then
		return
	end
	DetachedInstances[Instance] = OriginalParent
	Instance.Parent = nil
end

local function HideInstanceLocally(Instance: Instance, Category: string): ()
	local BasePart = Instance :: BasePart
	CacheOriginalProperty(Instance, "LocalTransparencyModifier", BasePart.LocalTransparencyModifier, Category)
	SetPropertySafely(Instance, "LocalTransparencyModifier", 1)
end

local function ForgetInstanceTracking(Instance: Instance): ()
	ProcessedInstances[Instance] = nil
	local Categories = InstanceCategories[Instance]
	if Categories then
		for _, Category in ipairs(Categories) do
			local Members = CategoryMembers[Category]
			if Members then
				Members[Instance] = nil
			end
		end
		InstanceCategories[Instance] = nil
	end
end

local function RestoreInstanceFully(Instance: Instance): ()
	local Properties = OriginalProperties[Instance]
	if Properties then
		local Categories = PropertyCategories[Instance]
		for PropertyName, OriginalValue in pairs(Properties) do
			if SetPropertySafely(Instance, PropertyName, OriginalValue) then
				Properties[PropertyName] = nil
				if Categories then
					Categories[PropertyName] = nil
				end
			end
		end
		if next(Properties) == nil then
			OriginalProperties[Instance] = nil
		end
		if Categories and next(Categories) == nil then
			PropertyCategories[Instance] = nil
		end
	end

	local OriginalParent = DetachedInstances[Instance]
	if OriginalParent then
		if Instance.Parent == nil then
			if pcall(function()
				Instance.Parent = OriginalParent
			end) then
				DetachedInstances[Instance] = nil
			end
		else
			DetachedInstances[Instance] = nil
		end
	end
end

local function TrackInstanceForCleanup(Instance: Instance): ()
	if CleanupTracked[Instance] then
		return
	end
	CleanupTracked[Instance] = true
	Instance.Destroying:Once(function()
		ProcessedInstances[Instance] = nil
		OriginalProperties[Instance] = nil
		PropertyCategories[Instance] = nil
		DetachedInstances[Instance] = nil
		CleanupTracked[Instance] = nil
		local Categories = InstanceCategories[Instance]
		if Categories then
			for _, Category in ipairs(Categories) do
				local Members = CategoryMembers[Category]
				if Members then
					Members[Instance] = nil
				end
			end
			InstanceCategories[Instance] = nil
		end
	end)
end

-- distance
local DistanceOptimizer = {}

local DistanceThreshold = DefaultDistanceThreshold

local DistanceCandidates: { [Instance]: BasePart } = NewWeakKeyTable()
local DistanceHiddenState: { [Instance]: boolean } = NewWeakKeyTable()
local DistanceCandidateCategory: { [Instance]: string } = NewWeakKeyTable()

local DistanceAccumulatedTime = 0
local CurrentRootPart: BasePart? = nil

function DistanceOptimizer.SetThreshold(Studs: number): ()
	DistanceThreshold = Studs
end

function DistanceOptimizer.RegisterCandidate(Candidate: BasePart, Category: string): ()
	DistanceCandidates[Candidate] = Candidate
	DistanceCandidateCategory[Candidate] = Category
end

function DistanceOptimizer.UnregisterCandidate(Instance: Instance): ()
	DistanceCandidates[Instance] = nil
	DistanceHiddenState[Instance] = nil
	DistanceCandidateCategory[Instance] = nil
end

function DistanceOptimizer.UnregisterCategory(Category: string): ()
	for Instance, CandidateCategory in pairs(DistanceCandidateCategory) do
		if CandidateCategory == Category then
			DistanceCandidates[Instance] = nil
			DistanceHiddenState[Instance] = nil
			DistanceCandidateCategory[Instance] = nil
		end
	end
end

function DistanceOptimizer.UpdateRootPart(Character: Model?): ()
	if not Character then
		CurrentRootPart = nil
		return
	end
	local RootPart = Character:FindFirstChild("HumanoidRootPart")
	CurrentRootPart = if RootPart and RootPart:IsA("BasePart") then (RootPart :: BasePart) else nil
	if not CurrentRootPart then
		local Connection: RBXScriptConnection
		Connection = Character.ChildAdded:Connect(function(Child: Instance)
			if Child.Name == "HumanoidRootPart" and Child:IsA("BasePart") then
				CurrentRootPart = Child :: BasePart
				Connection:Disconnect()
			end
		end)
		table.insert(ActiveConnections, Connection)
	end
end

function DistanceOptimizer.ProcessTick(DeltaTime: number): ()
	if next(DistanceCandidates) == nil then
		return
	end
	DistanceAccumulatedTime += DeltaTime
	if DistanceAccumulatedTime < DistanceCheckInterval then
		return
	end
	DistanceAccumulatedTime = 0
	local RootPart = CurrentRootPart
	if not RootPart then
		return
	end
	local Origin = RootPart.Position
	local ThresholdSquared = DistanceThreshold * DistanceThreshold
	for Instance, Candidate in pairs(DistanceCandidates) do
		local Delta = Candidate.Position - Origin
		local DistanceSquared = Delta.X * Delta.X + Delta.Y * Delta.Y + Delta.Z * Delta.Z
		local IsFar = DistanceSquared > ThresholdSquared
		local IsHidden = DistanceHiddenState[Instance] == true
		if IsFar and not IsHidden then
			local Category = DistanceCandidateCategory[Instance] or "Distance"
			CacheOriginalProperty(Candidate, "LocalTransparencyModifier", Candidate.LocalTransparencyModifier, Category)
			SetPropertySafely(Candidate, "LocalTransparencyModifier", 1)
			DistanceHiddenState[Instance] = true
		elseif not IsFar and IsHidden then
			local Properties = OriginalProperties[Candidate]
			local OriginalTransparency = (Properties and Properties.LocalTransparencyModifier) or 0
			SetPropertySafely(Candidate, "LocalTransparencyModifier", OriginalTransparency)
			DistanceHiddenState[Instance] = nil
		end
	end
end

function DistanceOptimizer.Reset(): ()
	DistanceCandidates = NewWeakKeyTable()
	DistanceHiddenState = NewWeakKeyTable()
	DistanceCandidateCategory = NewWeakKeyTable()
	DistanceAccumulatedTime = 0
end

local function MakeToggleHandler(SettingKey: string, Category: string): (Instance) -> ()
	return function(Instance: Instance)
		if not (ActiveSettings :: any)[SettingKey] then
			return
		end
		local Current = (Instance :: any).Enabled
		if typeof(Current) ~= "boolean" then
			return
		end
		CacheOriginalProperty(Instance, "Enabled", Current, Category)
		SetPropertySafely(Instance, "Enabled", false)
	end
end

-- category
local CategoryHandlers: { [string]: (Instance) -> () } = {}

CategoryHandlers.Particles = MakeToggleHandler("DisableParticles", "Particles")
CategoryHandlers.Highlights = MakeToggleHandler("DisableHighlights", "Highlights")
CategoryHandlers.PostEffects = MakeToggleHandler("DisablePostEffects", "PostEffects")

CategoryHandlers.Atmosphere = function(Instance: Instance)
	if ActiveSettings.DisableAtmosphere then
		DetachInstance(Instance)
	end
end

CategoryHandlers.SurfaceAppearances = function(Instance: Instance)
	if ActiveSettings.DetachSurfaceAppearances then
		DetachInstance(Instance)
	end
end

CategoryHandlers.Decorative = function(Instance: Instance)
	if not ActiveSettings.HideTaggedDecorative then
		return
	end
	if not HasDecorativeTag(Instance) then
		return
	end
	if Instance:IsA("BasePart") then
		DistanceOptimizer.UnregisterCandidate(Instance)
		HideInstanceLocally(Instance, "Decorative")
	elseif Instance:IsA("Decal") or Instance:IsA("Texture") then
		local Current = (Instance :: any).Transparency
		CacheOriginalProperty(Instance, "Transparency", Current, "Decorative")
		SetPropertySafely(Instance, "Transparency", 1)
	end
end

CategoryHandlers.Meshes = function(Instance: Instance)
	if not ActiveSettings.OptimizeMeshes then
		return
	end
	if not Instance:IsA("MeshPart") then
		return
	end
	local MeshPart = Instance :: MeshPart
	if MeshPart.CanCollide then
		return
	end
	DistanceOptimizer.RegisterCandidate(MeshPart, "Meshes")
end

CategoryHandlers.Materials = function(Instance: Instance)
	if not ActiveSettings.OptimizeMaterials then
		return
	end
	if not Instance:IsA("BasePart") then
		return
	end
	local BasePart = Instance :: BasePart
	if BasePart.CanCollide then
		return
	end
	if not ExpensiveMaterials[BasePart.Material.Name] then
		return
	end
	CacheOriginalProperty(Instance, "Material", BasePart.Material, "Materials")
	SetPropertySafely(Instance, "Material", Enum.Material.SmoothPlastic)
end

CategoryHandlers.Reflectance = function(Instance: Instance)
	if not ActiveSettings.OptimizeReflectance then
		return
	end
	if not Instance:IsA("BasePart") then
		return
	end
	local BasePart = Instance :: BasePart
	if BasePart.Reflectance <= 0 then
		return
	end
	CacheOriginalProperty(Instance, "Reflectance", BasePart.Reflectance, "Reflectance")
	SetPropertySafely(Instance, "Reflectance", 0)
end

CategoryHandlers.Shadows = function(Instance: Instance)
	if not ActiveSettings.DisableShadows then
		return
	end
	if not Instance:IsA("BasePart") then
		return
	end
	local BasePart = Instance :: BasePart
	CacheOriginalProperty(Instance, "CastShadow", BasePart.CastShadow, "Shadows")
	SetPropertySafely(Instance, "CastShadow", false)
end

CategoryHandlers.Distance = function(Instance: Instance)
	if not ActiveSettings.DistanceOptimization then
		return
	end
	if ActiveSettings.HideTaggedDecorative then
		return
	end
	if not Instance:IsA("BasePart") then
		return
	end
	if not HasDecorativeTag(Instance) then
		return
	end
	DistanceOptimizer.RegisterCandidate(Instance :: BasePart, "Distance")
end

CategoryHandlers.Lights = function(Instance: Instance)
	if not ActiveSettings.DisableLights then
		return
	end
	if not Instance:IsA("Light") then
		return
	end
	if EffectiveMode == "Extreme" then
		local Current = (Instance :: any).Enabled
		if typeof(Current) == "boolean" then
			CacheOriginalProperty(Instance, "Enabled", Current, "Lights")
			SetPropertySafely(Instance, "Enabled", false)
		end
		return
	end
	if EffectiveMode == "Medium" then
		local Brightness = (Instance :: any).Brightness
		if typeof(Brightness) == "number" then
			CacheOriginalProperty(Instance, "Brightness", Brightness, "Lights")
			SetPropertySafely(Instance, "Brightness", Brightness * LightBrightnessMultiplier)
		end
		local Range = (Instance :: any).Range
		if typeof(Range) == "number" then
			CacheOriginalProperty(Instance, "Range", Range, "Lights")
			SetPropertySafely(Instance, "Range", Range * LightRangeMultiplier)
		end
	end
end

CategoryHandlers.Guis = function(Instance: Instance)
	if not ActiveSettings.OptimizeGuis then
		return
	end
	if not HasDecorativeTag(Instance) then
		return
	end
	if Instance:IsA("BillboardGui") or Instance:IsA("SurfaceGui") then
		local Current = (Instance :: any).Enabled
		CacheOriginalProperty(Instance, "Enabled", Current, "Guis")
		SetPropertySafely(Instance, "Enabled", false)
	elseif Instance:IsA("VideoFrame") then
		local Current = (Instance :: any).Playing
		CacheOriginalProperty(Instance, "Playing", Current, "Guis")
		SetPropertySafely(Instance, "Playing", false)
	elseif Instance:IsA("ViewportFrame") then
		local Current = (Instance :: any).Visible
		CacheOriginalProperty(Instance, "Visible", Current, "Guis")
		SetPropertySafely(Instance, "Visible", false)
	end
end

local ExactCategoryByClassName: { [string]: string } = {
	ParticleEmitter = "Particles",
	Trail = "Particles",
	Beam = "Particles",
	Smoke = "Particles",
	Fire = "Particles",
	Sparkles = "Particles",
	Highlight = "Highlights",
	BloomEffect = "PostEffects",
	SunRaysEffect = "PostEffects",
	ColorCorrectionEffect = "PostEffects",
	DepthOfFieldEffect = "PostEffects",
	BlurEffect = "PostEffects",
	Atmosphere = "Atmosphere",
	SurfaceAppearance = "SurfaceAppearances",
}

local BuiltinOptimizers: { [string]: boolean } = {
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	Smoke = true,
	Fire = true,
	Sparkles = true,
	Highlight = true,
	BloomEffect = true,
	SunRaysEffect = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	BlurEffect = true,
	Atmosphere = true,
	SurfaceAppearance = true,
	Decal = true,
	Texture = true,
	MeshPart = true,
	BasePart = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
	Light = true,
	BillboardGui = true,
	SurfaceGui = true,
	VideoFrame = true,
	ViewportFrame = true,
}

local CustomOptimizers: { [string]: (Instance) -> () } = {}

-- auto
local AutoModeController = {}

local AutoPendingTier: NoRenderTier? = nil
local AutoPendingStreak = 0
local AutoTimeSinceSwitch = math.huge

local function ClassifyFps(AverageFps: number): NoRenderTier
	if AverageFps >= AutoFpsThresholdLow then
		return "Low"
	elseif AverageFps >= AutoFpsThresholdMedium then
		return "Medium"
	end
	return "Extreme"
end

local ApplyEffectiveTier: (NoRenderTier) -> ()

function AutoModeController.Evaluate(AverageFps: number): ()
	AutoTimeSinceSwitch += AutoSampleInterval
	local Candidate = ClassifyFps(AverageFps)
	if Candidate == EffectiveMode then
		AutoPendingTier = nil
		AutoPendingStreak = 0
		return
	end
	if AutoPendingTier == Candidate then
		AutoPendingStreak += 1
	else
		AutoPendingTier = Candidate
		AutoPendingStreak = 1
	end
	local HasEnoughSamples = AutoPendingStreak >= AutoRequiredSamples
	local CooldownElapsed = AutoTimeSinceSwitch >= AutoMinSwitchInterval
	if HasEnoughSamples and CooldownElapsed then
		ApplyEffectiveTier(Candidate)
		AutoTimeSinceSwitch = 0
		AutoPendingTier = nil
		AutoPendingStreak = 0
	end
end

function AutoModeController.Reset(): ()
	AutoPendingTier = nil
	AutoPendingStreak = 0
	AutoTimeSinceSwitch = math.huge
end

-- other utilities
local function GetOptimizationRoots(): { Instance }
	local Roots: { Instance } = { workspace, Lighting }
	local Player = Players.LocalPlayer
	if Player then
		table.insert(Roots, Player)
	end
	return Roots
end

local function RegisterCategoryMember(Instance: Instance, Category: string): ()
	local Members = CategoryMembers[Category]
	if not Members then
		Members = NewWeakKeyTable()
		CategoryMembers[Category] = Members
	end
	Members[Instance] = true
end

local function DispatchInstance(Instance: Instance): ()
	if ProcessedInstances[Instance] then
		return
	end
	if Instance.Parent == nil then
		return
	end
	if ShouldSkipInstance(Instance) then
		return
	end
	ProcessedInstances[Instance] = true
	TrackInstanceForCleanup(Instance)
	LastOptimizationTime = os.clock()
	local Categories: { string } = {}
	local ExactCategory = ExactCategoryByClassName[Instance.ClassName]
	if ExactCategory then
		table.insert(Categories, ExactCategory)
	end
	if Instance:IsA("Decal") or Instance:IsA("Texture") then
		table.insert(Categories, "Decorative")
	end
	if Instance:IsA("BasePart") then
		if Instance:IsA("MeshPart") then
			table.insert(Categories, "Meshes")
		end
		table.insert(Categories, "Materials")
		table.insert(Categories, "Reflectance")
		table.insert(Categories, "Shadows")
		table.insert(Categories, "Decorative")
		table.insert(Categories, "Distance")
	end
	if Instance:IsA("Light") then
		table.insert(Categories, "Lights")
	end
	if Instance:IsA("BillboardGui") or Instance:IsA("SurfaceGui") or Instance:IsA("VideoFrame") or Instance:IsA("ViewportFrame") then
		table.insert(Categories, "Guis")
	end
	InstanceCategories[Instance] = Categories
	for _, Category in ipairs(Categories) do
		RegisterCategoryMember(Instance, Category)
		local Handler = CategoryHandlers[Category]
		if Handler then
			Handler(Instance)
		end
	end
	local Custom = CustomOptimizers[Instance.ClassName]
	if Custom then
		Custom(Instance)
	end
end

local function RunBatchedScan(): ()
	ScanGeneration += 1
	local Generation = ScanGeneration
	local StartTime = os.clock()
	task.spawn(function()
		local BatchStart = os.clock()
		for _, Root in ipairs(GetOptimizationRoots()) do
			if Generation ~= ScanGeneration then
				return
			end
			for _, Descendant in ipairs(Root:GetDescendants()) do
				if Generation ~= ScanGeneration then
					return
				end
				DispatchInstance(Descendant)
				if os.clock() - BatchStart >= ScanBudget then
					task.wait()
					BatchStart = os.clock()
				end
			end
		end
		if Generation == ScanGeneration then
			LastScanDuration = os.clock() - StartTime
		end
	end)
end

local function HookDescendantAdded(): ()
	for _, Root in ipairs(GetOptimizationRoots()) do
		local Connection = Root.DescendantAdded:Connect(function(Descendant: Instance)
			task.defer(DispatchInstance, Descendant)
		end)
		table.insert(ActiveConnections, Connection)
	end
end

local function ConnectFrameEvent(Callback: (number) -> ()): RBXScriptConnection
	local Success, Connection = pcall(function()
		return RunService.PreRender:Connect(Callback)
	end)
	if Success then
		return Connection :: RBXScriptConnection
	end
	return RunService.Heartbeat:Connect(Callback)
end

-- frames
local FrameCount = 0
local FrameAccumulatedTime = 0
local LastAverageFps = 0

local function SampleFrame(DeltaTime: number): ()
	FrameCount += 1
	FrameAccumulatedTime += DeltaTime
	DistanceOptimizer.ProcessTick(DeltaTime)
	if FrameAccumulatedTime >= AutoSampleInterval then
		LastAverageFps = FrameCount / FrameAccumulatedTime
		FrameCount = 0
		FrameAccumulatedTime = 0
		if CurrentMode == "Auto" then
			AutoModeController.Evaluate(LastAverageFps)
		end
	end
end

local function HookFrameEvent(): ()
	local Connection = ConnectFrameEvent(SampleFrame)
	table.insert(ActiveConnections, Connection)
end

local function InitializeCharacterTracking(): ()
	local Player = Players.LocalPlayer
	if not Player then
		return
	end
	if Player.Character then
		DistanceOptimizer.UpdateRootPart(Player.Character)
	end
	local Connection = Player.CharacterAdded:Connect(function(Character: Model)
		DistanceOptimizer.UpdateRootPart(Character)
	end)
	table.insert(ActiveConnections, Connection)
end

local function TryUnlockFrameRate(): ()
	if typeof(setfps) == "function" then
		pcall(setfps, math.huge)
	end
end

-- actual no rendering functions
local function ComputeActiveSettings(): OptimizationSettings
	local Merged = table.clone(ModeSettings[EffectiveMode])
	for Key, Value in pairs(ManualOverrides) do
		(Merged :: any)[Key] = Value
	end
	return Merged
end

local function RestoreCategory(Category: string): ()
	for Instance, Properties in pairs(OriginalProperties) do
		local Categories = PropertyCategories[Instance]
		if Categories then
			for PropertyName in pairs(Properties) do
				if Categories[PropertyName] == Category then
					if SetPropertySafely(Instance, PropertyName, Properties[PropertyName]) then
						Properties[PropertyName] = nil
						Categories[PropertyName] = nil
					end
				end
			end
			if next(Categories) == nil then
				PropertyCategories[Instance] = nil
			end
		end
		if next(Properties) == nil then
			OriginalProperties[Instance] = nil
		end
	end
	if Category == "Atmosphere" or Category == "SurfaceAppearances" then
		local TargetClassName = if Category == "Atmosphere" then "Atmosphere" else "SurfaceAppearance"
		for Instance, OriginalParent in pairs(DetachedInstances) do
			if Instance.ClassName == TargetClassName then
				if Instance.Parent == nil then
					if pcall(function()
						Instance.Parent = OriginalParent
					end) then
						DetachedInstances[Instance] = nil
					end
				else
					DetachedInstances[Instance] = nil
				end
			end
		end
	end
	if Category == "Distance" or Category == "Meshes" then
		DistanceOptimizer.UnregisterCategory(Category)
	end
end

local function ApplyCategory(Category: string): ()
	local Members = CategoryMembers[Category]
	if not Members then
		return
	end
	local Handler = CategoryHandlers[Category]
	if not Handler then
		return
	end
	for Instance in pairs(Members) do
		if Instance.Parent ~= nil then
			Handler(Instance)
		end
	end
end

local function ReconcileSettings(NewSettings: OptimizationSettings, ForcedCategories: { string }?): ()
	local Changed: { [string]: boolean } = {}
	for Category, Key in pairs(CategorySettingKeys) do
		if (ActiveSettings :: any)[Key] ~= (NewSettings :: any)[Key] then
			Changed[Category] = true
		end
	end
	if ForcedCategories then
		for _, Category in ipairs(ForcedCategories) do
			Changed[Category] = true
		end
	end

	for Category in pairs(Changed) do
		RestoreCategory(Category)
	end
	ActiveSettings = NewSettings
	if Enabled then
		for Category in pairs(Changed) do
			if (NewSettings :: any)[CategorySettingKeys[Category]] then
				ApplyCategory(Category)
			end
		end
	end
end

ApplyEffectiveTier = function(Tier: NoRenderTier): ()
	EffectiveMode = Tier
	local NewSettings = ComputeActiveSettings()
	ReconcileSettings(NewSettings, { "Lights" })
end

local function RestoreAllTrackedInstances(): ()
	local ToRestore: { [Instance]: boolean } = {}
	for Instance in pairs(OriginalProperties) do
		ToRestore[Instance] = true
	end
	for Instance in pairs(DetachedInstances) do
		ToRestore[Instance] = true
	end
	for Instance in pairs(ToRestore) do
		RestoreInstanceFully(Instance)
	end
end

local function DisconnectAllConnections(): ()
	for _, Connection in ipairs(ActiveConnections) do
		Connection:Disconnect()
	end
	table.clear(ActiveConnections)
end

local function PerformFullCleanup(): ()
	ScanGeneration += 1
	DisconnectAllConnections()
	RestoreAllTrackedInstances()
	ProcessedInstances = NewWeakKeyTable()
	PropertyCategories = NewWeakKeyTable()
	CategoryMembers = {}
	InstanceCategories = NewWeakKeyTable()
	DistanceOptimizer.Reset()
	AutoModeController.Reset()
end

-- NoRender API's
local NoRender = {}

function NoRender:Enable(): ()
	assert(not Destroyed, "NoRender: Enable was called after Destroy")
	if Enabled then
		return
	end
	Enabled = true
	EnabledSince = os.clock()
	if CurrentMode ~= "Auto" then
		EffectiveMode = CurrentMode :: NoRenderTier
	end
	ActiveSettings = ComputeActiveSettings()
	TryUnlockFrameRate()
	InitializeCharacterTracking()
	HookDescendantAdded()
	HookFrameEvent()
	RunBatchedScan()
end

function NoRender:Disable(): ()
	if not Enabled then
		return
	end
	Enabled = false
	EnabledSince = nil
	PerformFullCleanup()
end

function NoRender:SetMode(Mode: NoRenderMode): ()
	assert(Mode == "Auto" or ModeSettings[Mode] ~= nil, "NoRender:SetMode received an invalid mode")
	if Mode == CurrentMode then
		return
	end
	CurrentMode = Mode
	local NewEffectiveMode: NoRenderTier = if Mode ~= "Auto" then (Mode :: NoRenderTier) else EffectiveMode
	AutoModeController.Reset()
	local ModeChanged = NewEffectiveMode ~= EffectiveMode
	EffectiveMode = NewEffectiveMode
	local NewSettings = ComputeActiveSettings()
	ReconcileSettings(NewSettings, if ModeChanged then { "Lights" } else nil)
end

function NoRender:SetConfig(Overrides: { [string]: boolean }): ()
	assert(typeof(Overrides) == "table", "NoRender:SetConfig expects a table")
	for Key, Value in pairs(Overrides) do
		assert(ValidConfigKeys[Key], "NoRender:SetConfig received an unknown setting")
		assert(typeof(Value) == "boolean", "NoRender:SetConfig values must be boolean")
		ManualOverrides[Key] = Value
	end
	local NewSettings = ComputeActiveSettings()
	ReconcileSettings(NewSettings)
end

function NoRender:SetDistanceThreshold(Studs: number): ()
	assert(typeof(Studs) == "number" and Studs > 0, "NoRender:SetDistanceThreshold expects a positive number")
	DistanceOptimizer.SetThreshold(Studs)
end

function NoRender:AddWhitelist(Instance: Instance): ()
	assert(typeof(Instance) == "Instance", "NoRender:AddWhitelist expects an Instance")
	Whitelist[Instance] = true
	if ProcessedInstances[Instance] then
		RestoreInstanceFully(Instance)
		ForgetInstanceTracking(Instance)
	end
end

function NoRender:RemoveWhitelist(Instance: Instance): ()
	Whitelist[Instance] = nil
	if Enabled and not ProcessedInstances[Instance] then
		DispatchInstance(Instance)
	end
end

function NoRender:AddBlacklist(Instance: Instance): ()
	assert(typeof(Instance) == "Instance", "NoRender:AddBlacklist expects an Instance")
	Blacklist[Instance] = true
	if Enabled and not ProcessedInstances[Instance] then
		DispatchInstance(Instance)
	end
end

function NoRender:RemoveBlacklist(Instance: Instance): ()
	Blacklist[Instance] = nil
end

function NoRender:RegisterOptimizer(ClassName: string, Handler: (Instance) -> ()): ()
	assert(typeof(ClassName) == "string" and #ClassName > 0, "NoRender:RegisterOptimizer expects a non-empty ClassName")
	assert(typeof(Handler) == "function", "NoRender:RegisterOptimizer expects a function")
	assert(not BuiltinOptimizers[ClassName], "NoRender:RegisterOptimizer cannot override a builtin optimizer")
	assert(not CustomOptimizers[ClassName], "NoRender:RegisterOptimizer already has an optimizer for this ClassName")
	CustomOptimizers[ClassName] = Handler
end

function NoRender:UnregisterOptimizer(ClassName: string): ()
	assert(not BuiltinOptimizers[ClassName], "NoRender:UnregisterOptimizer cannot remove a builtin optimizer")
	CustomOptimizers[ClassName] = nil
end

function NoRender:IsEnabled(): boolean
	return Enabled
end

function NoRender:GetStats(): { [string]: any }
	local OptimizedInstanceCount = 0
	for _ in pairs(ProcessedInstances) do
		OptimizedInstanceCount += 1
	end
	local CachedPropertyCount = 0
	for _ in pairs(OriginalProperties) do
		CachedPropertyCount += 1
	end
	local DetachedInstanceCount = 0
	for _ in pairs(DetachedInstances) do
		DetachedInstanceCount += 1
	end
	local OptimizationsPerSecond = 0
	if Enabled and EnabledSince then
		local Elapsed = os.clock() - EnabledSince
		if Elapsed > 0 then
			OptimizationsPerSecond = OptimizedInstanceCount / Elapsed
		end
	end
	return {
		OptimizedInstanceCount = OptimizedInstanceCount,
		CachedPropertyCount = CachedPropertyCount,
		DetachedInstanceCount = DetachedInstanceCount,
		ActiveConnectionCount = #ActiveConnections,
		CurrentMode = CurrentMode,
		EffectiveMode = EffectiveMode,
		Enabled = Enabled,
		LastOptimizationTime = LastOptimizationTime,
		AverageFps = LastAverageFps,
		LastScanDuration = LastScanDuration,
		OptimizationsPerSecond = OptimizationsPerSecond,
	}
end

function NoRender:Destroy(): ()
	if Destroyed then
		return
	end
	self:Disable()
	Destroyed = true
	ProcessedInstances = NewWeakKeyTable()
	OriginalProperties = NewWeakKeyTable()
	PropertyCategories = NewWeakKeyTable()
	DetachedInstances = {}
	Whitelist = NewWeakKeyTable()
	Blacklist = NewWeakKeyTable()
	CategoryMembers = {}
	InstanceCategories = NewWeakKeyTable()
	ManualOverrides = {}
end

return NoRender
