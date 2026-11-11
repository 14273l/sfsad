--[[
    Atarazia UI Library
    Design: supplied GUI-to-Lua export.
    API: NH-style Window -> Page -> SubPage -> Section.
    No HTTP downloads, external modules, or executor APIs are required.
    Optional executor file APIs enable named configuration files.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Atarazia must be loaded on the client")

local Environment = getgenv and getgenv() or _G
local Previous = Environment.AtaraziaLibrary
if Previous and Previous.Exit then
    Previous:Exit()
end

local Library = {
    Brand = "Atarazia",
    Flags = {},
    IgnoreFlags = {},
    SetFlags = {},
    MenuKeybind = tostring(Enum.KeyCode.RightShift),
    Directory = "Atarazia",
    Folders = { Assets = "/Assets", Configs = "/Configs" },
    Font = Font.new("rbxasset://fonts/families/Zekton.json"),
    FontSize = 12,
    Animation = { Time = 0.15, Style = "Quint", Direction = "Out" },
    Theme = {
        Background = Color3.fromRGB(34, 37, 40),
        Section = Color3.fromRGB(31, 34, 37),
        Element = Color3.fromRGB(34, 37, 40),
        Outline = Color3.fromRGB(63, 69, 75),
        Border = Color3.fromRGB(0, 0, 0),
        Accent = Color3.fromRGB(216, 235, 255),
        Text = Color3.fromRGB(255, 255, 255),
        ["Inactive Text"] = Color3.fromRGB(107, 117, 128),
        ["Hovered Element"] = Color3.fromRGB(43, 47, 51),
        ["Light Border"] = Color3.fromRGB(63, 69, 75),
        ["Border 2"] = Color3.fromRGB(0, 0, 0),
        Risky = Color3.fromRGB(255, 95, 95),
    },
    Connections = {},
    Threads = {},
    ActiveTweens = {},
    ThemeMap = {},
    OpenFrames = {},
    PopupRegistry = {},
    CleanupRegistry = {},
    Panels = {},
    Keybinds = {},
    LayoutRegistry = {},
    SettingsWidgets = {},
    WindowVisibilityBindings = {},
    VisibilityOwners = {},
    WindowOpenState = true,
    Destroyed = false,
    NextId = 0,
    Drag = nil,
    PickingKeybind = nil,
}
Library.__index = Library
Library.ThemingStuff = Library.ThemeMap

local function Option(Params, Key, Default)
    Params = Params or {}
    local Value = Params[Key]
    if Value == nil then
        Value = Params[Key:sub(1, 1):lower() .. Key:sub(2)]
    end
    if Value == nil then
        Value = Params[Key:lower()]
    end
    if Value == nil then
        return Default
    end
    return Value
end

local function Raw(Object)
    return type(Object) == "table" and Object.Instance or Object
end

local function Pointer(Input)
    if Input and Input.UserInputType == Enum.UserInputType.Touch then
        return Vector2.new(Input.Position.X, Input.Position.Y)
    end
    return UserInputService:GetMouseLocation()
end

local function Primary(Input)
    return Input.UserInputType == Enum.UserInputType.MouseButton1
        or Input.UserInputType == Enum.UserInputType.Touch
end

local function ScreenSize()
    if Library.Root and Library.Root.Instance.AbsoluteSize.X > 0 then
        return Library.Root.Instance.AbsoluteSize
    end
    local Camera = Workspace.CurrentCamera
    return Camera and Camera.ViewportSize or Vector2.new(1467, 820)
end

local function RootOrigin()
    return Library.Root and Library.Root.Instance.AbsolutePosition or Vector2.new(0, 0)
end

local function InBounds(Object, Position)
    Object = Raw(Object)
    if not Object or not Object.Parent or not Object:IsA("GuiObject") then
        return false
    end
    local Top, Size = Object.AbsolutePosition, Object.AbsoluteSize
    return Position.X >= Top.X and Position.Y >= Top.Y
        and Position.X <= Top.X + Size.X and Position.Y <= Top.Y + Size.Y
end

local function IsVisible(Object)
    Object = Raw(Object)
    while Object do
        if Object:IsA("GuiObject") and not Object.Visible then
            return false
        end
        if Object:IsA("ScreenGui") and not Object.Enabled then
            return false
        end
        Object = Object.Parent
    end
    return true
end

Library.SafeCall = function(Self, Callback, ...)
    if type(Callback) ~= "function" then
        return true
    end
    local Results = table.pack(pcall(Callback, ...))
    if not Results[1] then
        warn("[Atarazia] " .. tostring(Results[2]))
    end
    return table.unpack(Results, 1, Results.n)
end

Library.Connect = function(Self, Signal, Callback, Owner)
    assert(not Library.Destroyed, "Atarazia is unloaded")
    if type(Signal) == "string" then
        Signal = Self.Instance[Signal]
    end
    local Connection = Signal:Connect(function(...)
        if not Library.Destroyed then
            Callback(...)
        end
    end)
    Library.Connections[Connection] = Raw(Owner) or Self.Instance or true
    return Connection
end

Library.Disconnect = function(Self, Connection)
    if Connection then
        Connection:Disconnect()
        Library.Connections[Connection] = nil
    end
end

Library.RegisterCleanup = function(Self, Owner, Callback)
    Owner = Raw(Owner)
    local Callbacks = Library.CleanupRegistry[Owner]
    if not Callbacks then
        Callbacks = {}
        Library.CleanupRegistry[Owner] = Callbacks
        Library:Connect(Owner.Destroying, function()
            local Pending = Library.CleanupRegistry[Owner]
            Library.CleanupRegistry[Owner] = nil
            for _, Cleanup in ipairs(Pending or {}) do
                Cleanup()
            end
        end, Owner)
    end
    table.insert(Callbacks, Callback)
end

local function RegisterFlag(Name, Owner, Setter)
    Library.SetFlags[Name] = Setter
    Library:RegisterCleanup(Owner, function()
        if Library.SetFlags[Name] == Setter then
            Library.SetFlags[Name], Library.Flags[Name] = nil, nil
        end
    end)
end

Library.Thread = function(Self, Callback, ...)
    local Arguments = table.pack(...)
    local Thread = task.defer(function()
        Library:SafeCall(Callback, table.unpack(Arguments, 1, Arguments.n))
        Library.Threads[coroutine.running()] = nil
    end)
    Library.Threads[Thread] = true
    return Thread
end

Library.Delay = function(Self, Seconds, Callback)
    local Thread = task.delay(math.max(Seconds, 0), function()
        Library.Threads[coroutine.running()] = nil
        if not Library.Destroyed then
            Library:SafeCall(Callback)
        end
    end)
    Library.Threads[Thread] = true
    return Thread
end

Library.Create = function(Self, Class, Properties)
    assert(not Library.Destroyed, "Atarazia is unloaded")
    Properties = Properties or {}
    local Object = Instance.new(Class)
    if Object:IsA("GuiObject") then
        Object.BorderSizePixel = 0
        Object.BackgroundColor3 = Library.Theme.Element
    end
    if Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("TextBox") then
        Object.FontFace = Library.Font
        Object.TextSize = Library.FontSize
        Object.TextColor3 = Library.Theme.Text
        Object.TextStrokeTransparency = 0
        Object.TextStrokeColor3 = Library.Theme.Border
        Object.Text = ""
    end
    if Object:IsA("GuiButton") then
        Object.AutoButtonColor = false
    end
    for Key, Value in pairs(Properties) do
        if Key ~= "Parent" then
            Object[Key] = Value
        end
    end
    Object.Parent = Raw(Properties.Parent)
    return setmetatable({ Instance = Object, Class = Class, Properties = Properties }, Library)
end

local function ThemeValue(Value)
    if type(Value) == "function" then
        return Value()
    end
    return Library.Theme[Value] or Value
end

Library.AddToTheme = function(Self, Properties)
    local Data = Library.ThemeMap[Self.Instance] or {}
    for Property, Value in pairs(Properties) do
        Data[Property] = Value
        Self.Instance[Property] = ThemeValue(Value)
    end
    Library.ThemeMap[Self.Instance] = Data
    return Self
end
Library.ChangeItemTheme = Library.AddToTheme

Library.ChangeTheme = function(Self, Key, Color)
    assert(typeof(Color) == "Color3", "Theme colors must be Color3 values")
    Library.Theme[Key] = Color
    for Object, Properties in pairs(Library.ThemeMap) do
        if not Object.Parent then
            Library.ThemeMap[Object] = nil
        else
            for Property, Value in pairs(Properties) do
                if Value == Key or type(Value) == "function" then
                    Object[Property] = ThemeValue(Value)
                end
            end
        end
    end
end

Library.Tween = function(Self, Properties, Info, IsRawItem)
    local Object = Self.Instance or Raw(IsRawItem)
    if not Object or Library.Destroyed then
        return
    end
    Info = Info or TweenInfo.new(Library.Animation.Time,
        Enum.EasingStyle[Library.Animation.Style], Enum.EasingDirection[Library.Animation.Direction])
    local Tween = TweenService:Create(Object, Info, Properties)
    Library.ActiveTweens[Tween] = Object
    local Completed
    Completed = Tween.Completed:Connect(function()
        Library.ActiveTweens[Tween] = nil
        Completed:Disconnect()
    end)
    Tween:Play()
    return Tween
end

Library.GetTweenProperty = function(Self, IsRawItem)
    local Object = Self.Instance or Raw(IsRawItem)
    local Properties = {}
    if Object:IsA("GuiObject") then
        table.insert(Properties, "BackgroundTransparency")
    end
    if Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("TextBox") then
        table.insert(Properties, "TextTransparency")
        table.insert(Properties, "TextStrokeTransparency")
    elseif Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
        table.insert(Properties, "ImageTransparency")
    elseif Object:IsA("UIStroke") then
        table.insert(Properties, "Transparency")
    elseif Object:IsA("ScrollingFrame") then
        table.insert(Properties, "ScrollBarImageTransparency")
    end
    return Properties
end

local FadeValues = setmetatable({}, { __mode = "k" })
Library.Fade = function(Self, Property, Visibility, IsRawItem)
    local Object = Self.Instance or Raw(IsRawItem)
    local Saved = FadeValues[Object] or {}
    if Saved[Property] == nil then
        Saved[Property] = Object[Property]
    end
    FadeValues[Object] = Saved
    return Library:Tween({ [Property] = Visibility and Saved[Property] or 1 }, nil, Object)
end

Library.FadeDescendants = function(Self, Visibility, Callback)
    Self.FadeVersion = (Self.FadeVersion or 0) + 1
    local Version = Self.FadeVersion
    Self.Instance.Visible = true
    local Objects = Self.Instance:GetDescendants()
    table.insert(Objects, Self.Instance)
    for _, Object in ipairs(Objects) do
        for _, Property in ipairs(Library:GetTweenProperty(Object)) do
            Library:Fade(Property, Visibility, Object)
        end
    end
    Library:Delay(Library.Animation.Time, function()
        if Version == Self.FadeVersion and Self.Instance.Parent then
            Self.Instance.Visible = Visibility
            Library:SafeCall(Callback)
        end
    end)
end

Library.Destroy = function(Self)
    local Object = Self.Instance
    if not Object then
        return
    end
    local Attached = {}
    for PopupData in pairs(Library.PopupRegistry) do
        local Anchor = PopupData.AttachedButton
        if Anchor == Object or Anchor:IsDescendantOf(Object) then
            table.insert(Attached, PopupData)
        end
    end
    for _, PopupData in ipairs(Attached) do
        Library.PopupRegistry[PopupData] = nil
        PopupData:SetOpen(false)
        PopupData.Item:Destroy()
    end
    local CleanupOwners = {}
    for Owner in pairs(Library.CleanupRegistry) do
        if Owner == Object or Owner:IsDescendantOf(Object) then
            table.insert(CleanupOwners, Owner)
        end
    end
    for _, Owner in ipairs(CleanupOwners) do
        local Callbacks = Library.CleanupRegistry[Owner]
        Library.CleanupRegistry[Owner] = nil
        for _, Callback in ipairs(Callbacks or {}) do
            Callback()
        end
    end
    for Connection, Owner in pairs(Library.Connections) do
        if typeof(Owner) == "Instance" and (Owner == Object or Owner:IsDescendantOf(Object)) then
            Library:Disconnect(Connection)
        end
    end
    for Item in pairs(Library.ThemeMap) do
        if Item == Object or Item:IsDescendantOf(Object) then
            Library.ThemeMap[Item] = nil
        end
    end
    for Tween, Target in pairs(Library.ActiveTweens) do
        if Target == Object or Target:IsDescendantOf(Object) then
            Tween:Cancel()
        end
    end
    Object:Destroy()
end

local function Frame(Parent, Name, Size, Position, Theme)
    local Item = Library:Create("Frame", {
        Name = Name, Parent = Parent, Size = Size or UDim2.fromScale(1, 1),
        Position = Position or UDim2.new(), BackgroundTransparency = Theme and 0 or 1,
    })
    if Theme then
        Item:AddToTheme({ BackgroundColor3 = Theme })
    end
    return Item
end

local function Text(Parent, Name, Value, Size, Position, Theme)
    return Library:Create("TextLabel", {
        Name = Name, Parent = Parent, Text = tostring(Value or ""),
        Size = Size or UDim2.fromScale(1, 1), Position = Position or UDim2.new(),
        BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
    }):AddToTheme({ TextColor3 = Theme or "Text" })
end

local function Button(Parent, Name, Value, Size, Position, Theme)
    local Item = Library:Create("TextButton", {
        Name = Name, Parent = Parent, Text = tostring(Value or ""),
        Size = Size or UDim2.fromScale(1, 1), Position = Position or UDim2.new(),
        BackgroundTransparency = Theme and 0 or 1, TextTruncate = Enum.TextTruncate.AtEnd,
    }):AddToTheme({ TextColor3 = "Text" })
    if Theme then
        Item:AddToTheme({ BackgroundColor3 = Theme })
    end
    return Item
end

local function Border(Item, Double)
    Library:Create("UIStroke", {
        Name = "Outline", Parent = Item, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter, Thickness = 1,
    }):AddToTheme({ Color = Double == false and "Border" or "Outline" })
    if Double ~= false then
        local Stroke = Library:Create("UIStroke", {
            Name = "OuterBorder", Parent = Item, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            LineJoinMode = Enum.LineJoinMode.Miter,
        }):AddToTheme({ Color = "Border" })
        -- BorderOffset is not exposed by older Roblox clients.
        pcall(function()
            Stroke.Instance.BorderOffset = UDim.new(0, 1)
        end)
    end
end

local function List(Parent, Padding, Horizontal)
    return Library:Create("UIListLayout", {
        Parent = Parent, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, Padding or 8),
        FillDirection = Horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
    })
end

local function Padding(Parent, Amount)
    return Library:Create("UIPadding", {
        Parent = Parent, PaddingTop = UDim.new(0, Amount), PaddingBottom = UDim.new(0, Amount),
        PaddingLeft = UDim.new(0, Amount), PaddingRight = UDim.new(0, Amount),
    })
end

local function Scroll(Parent, Name, Size, Position, Amount)
    local Item = Library:Create("ScrollingFrame", {
        Name = Name, Parent = Parent, Size = Size or UDim2.fromScale(1, 1),
        Position = Position or UDim2.new(), BackgroundTransparency = 1,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.Y,
        Active = true,
    })
    Padding(Item, Amount or 3)
    List(Item, 8)
    return Item
end

local function ContentParent(Self, Params)
    local Parent = Option(Params, "Parent") or (Self.Items and Self.Items.Content)
    assert(Parent, "Create controls on a Section, section SubTab, or Toggle:Settings()")
    return Parent
end

local function Flag(Params, Name)
    local Value = Option(Params, "Flag")
    if Value ~= nil then
        assert(type(Value) == "string", "Flag must be a string")
        return Value
    end
    Library.NextId = Library.NextId + 1
    return tostring(Name or "Control") .. "_" .. Library.NextId
end

local function Control(Self, Params, Kind, Height)
    local Name = Option(Params, "Name", Kind)
    local Item = Frame(ContentParent(Self, Params), Kind .. "_Frame", UDim2.new(1, 0, 0, Height))
    local Data = setmetatable({
        Kind = Kind, Name = Name, Flag = Flag(Params, Name), Section = Self,
        Window = Self.Window, Page = Self.Page,
        Callback = Option(Params, "Callback"), Items = {}, Instance = Item.Instance,
    }, Library)
    Data.Items[Kind] = Item
    function Data:SetVisibility(Bool)
        Item.Instance.Visible = Bool == true
        if not Bool then
            Library:CloseOpenFrames(Item.Instance)
        end
        return self
    end
    function Data:SetText(Value)
        self.Name = tostring(Value)
        if self.Items.Text then
            self.Items.Text.Instance.Text = self.Name
        end
        return self
    end
    Item:Tooltip(Option(Params, "Tooltip"))
    return Data, Item
end

local function Commit(ControlData, Value, Silent)
    ControlData.Value = Value
    Library.Flags[ControlData.Flag] = type(Value) == "table" and table.clone(Value) or Value
    if not Silent then
        Library:SafeCall(ControlData.Callback, type(Value) == "table" and table.clone(Value) or Value)
    end
end

Library.OnHover = function(Self, Enter, Leave)
    if Enter then
        Self:Connect("MouseEnter", Enter)
    end
    if Leave then
        Self:Connect("MouseLeave", Leave)
    end
    return Self
end

Library.IsMouseOverFrame = function(Self)
    return InBounds(Self, Pointer())
end

Library.IsClipped = function(Self, Column)
    Column = Raw(Column)
    local Position, Size = Self.Instance.AbsolutePosition, Self.Instance.AbsoluteSize
    local Top, Bounds = Column.AbsolutePosition, Column.AbsoluteSize
    return Position.X < Top.X or Position.Y < Top.Y
        or Position.X + Size.X > Top.X + Bounds.X or Position.Y + Size.Y > Top.Y + Bounds.Y
end

Library.BindDrag = function(Self, Callback)
    Self:Connect("InputBegan", function(Input)
        if Primary(Input) and IsVisible(Self) and not Library.ActiveConfirmDialog then
            Library.Drag = { Input = Input, Update = Callback }
            Callback(Pointer(Input), true)
        end
    end)
    return Self
end

Library.MakeDraggable = function(Self, Handle)
    local Object, Start, Position = Self.Instance
    Handle = Handle or Self
    if typeof(Handle) == "Instance" then
        Handle = setmetatable({ Instance = Handle }, Library)
    end
    Handle:BindDrag(function(Point, Begin)
        if Begin then
            local Origin = RootOrigin()
            Position = Object.AbsolutePosition - Origin
            Object.AnchorPoint = Vector2.new(0, 0)
            Object.Position = UDim2.fromOffset(Position.X, Position.Y)
            Start = Point
        end
        local Delta, Size, Bounds = Point - Start, Object.AbsoluteSize, ScreenSize()
        Object.Position = UDim2.fromOffset(
            math.clamp(Position.X + Delta.X, 28, math.max(28, Bounds.X - Size.X - 3)),
            math.clamp(Position.Y + Delta.Y, 32, math.max(32, Bounds.Y - Size.Y - 3)))
    end)
    return Self
end

Library.MakeResizeable = function(Self, Minimum)
    local Object, Start, Size = Self.Instance
    Minimum = Minimum or Vector2.new(360, 320)
    local Grip = Button(Self, "ResizeGrip", "", UDim2.fromOffset(12, 12), UDim2.new(1, -12, 1, -12))
    Grip.Instance.ZIndex = 20
    Grip:BindDrag(function(Point, Begin)
        if Begin then
            Start, Size = Point, Object.AbsoluteSize
        end
        local Delta, Bounds = Point - Start, ScreenSize()
        local Position = Object.AbsolutePosition - RootOrigin()
        local MaxX, MaxY = math.max(80, Bounds.X - Position.X - 3), math.max(80, Bounds.Y - Position.Y - 3)
        Object.Size = UDim2.fromOffset(
            math.clamp(Size.X + Delta.X, math.min(Minimum.X, MaxX), MaxX),
            math.clamp(Size.Y + Delta.Y, math.min(Minimum.Y, MaxY), MaxY))
    end)
    return Self
end
Library.MakeResizable = Library.MakeResizeable

Library.Round = function(Self, Number, Step)
    Step = tonumber(Step) or 1
    if Step <= 0 then
        Step = 1
    end
    return math.round(Number / Step) * Step
end

-- Use PlayerGui in Studio; use gethui only when it is supplied by the host.
local Parent = LocalPlayer:WaitForChild("PlayerGui")
if gethui then
    local Success, Result = pcall(gethui)
    if Success and typeof(Result) == "Instance" then
        Parent = Result
    end
end
Library.Holder = Library:Create("ScreenGui", {
    Name = "Atarazia", Parent = Parent, IgnoreGuiInset = true,
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100,
})
Library.Root = Frame(Library.Holder, "Root", UDim2.fromScale(1, 1))
Library.PopupLayer = Frame(Library.Root, "PopupLayer", UDim2.fromScale(1, 1))
Library.PopupLayer.Instance.ZIndex = 100
Library.UnusedHolder = Library:Create("Folder", { Name = "Unused", Parent = Library.Holder })
Library.NotifHolder = Frame(Library.Root, "Notifications", UDim2.new(0, 300, 1, -45), UDim2.fromOffset(36, 42))
Library.NotifHolder.Instance.ZIndex = 200
List(Library.NotifHolder, 6)

Library.CloseOpenFrames = function(Self, Within)
    Within = Raw(Within)
    local Close = {}
    for Popup in pairs(Library.OpenFrames) do
        if not Within or Popup.AttachedButton == Within or Popup.AttachedButton:IsDescendantOf(Within) then
            table.insert(Close, Popup)
        end
    end
    for _, Popup in ipairs(Close) do
        Popup:SetOpen(false)
    end
end

local function PopupPosition(Popup)
    local Anchor, Panel, Origin = Popup.AttachedButton, Popup.Frame, RootOrigin()
    local Bounds, Size = ScreenSize(), Panel.AbsoluteSize
    local X = Anchor.AbsolutePosition.X - Origin.X
    local Y = Anchor.AbsolutePosition.Y - Origin.Y + Anchor.AbsoluteSize.Y + 4
    if Y + Size.Y > Bounds.Y - 3 then
        Y = Anchor.AbsolutePosition.Y - Origin.Y - Size.Y - 4
    end
    Panel.Position = UDim2.fromOffset(
        math.clamp(X, 3, math.max(3, Bounds.X - Size.X - 3)),
        math.clamp(Y, 32, math.max(32, Bounds.Y - Size.Y - 3)))
end

local function Popup(Anchor, Size, Name)
    local Item = Frame(Library.PopupLayer, Name, Size, nil, "Background")
    Border(Item)
    Item.Instance.Visible = false
    local Data = { AttachedButton = Raw(Anchor), Frame = Item.Instance, IsOpen = false, Item = Item }
    Library.PopupRegistry[Data] = true
    function Data:SetOpen(Bool)
        Bool = Bool == true and Library.WindowOpenState and IsVisible(self.AttachedButton)
        if Bool then
            if self.BeforeOpen then
                self.BeforeOpen()
            end
            -- Keep an ancestor settings popup open when a child dropdown opens.
            local Close = {}
            for Other in pairs(Library.OpenFrames) do
                if Other ~= self and not self.AttachedButton:IsDescendantOf(Other.Frame) then
                    table.insert(Close, Other)
                end
            end
            for _, Other in ipairs(Close) do
                Other:SetOpen(false)
            end
            Library.OpenFrames[self] = true
            self.Frame.Visible = true
            PopupPosition(self)
        else
            Library:CloseOpenFrames(self.Frame)
            Library.OpenFrames[self] = nil
            self.Frame.Visible = false
        end
        self.IsOpen = Bool
        if self.OnOpenChanged then
            self.OnOpenChanged(Bool)
        end
    end
    Anchor:Connect("Activated", function()
        Data:SetOpen(not Data.IsOpen)
    end)
    Anchor:Connect("Destroying", function()
        Library.PopupRegistry[Data] = nil
        Data:SetOpen(false)
        Item:Destroy()
    end)
    return Data, Item
end

Library.GlobalUpdateOpenFrames = function(Self)
    local Close = {}
    for PopupData in pairs(Library.OpenFrames) do
        local Anchor = PopupData.AttachedButton
        if not Anchor.Parent or not IsVisible(Anchor) then
            table.insert(Close, PopupData)
        else
            local Clipped = false
            local Ancestor = Anchor.Parent
            while Ancestor and Ancestor ~= Library.Root.Instance do
                if Ancestor:IsA("ScrollingFrame") then
                    local Top, Size = Ancestor.AbsolutePosition, Ancestor.AbsoluteWindowSize
                    local A, B = Anchor.AbsolutePosition, Anchor.AbsoluteSize
                    Clipped = A.Y < Top.Y or A.Y + B.Y > Top.Y + Size.Y
                    if Clipped then
                        break
                    end
                end
                Ancestor = Ancestor.Parent
            end
            if Clipped then
                table.insert(Close, PopupData)
            else
                PopupPosition(PopupData)
            end
        end
    end
    for _, PopupData in ipairs(Close) do
        PopupData:SetOpen(false)
    end
end

Library.BindToWindowVisibility = function(Self, Callback, Owner)
    table.insert(Library.WindowVisibilityBindings, Callback)
    Owner = Raw(Owner) or Self.Instance
    if Owner then
        Library.VisibilityOwners[Callback] = Owner
        Library:RegisterCleanup(Owner, function()
            Library.VisibilityOwners[Callback] = nil
            local Index = table.find(Library.WindowVisibilityBindings, Callback)
            if Index then
                table.remove(Library.WindowVisibilityBindings, Index)
            end
        end)
    end
    Library:SafeCall(Callback, Library.WindowOpenState)
    return Callback
end

Library.SetWindowVisibilityState = function(Self, Bool)
    Library.WindowOpenState = Bool == true
    Library.Drag = nil
    if not Bool then
        Library:CloseOpenFrames()
        if Library.PickingKeybind then
            Library.PickingKeybind:CancelPicking()
        end
        if Library.ActiveConfirmDialog then
            Library.ActiveConfirmDialog:Close(false)
        end
    end
    for _, Callback in ipairs(table.clone(Library.WindowVisibilityBindings)) do
        Library:SafeCall(Callback, Library.WindowOpenState)
    end
end

Library.Tooltip = function(Self, Data)
    if Data == nil then
        return Self
    end
    if type(Data) == "string" then
        Data = { Description = Data }
    end
    local TooltipItem
    local function Hide()
        if TooltipItem then
            TooltipItem:Destroy()
            TooltipItem = nil
        end
    end
    Self:OnHover(function()
        if not Library.WindowOpenState or not IsVisible(Self) then
            return
        end
        Hide()
        TooltipItem = Frame(Library.PopupLayer, "Tooltip", UDim2.fromOffset(230, 66), nil, "Background")
        TooltipItem.Instance.ZIndex = 50
        Border(TooltipItem)
        local Title = Option(Data, "Title", "")
        local Label = Text(TooltipItem, "Description", Option(Data, "Description", ""),
            UDim2.new(1, -14, 1, Title == "" and -10 or -27), UDim2.fromOffset(7, Title == "" and 5 or 22))
        Label.Instance.TextWrapped = true
        Label.Instance.TextXAlignment = Enum.TextXAlignment.Left
        Label.Instance.TextYAlignment = Enum.TextYAlignment.Top
        if Title ~= "" then
            Text(TooltipItem, "Title", Title, UDim2.new(1, -14, 0, 16), UDim2.fromOffset(7, 4),
                Data.Risky and "Risky" or "Accent").Instance.TextXAlignment = Enum.TextXAlignment.Left
        end
        local Point, Origin, Bounds = Pointer(), RootOrigin(), ScreenSize()
        TooltipItem.Instance.Position = UDim2.fromOffset(
            math.clamp(Point.X - Origin.X + 15, 3, math.max(3, Bounds.X - 233)),
            math.clamp(Point.Y - Origin.Y + 15, 32, math.max(32, Bounds.Y - 69)))
    end, Hide)
    Self:Connect("Destroying", Hide)
    Library:BindToWindowVisibility(function(Open)
        if not Open then
            Hide()
        end
    end, Self)
    return Self
end

-- Shared panel shell reproduces the export's square, double-bordered windows.
local function Panel(Params, Kind, DefaultSize, DefaultPosition)
    Params = Params or {}
    local Bounds = ScreenSize()
    local Size = Option(Params, "Size", DefaultSize)
    if typeof(Size) == "Vector2" then
        Size = UDim2.fromOffset(Size.X, Size.Y)
    end
    local Position = Option(Params, "Position", DefaultPosition)
    if typeof(Position) == "Vector2" then
        Position = UDim2.fromOffset(Position.X, Position.Y)
    end
    local Width = math.min(Size.X.Scale * Bounds.X + Size.X.Offset, math.max(100, Bounds.X - 36))
    local Height = math.min(Size.Y.Scale * Bounds.Y + Size.Y.Offset, math.max(100, Bounds.Y - 42))
    local X = Position.X.Scale * Bounds.X + Position.X.Offset
    local Y = Position.Y.Scale * Bounds.Y + Position.Y.Offset
    local Main = Frame(Library.Root, Kind .. "_Frame", UDim2.fromOffset(Width, Height),
        UDim2.fromOffset(math.clamp(X, 28, math.max(28, Bounds.X - Width - 3)),
            math.clamp(Y, 32, math.max(32, Bounds.Y - Height - 3))), "Background")
    Border(Main)
    local Title = Text(Main, "Title_Label", Option(Params, "Name", Kind), UDim2.new(1, -14, 0, 29),
        UDim2.fromOffset(7, 0), "Accent")
    Title.Instance.TextXAlignment = Enum.TextXAlignment.Left
    Title.Instance.Active = true
    Main:MakeDraggable(Title)
    local Accent = Frame(Main, "Highlight_Frame", UDim2.new(1, -14, 0, 1), UDim2.fromOffset(7, 30), "Accent")
    Border(Accent)
    local Data = setmetatable({
        Kind = Kind, Name = Option(Params, "Name", Kind), Visible = Option(Params, "Visible", true),
        Instance = Main.Instance, Items = { MainFrame = Main, Text = Title, AccentLiner = Accent },
    }, Library)
    function Data:ApplyVisibility()
        Main.Instance.Visible = self.Visible and Library.WindowOpenState
        if self.HeaderButton then
            self.HeaderButton:SetActive(Main.Instance.Visible)
        end
    end
    function Data:SetVisibility(Bool)
        self.Visible = Bool == true
        if not Bool then
            Library:CloseOpenFrames(Main.Instance)
        end
        self:ApplyVisibility()
        return self
    end
    function Data:SetText(Value)
        self.Name = tostring(Value or "")
        Title.Instance.Text = self.Name
        return self
    end
    function Data:SetPosition(Value)
        Main.Instance.AnchorPoint = Vector2.new(0, 0)
        Main.Instance.Position = Value
        return self
    end
    function Data:Center()
        local Screen, Extents = ScreenSize(), Main.Instance.AbsoluteSize
        return self:SetPosition(UDim2.fromOffset(math.max(28, (Screen.X - Extents.X) / 2),
            math.max(32, (Screen.Y - Extents.Y) / 2)))
    end
    function Data:GetBounds()
        return Main.Instance.AbsolutePosition, Main.Instance.AbsoluteSize
    end
    Library:BindToWindowVisibility(function()
        Data:ApplyVisibility()
    end, Main)
    table.insert(Library.Panels, Data)
    Library:RegisterLayout(Option(Params, "Id", Kind), {
        Instance = Main.Instance, SaveSize = true, MinimumSize = Vector2.new(100, 100),
    })
    return Data
end

local function AttachPanelButton(Data, Name)
    if not Library.TopBarData then
        return
    end
    Data.HeaderButton = Library.TopBarData:AddButton({
        Name = Name, Active = Data.Visible and Library.WindowOpenState,
        Callback = function()
            if Data == Library.MainWindow then
                Data:SetOpen(not Library.WindowOpenState)
            else
                if not Library.WindowOpenState then
                    Library.MainWindow:SetOpen(true)
                    Data:SetVisibility(true)
                else
                    Data:SetVisibility(not Data.Visible)
                end
            end
        end,
    })
end

Library.TopBar = function(Self, Params)
    if Library.TopBarData then
        return Library.TopBarData
    end
    Params = Params or {}
    local Top = Frame(Library.Root, "TopBar_Frame", UDim2.new(1, 0, 0, 26), nil, "Background")
    Top.Instance.ZIndex = 60
    Border(Top)
    local Holder = Library:Create("ScrollingFrame", {
        Name = "Buttons", Parent = Top, Size = UDim2.new(1, -10, 1, 0), Position = UDim2.fromOffset(5, 0),
        BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
    })
    local Layout = List(Holder, 5, true)
    Layout.Instance.VerticalAlignment = Enum.VerticalAlignment.Center
    Text(Holder, "Title_Label", Option(Params, "Name", "Atarazia"), UDim2.fromOffset(60, 26), nil, "Accent")
    Text(Holder, "Separator", "/", UDim2.fromOffset(15, 26))
    local Date = Text(Holder, "Date_Label", os.date("%A, %b %d"), UDim2.fromOffset(140, 26))
    Text(Holder, "Separator", "/", UDim2.fromOffset(15, 26))
    local Data = { Items = { TopBar = Top, Holder = Holder, Date = Date }, Buttons = {}, Visible = true }
    function Data:AddButton(Config)
        Config = Config or {}
        local Item = Button(Holder, "Header_Button", Option(Config, "Name", Option(Config, "Text", "Button")),
            UDim2.fromOffset(Option(Config, "Width", 65), 22))
        Border(Item)
        local New = { Active = Option(Config, "Active", false), Items = { Outline = Item, Text = Item },
            Callback = Option(Config, "Callback") }
        function New:SetActive(Bool)
            self.Active = Bool == true
            Item:AddToTheme({ TextColor3 = self.Active and "Accent" or "Inactive Text" })
        end
        function New:SetText(Value)
            Item.Instance.Text = tostring(Value)
        end
        function New:SetVisible(Bool)
            Item.Instance.Visible = Bool == true
        end
        function New:SetCallback(Callback)
            self.Callback = Callback
        end
        Item:Connect("Activated", function()
            Library:SafeCall(New.Callback, New)
        end)
        New:SetActive(New.Active)
        table.insert(self.Buttons, New)
        return New
    end
    function Data:SetVisibility(Bool)
        self.Visible = Bool == true
        Top.Instance.Visible = self.Visible
    end
    Library.TopBarData = Data
    Library:Thread(function()
        while not Library.Destroyed and Top.Instance.Parent do
            task.wait(60)
            if not Library.Destroyed and Top.Instance.Parent then
                Date.Instance.Text = os.date("%A, %b %d")
            end
        end
    end)
    return Data
end

Library.Window = function(Self, Params)
    assert(not Library.MainWindow, "Atarazia supports one main window per library instance")
    Params = Params or {}
    local Config = table.clone(Params)
    Config.Name = Option(Params, "Title", Option(Params, "Name", "Atarazia"))
    local Window = Panel(Config, "Window", Vector2.new(440, 575), UDim2.fromScale(0.35175, 0.14878))
    Window.Window = Window
    Window.Pages = {}
    Window.IsOpen = true
    Window.Items.Text.Instance.TextXAlignment = Enum.TextXAlignment.Center
    Library.MainWindow, Library.MainWindowFrame = Window, Window.Instance
    Window.Items.HeaderTitle = Window.Items.Text
    Window.Items.PagesOutline = Frame(Window.Items.MainFrame, "TabButtons_Frame", UDim2.new(1, -14, 0, 40),
        UDim2.fromOffset(7, 40), "Section")
    Border(Window.Items.PagesOutline)
    Window.Items.Content = Frame(Window.Items.MainFrame, "TabWindow_Frame", UDim2.new(1, -14, 1, -87),
        UDim2.fromOffset(7, 80), "Section")
    Border(Window.Items.Content)
    if Option(Params, "Resizable", true) then
        Window.Items.MainFrame:MakeResizeable(Vector2.new(360, 320))
    end
    if Option(Params, "TopBar", true) then
        Library:TopBar({ Name = Option(Params, "Brand", "Atarazia") })
        AttachPanelButton(Window, Option(Params, "ButtonName", "Home"))
    end
    if Option(Params, "Sidebar", true) then
        local Sidebar = Frame(Library.Root, "SideBarForTopBar_Frame", UDim2.new(0, 26, 1, -26),
            UDim2.fromOffset(0, 26), "Background")
        Border(Sidebar)
        Sidebar.Instance.ZIndex = 55
        Library:BindToWindowVisibility(function(Open)
            Sidebar.Instance.Visible = Open
        end, Sidebar)
        Window.Items.Sidebar = Sidebar
    end
    if Option(Params, "DesktopBackground", false) then
        local Backdrop = Frame(Library.Root, "DesktopBackground", nil, nil)
        Backdrop.Instance.BackgroundColor3 = Color3.fromRGB(171, 185, 204)
        Backdrop.Instance.BackgroundTransparency = 0
        Backdrop.Instance.ZIndex = 0
        Library:BindToWindowVisibility(function(Open)
            Backdrop.Instance.Visible = Open
        end, Backdrop)
    end
    local Image = Option(Params, "PreviewImage", "rbxassetid://71195216490355")
    if Image and Image ~= "" then
        Window.Items.PreviewImage = Library:Create("ImageLabel", {
            Name = "Preview_Image", Parent = Window.Items.MainFrame, Image = Image,
            Size = UDim2.fromOffset(100, 100), Position = UDim2.new(1, -107, 1, -107),
            BackgroundTransparency = 1, Active = false, ZIndex = 2,
        })
    end
    function Window:SetOpen(Bool)
        self.IsOpen = Bool == true
        self.Visible = true
        Library:SetWindowVisibilityState(self.IsOpen)
        self:ApplyVisibility()
    end
    function Window:SetTitle(Value)
        self:SetText(Value)
    end
    function Window:SetDockText(Value)
        if self.HeaderButton then
            self.HeaderButton:SetText(Value)
        end
    end
    function Window:AddHeaderButton(ConfigData)
        return Library:TopBar():AddButton(ConfigData)
    end
    Window:SetOpen(Option(Params, "Open", true))
    return Window
end

local function EqualButtons(Buttons, Height)
    for Index, Item in ipairs(Buttons) do
        Item.Instance.Position = UDim2.new((Index - 1) / #Buttons, 0, 0, 0)
        Item.Instance.Size = UDim2.new(1 / #Buttons, 0, 0, Height)
    end
end

local function Columns(Parent)
    local Left = Scroll(Parent, "LeftMiniTab_Frame", UDim2.new(0.5, -4, 1, 0), nil, 3)
    local Right = Scroll(Parent, "RightMiniTab_Frame", UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), 3)
    return { Left, Right }
end

Library.Page = function(Self, Params)
    assert(Self.Kind == "Window", "Page must be created on a Window")
    Params = Params or {}
    local Name = Option(Params, "Name", "Page")
    local Tab = Button(Self.Items.PagesOutline, "Tab_Button", Name)
    Border(Tab)
    local Body = Frame(Self.Items.Content, "Page_" .. Name)
    local SubTabs = Frame(Body, "SubPages", UDim2.new(1, -6, 0, 30), UDim2.fromOffset(3, 3))
    SubTabs.Instance.Visible = false
    local Content = Frame(Body, "Columns")
    local Page = setmetatable({ Kind = "Page", Name = Name, Window = Self, Pages = {}, Active = false,
        Items = { Inactive = Tab, InactiveInline = Tab, Text = Tab, Page = Body, SubPages = SubTabs, Columns = Content },
        ColumnsData = Columns(Content), Buttons = {} }, Library)
    function Page:Turn(Bool)
        if Bool then
            for _, Other in ipairs(self.Window.Pages) do
                if Other ~= self then
                    Other:Turn(false)
                end
            end
        else
            Library:CloseOpenFrames(Body.Instance)
        end
        self.Active = Bool == true
        Body.Instance.Visible = self.Active
        Tab:AddToTheme({ TextColor3 = self.Active and "Accent" or "Inactive Text" })
    end
    Tab:Connect("Activated", function()
        Page:Turn(true)
    end)
    table.insert(Self.Pages, Page)
    local Tabs = {}
    for _, Other in ipairs(Self.Pages) do
        table.insert(Tabs, Other.Items.Inactive)
    end
    EqualButtons(Tabs, 40)
    Page:Turn(#Self.Pages == 1)
    return Page
end

Library.SubPage = function(Self, Params)
    assert(Self.Kind == "Page" or Self.Kind == "Section", "SubPage must be created on a Page or Section")
    Params = Params or {}
    local Name = Option(Params, "Name", "Settings")
    local SectionMode = Self.Kind == "Section"
    local SubTabs = SectionMode and Self.Items.SubTabs or Self.Items.SubPages
    local Tab = Button(SubTabs, "SubTab_Button", Name)
    Border(Tab)
    SubTabs.Instance.Visible = true
    if SectionMode then
        Self.Items.Text.Instance.Visible = false
        Self.Items.Content.Instance.Visible = false
    else
        for _, Column in ipairs(Self.ColumnsData) do
            Column.Instance.Visible = false
        end
        Self.Items.Columns.Instance.Position = UDim2.fromOffset(0, 37)
        Self.Items.Columns.Instance.Size = UDim2.new(1, 0, 1, -37)
    end
    local Content = Frame(SectionMode and Self.Items.Section or Self.Items.Columns, "SubPage_" .. Name,
        SectionMode and UDim2.new(1, -24, 0, 0) or nil, SectionMode and UDim2.fromOffset(12, 50) or nil)
    local Data = setmetatable({ Kind = SectionMode and "SubTab" or "SubPage", Name = Name,
        Window = Self.Window, Page = Self, Active = false,
        Items = { Inactive = Tab, Text = Tab, Page = Content, Content = Content } }, Library)
    if SectionMode then
        Content.Instance.AutomaticSize = Enum.AutomaticSize.Y
        List(Content, 8)
        Padding(Content, 12)
        Border(Content)
        Self.Items.Section.Instance.AutomaticSize = Enum.AutomaticSize.Y
    else
        Data.ColumnsData = Columns(Content)
    end
    function Data:Turn(Bool)
        if Bool then
            for _, Other in ipairs(Self.Pages) do
                if Other ~= self then
                    Other:Turn(false)
                end
            end
        else
            Library:CloseOpenFrames(Content.Instance)
        end
        self.Active = Bool == true
        Content.Instance.Visible = self.Active
        Tab:AddToTheme({ TextColor3 = self.Active and "Accent" or "Inactive Text" })
    end
    Tab:Connect("Activated", function()
        Data:Turn(true)
    end)
    table.insert(Self.Pages, Data)
    local Tabs = {}
    for _, Other in ipairs(Self.Pages) do
        table.insert(Tabs, Other.Items.Inactive)
    end
    EqualButtons(Tabs, 30)
    Data:Turn(#Self.Pages == 1)
    return Data
end
Library.SubTab = Library.SubPage

Library.Section = function(Self, Params)
    Params = Params or {}
    assert(Self.ColumnsData, "Section must be created on a Page or SubPage")
    local Side = Option(Params, "Side", 1)
    if type(Side) == "string" then
        Side = Side:lower() == "right" and 2 or 1
    end
    assert(Self.ColumnsData[Side], "Side must be 1 (left) or 2 (right)")
    local Name = Option(Params, "Name", "Section")
    local Outer = Frame(Self.ColumnsData[Side], "OuterSelection_Frame", UDim2.new(1, 0, 0, 0), nil, "Section")
    Outer.Instance.AutomaticSize = Enum.AutomaticSize.Y
    Border(Outer)
    local Header = Text(Outer, "SelectionName_Label", Name, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 12))
    Border(Header)
    local Tabs = Frame(Outer, "SubTab_Frame", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 12))
    Tabs.Instance.Visible = false
    local Content = Frame(Outer, "InnerSelection_Frame", UDim2.new(1, -24, 0, 0), UDim2.fromOffset(12, 50), "Section")
    Content.Instance.AutomaticSize = Enum.AutomaticSize.Y
    Border(Content)
    List(Content, 8)
    Padding(Content, 12)
    Padding(Outer, 0).Instance.PaddingBottom = UDim.new(0, 12)
    local Data = setmetatable({ Kind = "Section", Name = Name, Side = Side, Window = Self.Window,
        Page = Self, Pages = {}, Items = { SectionOutline = Outer, Section = Outer, Text = Header,
            SubTabs = Tabs, Content = Content }, Instance = Outer.Instance }, Library)
    function Data:SetText(Value)
        Header.Instance.Text = tostring(Value)
    end
    function Data:SetVisibility(Bool)
        Outer.Instance.Visible = Bool == true
        if not Bool then
            Library:CloseOpenFrames(Outer.Instance)
        end
    end
    return Data
end

local function Attachments(ControlData, Row)
    local Holder = Frame(Row, "SubElements", UDim2.new(0, 0, 1, 0), UDim2.fromScale(1, 0))
    Holder.Instance.AnchorPoint = Vector2.new(1, 0)
    Holder.Instance.AutomaticSize = Enum.AutomaticSize.X
    local Layout = List(Holder, 6, true)
    Layout.Instance.HorizontalAlignment = Enum.HorizontalAlignment.Right
    Layout.Instance.VerticalAlignment = Enum.VerticalAlignment.Center
    ControlData.Items.SubElements = Holder
    function ControlData:Colorpicker(Params)
        Params = table.clone(Params or {})
        Params.Parent = Holder
        Params.Flag = Option(Params, "Flag", self.Flag .. "Color")
        return Library:CreateColorpicker(Params)
    end
    function ControlData:Keybind(Params)
        Params = table.clone(Params or {})
        Params.Parent = Holder
        Params.Name = Option(Params, "Name", self.Name)
        Params.Flag = Option(Params, "Flag", self.Flag .. "Keybind")
        return Library:CreateKeybind(Params)
    end
    Library:Connect(Holder.Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
        if ControlData.Items.Text then
            local Offset = ControlData.Kind == "Toggle" and 18 or 0
            ControlData.Items.Text.Instance.Size = UDim2.new(1, -Holder.Instance.AbsoluteSize.X - Offset - 4, 1, 0)
        end
    end, Row)
end

Library.Toggle = function(Self, Params)
    Params = Params or {}
    local Data, Row = Control(Self, Params, "Toggle", 16)
    local Hitbox = Button(Row, "Toggle_Button", "")
    Data.Items.Toggle = Hitbox
    Data.Items.Indicator = Frame(Hitbox, "Indicator", UDim2.fromOffset(9, 9), UDim2.new(0, 0, 0.5, -4), "Element")
    Border(Data.Items.Indicator, false)
    Data.Items.Inline = Frame(Data.Items.Indicator, "Fill", nil, nil, "Accent")
    Data.Items.Text = Text(Hitbox, "Toggle_Label", Data.Name, UDim2.new(1, -18, 1, 0), UDim2.fromOffset(18, 0),
        Option(Params, "Risky", false) and "Risky" or "Text")
    Data.Items.Text.Instance.TextXAlignment = Enum.TextXAlignment.Left
    Attachments(Data, Hitbox)
    function Data:Set(Bool, Silent)
        Bool = Bool == true
        self.Items.Inline.Instance.Visible = Bool
        Commit(self, Bool, Silent)
        return self
    end
    function Data:Settings()
        if self.SettingsData then
            return self.SettingsData
        end
        local Gear = Button(self.Items.SubElements, "Settings_Button", "+", UDim2.fromOffset(12, 16))
        local State, Item = Popup(Gear, UDim2.fromOffset(254, 242), "ToggleSettings")
        local Header = Text(Item, "Title", self.Name, UDim2.new(1, -14, 0, 25), UDim2.fromOffset(7, 0), "Accent")
        Header.Instance.TextXAlignment = Enum.TextXAlignment.Left
        local Content = Scroll(Item, "Content", UDim2.new(1, -10, 1, -35), UDim2.fromOffset(5, 30), 7)
        State.Kind, State.IsSettings = "Settings", true
        State.Items = { Content = Content, Text = Header, ToggleSettings = Item }
        State.Window, State.Page = self.Window, self.Page
        self.SettingsData = setmetatable(State, Library)
        return self.SettingsData
    end
    Hitbox:Connect("Activated", function()
        Data:Set(not Data.Value)
    end)
    RegisterFlag(Data.Flag, Row, function(Value)
        Data:Set(Value)
    end)
    Data:Set(Option(Params, "Default", false))
    return Data
end

Library.Label = function(Self, Params)
    Params = Params or {}
    local Data, Row = Control(Self, Params, "Label", 16)
    Data.Items.Text = Text(Row, "Text", Data.Name)
    Data.Items.Text.Instance.TextXAlignment = Enum.TextXAlignment.Left
    Attachments(Data, Row)
    return Data
end

Library.Button = function(Self, Params)
    Params = Params or {}
    local Data, Row = Control(Self, Params, "Button", 22)
    local Hitbox = Button(Row, "Button", Data.Name, nil, nil, "Element")
    Border(Hitbox)
    Data.Items.Button, Data.Items.Text = Hitbox, Hitbox
    function Data:Press()
        Library:SafeCall(self.Callback)
    end
    Hitbox:OnHover(function()
        Hitbox:AddToTheme({ BackgroundColor3 = "Hovered Element" })
    end, function()
        Hitbox:AddToTheme({ BackgroundColor3 = "Element" })
    end)
    Hitbox:Connect("Activated", function()
        Data:Press()
    end)
    return Data
end

Library.Slider = function(Self, Params)
    Params = Params or {}
    local Data, Row = Control(Self, Params, "Slider", 30)
    Data.Min, Data.Max = Option(Params, "Min", 0), Option(Params, "Max", 100)
    assert(Data.Max >= Data.Min, "Slider Max must be greater than or equal to Min")
    Data.Decimals, Data.Suffix = Option(Params, "Decimals", 0), Option(Params, "Suffix", "")
    Data.Items.Text = Text(Row, "Slider_Label", Data.Name, UDim2.new(0.6, 0, 0, 16))
    Data.Items.Text.Instance.TextXAlignment = Enum.TextXAlignment.Left
    local ValueText = Text(Row, "SliderValue_Label", "", UDim2.new(0.4, 0, 0, 16), UDim2.fromScale(0.6, 0))
    ValueText.Instance.TextXAlignment = Enum.TextXAlignment.Right
    Data.Items.Value = ValueText
    local Bar = Frame(Row, "SliderBar_Frame", UDim2.new(1, 0, 0, 7), UDim2.fromOffset(0, 21), "Element")
    Border(Bar, false)
    local Fill = Frame(Bar, "SliderFill_Frame", nil, nil, "Accent")
    Data.Items.Accent = Fill
    local Hitbox = Button(Row, "RealSlider", "", UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 16))
    Data.Items.RealSlider = Hitbox
    function Data:Set(Value, Silent)
        Value = tonumber(Value)
        if not Value or Value ~= Value or math.abs(Value) == math.huge then
            return false
        end
        Value = math.clamp(Library:Round(math.clamp(Value, self.Min, self.Max), self.Decimals), self.Min, self.Max)
        local Alpha = self.Max == self.Min and 1 or (Value - self.Min) / (self.Max - self.Min)
        Fill.Instance.Size = UDim2.fromScale(Alpha, 1)
        ValueText.Instance.Text = string.format("%s%s", tonumber(string.format("%.6f", Value)), self.Suffix)
        Commit(self, Value, Silent)
        return self
    end
    function Data:GetSize(Input)
        local Position = Pointer(Input)
        return self.Min + (self.Max - self.Min)
            * math.clamp((Position.X - Bar.Instance.AbsolutePosition.X) / math.max(1, Bar.Instance.AbsoluteSize.X), 0, 1)
    end
    Hitbox:BindDrag(function(Point)
        local Alpha = math.clamp((Point.X - Bar.Instance.AbsolutePosition.X) / math.max(1, Bar.Instance.AbsoluteSize.X), 0, 1)
        Data:Set(Data.Min + (Data.Max - Data.Min) * Alpha)
    end)
    RegisterFlag(Data.Flag, Row, function(Value)
        Data:Set(Value)
    end)
    Data:Set(Option(Params, "Default", Data.Min))
    return Data
end

-- Dropdown and Searchbox share selection logic, including exact multiselect resets.
local function Selection(Self, Params, SearchMode)
    local Kind = SearchMode and "Searchbox" or "Dropdown"
    local Data, Row = Control(Self, Params, Kind, SearchMode and 150 or 20)
    Data.Multi, Data.Options, Data.OptionItems = Option(Params, "Multi", false), {}, {}
    Data.Value = Data.Multi and {} or ""
    local Holder, State, PopupItem, Hitbox
    if SearchMode then
        local Search = Library:Create("TextBox", {
            Name = "Input", Parent = Row, Size = UDim2.new(1, 0, 0, 23),
            PlaceholderText = Option(Params, "Placeholder", "Search ..."),
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        }):AddToTheme({ BackgroundColor3 = "Element", PlaceholderColor3 = "Inactive Text" })
        Border(Search)
        Holder = Scroll(Row, "Holder", UDim2.new(1, 0, 1, -29), UDim2.fromOffset(0, 29), 4)
        Data.Items.Input, Data.Items.Holder = Search, Holder
        Border(Holder)
    else
        Hitbox = Button(Row, "RealDropdown", "", nil, nil, "Element")
        Border(Hitbox, false)
        local Value = Text(Hitbox, "Value", Data.Name, UDim2.new(1, -24, 1, 0), UDim2.fromOffset(4, 0))
        Value.Instance.TextXAlignment = Enum.TextXAlignment.Left
        local Icon = Text(Hitbox, "DropDownIcon_Label", "+", UDim2.new(0, 18, 1, 0), UDim2.new(1, -18, 0, 0))
        Data.Items.RealDropdown, Data.Items.Value, Data.Items.Text, Data.Items.Icon = Hitbox, Value, Value, Icon
        State, PopupItem = Popup(Hitbox, UDim2.fromOffset(160, 100), "OptionHolder")
        Holder = Scroll(PopupItem, "Options", nil, nil, 4)
        Data.Items.OptionHolder = PopupItem
        Data.AttachedButton, Data.Frame = Hitbox.Instance, PopupItem.Instance
        State.OnOpenChanged = function(Open)
            Data.IsOpen = Open
            Icon.Instance.Text = Open and "-" or "+"
        end
        State.BeforeOpen = function()
            local Count = #Data.OptionItems
            PopupItem.Instance.Size = UDim2.fromOffset(Hitbox.Instance.AbsoluteSize.X,
                math.min(Option(Params, "MaxSize", 180), math.max(28, Count * 22 + 8)))
        end
        function Data:SetOpen(Bool)
            State:SetOpen(Bool)
        end
    end
    local function UpdateDisplay()
        if Data.Items.Value then
            local Value = Data.Multi and table.concat(Data.Value, ", ") or Data.Value
            Data.Items.Value.Instance.Text = Value ~= "" and Value or Data.Name
        end
        for Name, Entry in pairs(Data.Options) do
            Entry.IsSelected = Data.Multi and table.find(Data.Value, Name) ~= nil or (not Data.Multi and Data.Value == Name)
            Entry.Button:AddToTheme({ TextColor3 = Entry.IsSelected and "Accent" or "Inactive Text" })
        end
    end
    function Data:Set(Value, Silent)
        if self.Multi then
            if type(Value) ~= "table" then
                return false
            end
            local New, Seen = {}, {}
            for _, Name in ipairs(Value) do
                if self.Options[Name] and not Seen[Name] then
                    table.insert(New, Name)
                    Seen[Name] = true
                end
            end
            Commit(self, New, Silent)
        else
            if Value == nil then
                Value = ""
            end
            if Value ~= "" and not self.Options[Value] then
                return false
            end
            Commit(self, Value, Silent)
        end
        UpdateDisplay()
        return self
    end
    function Data:Add(Value)
        Value = tostring(Value)
        if self.Options[Value] then
            return self.Options[Value]
        end
        local Item = Button(Holder, "Option", Value, UDim2.new(1, 0, 0, 20))
        Item.Instance.TextXAlignment = Enum.TextXAlignment.Left
        local Entry = { Button = Item, Name = Value, IsSelected = false }
        function Entry:Set()
            if Data.Multi then
                local New = table.clone(Data.Value)
                local Index = table.find(New, Value)
                if Index then
                    table.remove(New, Index)
                else
                    table.insert(New, Value)
                end
                Data:Set(New)
            else
                Data:Set(Value)
                if State then
                    State:SetOpen(false)
                end
            end
        end
        function Entry:ToggleState(ValueState)
            Item:AddToTheme({ TextColor3 = ValueState == "Active" and "Accent" or "Inactive Text" })
        end
        Item:Connect("Activated", function()
            Entry:Set()
        end)
        self.Options[Value] = Entry
        table.insert(self.OptionItems, Value)
        if SearchMode then
            Item.Instance.Visible = Value:lower():find(self.Items.Input.Instance.Text:lower(), 1, true) ~= nil
        end
        UpdateDisplay()
        return Entry
    end
    function Data:Remove(Value)
        local Entry = self.Options[Value]
        if not Entry then
            return
        end
        Entry.Button:Destroy()
        self.Options[Value] = nil
        table.remove(self.OptionItems, table.find(self.OptionItems, Value))
        if self.Multi then
            self:Set(self.Value)
        elseif self.Value == Value then
            self:Set("")
        end
    end
    function Data:Refresh(Values)
        local PreviousValue = type(self.Value) == "table" and table.clone(self.Value) or self.Value
        for _, Entry in pairs(self.Options) do
            Entry.Button:Destroy()
        end
        self.Options, self.OptionItems = {}, {}
        for _, Value in ipairs(Values or {}) do
            self:Add(Value)
        end
        if not self.Multi and not self.Options[PreviousValue] then
            PreviousValue = ""
        end
        self:Set(PreviousValue)
        if State and State.IsOpen then
            self:SetOpen(true)
        end
    end
    if SearchMode then
        Library:Connect(Data.Items.Input.Instance:GetPropertyChangedSignal("Text"), function()
            local Query = Data.Items.Input.Instance.Text:lower()
            for Name, Entry in pairs(Data.Options) do
                Entry.Button.Instance.Visible = Name:lower():find(Query, 1, true) ~= nil
            end
        end, Row)
    end
    for _, Value in ipairs(Option(Params, "Items", {})) do
        Data:Add(Value)
    end
    RegisterFlag(Data.Flag, Row, function(Value)
        Data:Set(Value)
    end)
    Data:Set(Option(Params, "Default", Data.Multi and {} or ""))
    return Data
end

Library.Dropdown = function(Self, Params)
    return Selection(Self, Params or {}, false)
end
Library.Searchbox = function(Self, Params)
    return Selection(Self, Params or {}, true)
end

Library.Textbox = function(Self, Params)
    Params = Params or {}
    local Data, Row = Control(Self, Params, "Textbox", 25)
    Data.Numeric, Data.Finished = Option(Params, "Numeric", false), Option(Params, "Finished", false)
    local Input = Library:Create("TextBox", {
        Name = "Input", Parent = Row, Size = UDim2.fromScale(1, 1),
        PlaceholderText = Option(Params, "Placeholder", Data.Name .. " ..."),
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }):AddToTheme({ BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "Inactive Text" })
    Border(Input)
    Padding(Input, 4)
    Data.Items.Input = Input
    local Updating = false
    function Data:Set(Value, Silent)
        Value = tostring(Value or "")
        if self.Numeric and Value ~= "" and not tonumber(Value) then
            Updating = true
            Input.Instance.Text = self.Value or ""
            Updating = false
            return false
        end
        Updating = true
        Input.Instance.Text = Value
        Updating = false
        Commit(self, Value, Silent)
        return self
    end
    function Data:SetText(Value)
        self.Name = tostring(Value)
        Input.Instance.PlaceholderText = self.Name
    end
    if Data.Finished then
        Input:Connect("FocusLost", function()
            Data:Set(Input.Instance.Text)
        end)
    else
        Library:Connect(Input.Instance:GetPropertyChangedSignal("Text"), function()
            if not Updating then
                Data:Set(Input.Instance.Text)
            end
        end, Row)
    end
    RegisterFlag(Data.Flag, Row, function(Value)
        Data:Set(Value)
    end)
    Data:Set(Option(Params, "Default", ""))
    return Data
end
Library.TextBox = Library.Textbox

Library.CreateColorpicker = function(Self, Params)
    Params = Params or {}
    local Parent = Option(Params, "Parent")
    assert(Parent, "Use Toggle:Colorpicker() or Label:Colorpicker()")
    local Swatch = Button(Parent, "ColorpickerButton", "", UDim2.fromOffset(22, 12), nil, "Element")
    Library.ThemeMap[Swatch.Instance].BackgroundColor3 = nil
    Border(Swatch, false)
    local State, Item = Popup(Swatch, UDim2.fromOffset(230, 224), "ColorpickerWindow")
    local Data = {
        Flag = Flag(Params, "Color"), Callback = Option(Params, "Callback"),
        Color = Color3.new(1, 1, 1), Alpha = 0, Hue = 0, Saturation = 0, Value = 1,
        Items = { ColorpickerButton = Swatch, ColorpickerWindow = Item }, IsOpen = false,
        AttachedButton = Swatch.Instance, Frame = Item.Instance,
    }
    State.OnOpenChanged = function(Open)
        Data.IsOpen = Open
    end
    local Palette = Button(Item, "Palette", "", UDim2.fromOffset(176, 155), UDim2.fromOffset(10, 10), "Element")
    Library.ThemeMap[Palette.Instance].BackgroundColor3 = nil
    Border(Palette, false)
    local Saturation = Frame(Palette, "Saturation")
    Saturation.Instance.BackgroundTransparency = 0
    Saturation.Instance.BackgroundColor3 = Color3.new(1, 1, 1)
    Library:Create("UIGradient", {
        Parent = Saturation, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
        }),
    })
    local ValueLayer = Frame(Palette, "Value")
    ValueLayer.Instance.BackgroundTransparency = 0
    ValueLayer.Instance.BackgroundColor3 = Color3.new(0, 0, 0)
    Library:Create("UIGradient", {
        Parent = ValueLayer, Rotation = 90, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
        }),
    })
    local Marker = Frame(Palette, "PaletteDragger", UDim2.fromOffset(3, 3), nil, "Text")
    Marker.Instance.AnchorPoint = Vector2.new(0.5, 0.5)
    Marker.Instance.ZIndex = 5
    Border(Marker, false)
    local Hue = Button(Item, "Hue", "", UDim2.fromOffset(15, 155), UDim2.fromOffset(202, 10), "Element")
    Library.ThemeMap[Hue.Instance].BackgroundColor3 = nil
    Hue.Instance.BackgroundColor3 = Color3.new(1, 1, 1)
    Border(Hue, false)
    local HueColors = {}
    for Index = 0, 6 do
        table.insert(HueColors, ColorSequenceKeypoint.new(Index / 6, Color3.fromHSV(Index / 6, 1, 1)))
    end
    Library:Create("UIGradient", { Parent = Hue, Rotation = 90, Color = ColorSequence.new(HueColors) })
    local HueMarker = Frame(Hue, "HueDragger", UDim2.new(1, 0, 0, 2), nil, "Text")
    local Alpha = Button(Item, "Alpha", "", UDim2.fromOffset(176, 12), UDim2.fromOffset(10, 176), "Element")
    Border(Alpha, false)
    local AlphaFill = Frame(Alpha, "AlphaColor")
    AlphaFill.Instance.BackgroundTransparency = 0
    Library:Create("UIGradient", {
        Parent = AlphaFill, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
        }),
    })
    local AlphaMarker = Frame(Alpha, "AlphaDragger", UDim2.new(0, 2, 1, 0), nil, "Text")
    local Hex = Library:Create("TextBox", {
        Name = "Hex", Parent = Item, Size = UDim2.fromOffset(126, 22), Position = UDim2.fromOffset(10, 195),
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }):AddToTheme({ BackgroundColor3 = "Element" })
    Border(Hex)
    local Copy = Button(Item, "Copy", "Copy", UDim2.fromOffset(35, 22), UDim2.fromOffset(143, 195))
    local Paste = Button(Item, "Paste", "Paste", UDim2.fromOffset(35, 22), UDim2.fromOffset(182, 195))
    Data.Items.Palette, Data.Items.PaletteDragger, Data.Items.Hue, Data.Items.HueDragger = Palette, Marker, Hue, HueMarker
    Data.Items.Alpha, Data.Items.AlphaDragger, Data.Items.Hex = Alpha, AlphaMarker, Hex
    function Data:SetOpen(Bool)
        State:SetOpen(Bool)
    end
    function Data:SetVisibility(Bool)
        Swatch.Instance.Visible = Bool == true
        if not Bool then
            self:SetOpen(false)
        end
    end
    function Data:Update(Silent)
        self.Color = Color3.fromHSV(self.Hue, self.Saturation, self.Value)
        self.HexValue = self.Color:ToHex()
        Swatch.Instance.BackgroundColor3 = self.Color
        Swatch.Instance.BackgroundTransparency = self.Alpha
        Palette.Instance.BackgroundColor3 = Color3.fromHSV(self.Hue, 1, 1)
        AlphaFill.Instance.BackgroundColor3 = self.Color
        Marker.Instance.Position = UDim2.fromScale(self.Saturation, 1 - self.Value)
        HueMarker.Instance.Position = UDim2.new(0, 0, self.Hue, -1)
        AlphaMarker.Instance.Position = UDim2.new(self.Alpha, -1, 0, 0)
        Hex.Instance.Text = "#" .. self.HexValue
        Library.Flags[self.Flag] = {
            Color = self.Color, Alpha = self.Alpha, HexValue = self.HexValue, Transparency = 1 - self.Alpha,
        }
        if not Silent then
            Library:SafeCall(self.Callback, self.Color, self.Alpha)
        end
    end
    function Data:Set(Color, Transparency, Silent)
        if type(Color) == "table" and Color.Color then
            Transparency, Color = Color.Alpha, Color.Color
        end
        local Success, Parsed = pcall(function()
            if type(Color) == "string" then
                return Color3.fromHex(Color:gsub("#", ""))
            elseif type(Color) == "table" then
                return Color3.fromRGB(Color[1], Color[2], Color[3])
            end
            assert(typeof(Color) == "Color3", "Color must be Color3, hex, or an RGB array")
            return Color
        end)
        if not Success then
            return false
        end
        self.Hue, self.Saturation, self.Value = Parsed:ToHSV()
        self.Alpha = math.clamp(tonumber(Transparency) or self.Alpha, 0, 1)
        self:Update(Silent)
        return self
    end
    Palette:BindDrag(function(Point)
        local Position, Size = Palette.Instance.AbsolutePosition, Palette.Instance.AbsoluteSize
        Data.Saturation = math.clamp((Point.X - Position.X) / math.max(1, Size.X), 0, 1)
        Data.Value = 1 - math.clamp((Point.Y - Position.Y) / math.max(1, Size.Y), 0, 1)
        Data:Update()
    end)
    Hue:BindDrag(function(Point)
        Data.Hue = math.clamp((Point.Y - Hue.Instance.AbsolutePosition.Y) / math.max(1, Hue.Instance.AbsoluteSize.Y), 0, 1)
        Data:Update()
    end)
    Alpha:BindDrag(function(Point)
        Data.Alpha = math.clamp((Point.X - Alpha.Instance.AbsolutePosition.X) / math.max(1, Alpha.Instance.AbsoluteSize.X), 0, 1)
        Data:Update()
    end)
    Hex:Connect("FocusLost", function()
        if not Data:Set(Hex.Instance.Text) then
            Hex.Instance.Text = "#" .. Data.HexValue
        end
    end)
    Copy:Connect("Activated", function()
        Library.CopiedColor = { Color = Data.Color, Alpha = Data.Alpha }
    end)
    Paste:Connect("Activated", function()
        if Library.CopiedColor then
            Data:Set(Library.CopiedColor)
        end
    end)
    RegisterFlag(Data.Flag, Swatch, function(Value, Transparency)
        Data:Set(Value, Transparency)
    end)
    Data:Set(Option(Params, "Default", Color3.new(1, 1, 1)), Option(Params, "Alpha", 0))
    return Data, Data.Items
end

local function NormalizeKey(Value)
    if Value == nil or Value == "None" or Value == "" then
        return "None", "None"
    end
    local Key = tostring(Value)
    local Name = Key:match("([%w_]+)$")
    if Name == "Backspace" or Name == "Unknown" then
        return "None", "None"
    end
    if not Key:find("Enum.", 1, true) then
        local Success, Item = pcall(function()
            return Enum.KeyCode[Name]
        end)
        if not Success or not Item then
            return "None", "None"
        end
        Key = tostring(Item)
    end
    return Key, Name
end

Library.CreateKeybind = function(Self, Params)
    Params = Params or {}
    local Parent = Option(Params, "Parent")
    assert(Parent, "Use Toggle:Keybind() or Label:Keybind()")
    local KeyButton = Button(Parent, "KeyButton", "[None]", UDim2.fromOffset(48, 16))
    local Data = {
        Flag = Flag(Params, "Keybind"), Name = Option(Params, "Name", "Keybind"),
        Callback = Option(Params, "Callback"), Key = "None", Value = "None",
        Mode = Option(Params, "Mode", "Toggle"), Toggled = false, Picking = false,
        Disabled = false, ShowInList = true, Items = { KeyButton = KeyButton }, IsOpen = false,
    }
    -- The left click captures a key; the right click opens mode settings.
    local ModeAnchor = Button(Parent, "ModeButton", ":", UDim2.fromOffset(8, 16))
    local State, Item = Popup(ModeAnchor, UDim2.fromOffset(180, 98), "KeybindWindow")
    Data.Items.KeybindWindow, Data.Items.ModeButton = Item, ModeAnchor
    Data.Frame, Data.AttachedButton = Item.Instance, ModeAnchor.Instance
    State.OnOpenChanged = function(Open)
        Data.IsOpen = Open
    end
    local Content = Frame(Item, "Content", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(8, 8))
    List(Content, 8)
    local Settings = setmetatable({ Kind = "Settings", Items = { Content = Content } }, Library)
    local ModeDropdown
    function Data:Update(Silent)
        Library.Flags[self.Flag] = { Key = self.Key, Mode = self.Mode, Toggled = self.Toggled }
        KeyButton.Instance.Text = self.Picking and "[...]" or "[" .. self.Value .. "]"
        KeyButton.Instance.Size = UDim2.fromOffset(math.max(36, #KeyButton.Instance.Text * 7), 16)
        if self.ListItem then
            self.ListItem:Set(self.Value, self.Name, self.Mode)
            self.ListItem:SetVis(self.ShowInList)
            self.ListItem:SetStatus(self.Toggled)
        end
        if not Silent then
            Library:SafeCall(self.Callback, self.Toggled)
        end
    end
    function Data:SetMode(Value, Silent)
        if not table.find({ "Toggle", "Hold", "Always" }, Value) then
            return false
        end
        self.Mode = Value
        self.Toggled = Value == "Always"
        if ModeDropdown then
            ModeDropdown:Set(Value, true)
        end
        self:Update(Silent)
        return self
    end
    function Data:Set(Value, Silent)
        if type(Value) == "string" and table.find({ "Toggle", "Hold", "Always" }, Value) then
            return self:SetMode(Value, Silent)
        end
        if type(Value) == "table" then
            local NewMode = Value.Mode or self.Mode
            if not table.find({ "Toggle", "Hold", "Always" }, NewMode) then
                return false
            end
            self.Mode = NewMode
            self.Key, self.Value = NormalizeKey(Value.Key)
            self.Toggled = self.Mode == "Always" or Value.Toggled == true
        else
            self.Key, self.Value = NormalizeKey(Value)
            self.Toggled = self.Mode == "Always"
        end
        self.Picking = false
        if Library.PickingKeybind == self then
            Library.PickingKeybind = nil
        end
        if ModeDropdown then
            ModeDropdown:Set(self.Mode, true)
        end
        self:Update(Silent)
        return self
    end
    function Data:Press(Bool)
        if self.Mode == "Always" then
            self.Toggled = true
        elseif self.Mode == "Hold" then
            self.Toggled = Bool == true
        elseif Bool ~= false then
            self.Toggled = not self.Toggled
        end
        self:Update()
    end
    function Data:CancelPicking()
        self.Picking = false
        if Library.PickingKeybind == self then
            Library.PickingKeybind = nil
        end
        self:Update(true)
    end
    function Data:SetOpen(Bool)
        State:SetOpen(Bool)
    end
    function Data:SetVisibility(Bool)
        KeyButton.Instance.Visible = Bool == true
        ModeAnchor.Instance.Visible = Bool == true
        if not Bool then
            self:CancelPicking()
            self:SetOpen(false)
        end
    end
    ModeDropdown = Settings:Dropdown({
        Name = "Mode", Flag = Data.Flag .. "Mode", Items = { "Toggle", "Hold", "Always" },
        Default = Data.Mode, Callback = function(Value)
            Data:SetMode(Value)
        end,
    })
    Settings:Toggle({ Name = "Show in keybinds list", Flag = Data.Flag .. "ShowInKeybindsList", Default = true,
        Callback = function(Value)
            Data.ShowInList = Value
            Data:Update(true)
        end })
    KeyButton:Connect("Activated", function()
        if Data.Disabled then
            return
        end
        if Library.PickingKeybind then
            Library.PickingKeybind:CancelPicking()
        end
        Data.Picking = true
        Library.PickingKeybind = Data
        Data:Update(true)
    end)
    KeyButton:Connect("MouseButton2Click", function()
        Data:SetOpen(not Data.IsOpen)
    end)
    Library:RegisterCleanup(KeyButton, function()
        Data:CancelPicking()
        Library.Keybinds[Data] = nil
        if Data.ListItem then
            Data.ListItem:Destroy()
        end
    end)
    Library.Keybinds[Data] = true
    if Library.KeyList then
        Data.ListItem = Library.KeyList:Add(Data.Value, Data.Name, Data.Mode)
    end
    RegisterFlag(Data.Flag, KeyButton, function(Value)
        Data:Set(Value)
    end)
    Data:Set({ Key = Option(Params, "Default", "None"), Mode = Data.Mode })
    return Data, Data.Items
end

Library.KeybindList = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "KeybindList", Vector2.new(220, 160), UDim2.fromOffset(36, 400))
    local Content = Scroll(Data.Items.MainFrame, "Content", UDim2.new(1, -14, 1, -44), UDim2.fromOffset(7, 37), 3)
    Data.Items.KeybindList, Data.Items.Content = Data.Items.MainFrame, Content
    function Data:Add(Key, Name, Mode)
        local Item = Text(Content, "Key", "", UDim2.new(1, 0, 0, 17))
        Item.Instance.TextXAlignment = Enum.TextXAlignment.Left
        Item.CanShow, Item.Active = true, false
        function Item:Set(NewKey, NewName, NewMode)
            self.Instance.Text = tostring(NewKey) .. " - " .. tostring(NewName) .. " - " .. tostring(NewMode)
        end
        function Item:SetStatus(Bool)
            self.Active = Bool == true
            self.Instance.Visible = self.Active and self.CanShow
        end
        function Item:SetVis(Bool)
            self.CanShow = Bool == true
            self:SetStatus(self.Active)
        end
        Item:Set(Key, Name, Mode)
        Item:SetStatus(false)
        return Item
    end
    Library.KeyList = Data
    for Keybind in pairs(Library.Keybinds) do
        Keybind.ListItem = Data:Add(Keybind.Value, Keybind.Name, Keybind.Mode)
        Keybind:Update(true)
    end
    return Data
end

Library.Notification = function(Self, Name, Duration, Color)
    local Item = Frame(Library.NotifHolder, "Notification", UDim2.fromOffset(294, 30), nil, "Background")
    Border(Item)
    local Accent = Frame(Item, "Accent", UDim2.new(0, 2, 1, 0), nil, "Accent")
    if Color then
        Accent.Instance.BackgroundColor3 = Color
    end
    local Label = Text(Item, "Text", tostring(Name), UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3))
    Label.Instance.TextXAlignment = Enum.TextXAlignment.Left
    Label.Instance.TextWrapped = true
    local Closed = false
    function Item:Close()
        if Closed then
            return
        end
        Closed = true
        self:Destroy()
    end
    Library:Delay(tonumber(Duration) or 3, function()
        Item:Close()
    end)
    return Item
end
Library.Notify = Library.Notification

Library.Watermark = function(Self, Params)
    Params = Params or {}
    local Main = Frame(Library.Root, "Watermark", UDim2.fromOffset(300, 24),
        Option(Params, "Position", UDim2.fromOffset(36, 32)), "Background")
    Border(Main)
    local Label = Text(Main, "Text", Option(Params, "Name", "Atarazia"), UDim2.new(1, -12, 1, 0),
        UDim2.fromOffset(6, 0), "Accent")
    Main:MakeDraggable()
    local Data = { Items = { Watermark = Main, Text = Label }, Prefix = Option(Params, "Name", "Atarazia") }
    function Data:SetText(Value)
        self.Provider = nil
        self.Prefix = tostring(Value)
        Label.Instance.Text = self.Prefix
    end
    Data.SetName = Data.SetText
    function Data:SetDynamicTextProvider(Callback)
        self.Provider = Callback
    end
    function Data:SetVisibility(Bool)
        Main.Instance.Visible = Bool == true
    end
    function Data:GetBounds()
        return Main.Instance.AbsolutePosition, Main.Instance.AbsoluteSize
    end
    local Frames, Elapsed = 0, 0
    Library:Connect(RunService.RenderStepped, function(Delta)
        Frames, Elapsed = Frames + 1, Elapsed + Delta
        if Elapsed >= 1 then
            local Fps = math.round(Frames / Elapsed)
            if Data.Provider then
                local Success, Value = Library:SafeCall(Data.Provider, Fps)
                if Success then
                    Label.Instance.Text = tostring(Value or "")
                end
            else
                Label.Instance.Text = Data.Prefix .. " / " .. Fps .. " fps / " .. os.date("%H:%M:%S")
            end
            Frames, Elapsed = 0, 0
        end
    end, Main)
    Library:RegisterLayout("Watermark", { Instance = Main.Instance })
    return Data
end

Library.ConsoleLogger = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "Console", Vector2.new(420, 275), UDim2.fromScale(0.05857, 0.14878))
    Data.Items.CallLogger = Data.Items.MainFrame
    local Output = Scroll(Data.Items.MainFrame, "Prints_ScrollingFrame", UDim2.new(1, -14, 1, -80),
        UDim2.fromOffset(7, 40), 5)
    Border(Output)
    Data.Items.Holder = Output
    local Clear = Button(Data.Items.MainFrame, "Clear_Button", "Clear Console", UDim2.new(1, -14, 0, 25),
        UDim2.new(0, 7, 1, -32), "Element")
    Border(Clear)
    Data.Items.Clear = Clear
    Data.CommandCallback = Option(Params, "Callback")
    Data.Lines = {}
    Data.MaxLines = math.max(1, tonumber(Option(Params, "MaxLines", 250)) or 250)
    function Data:Add(TextValue, Color)
        local Label = Text(Output, "Print_Label", tostring(TextValue), UDim2.new(1, 0, 0, 20))
        Label.Instance.TextXAlignment = Enum.TextXAlignment.Left
        Label.Instance.TextWrapped = true
        Label.Instance.AutomaticSize = Enum.AutomaticSize.Y
        if Color then
            Label.Instance.TextColor3 = Color
        end
        table.insert(self.Lines, Label)
        if #self.Lines > self.MaxLines then
            table.remove(self.Lines, 1):Destroy()
        end
        Library:Delay(0, function()
            if Output.Instance.Parent then
                Output.Instance.CanvasPosition = Vector2.new(0,
                    math.max(0, Output.Instance.AbsoluteCanvasSize.Y - Output.Instance.AbsoluteWindowSize.Y))
            end
        end)
        return Label
    end
    function Data:AddOutput(Value)
        return self:Add(Value)
    end
    function Data:AddWarning(Value)
        return self:Add(Value, Color3.fromRGB(255, 222, 80))
    end
    function Data:AddError(Value)
        return self:Add(Value, Library.Theme.Risky)
    end
    function Data:Clear()
        for _, Label in ipairs(self.Lines) do
            Label:Destroy()
        end
        table.clear(self.Lines)
        Output.Instance.CanvasPosition = Vector2.new(0, 0)
    end
    function Data:SetCommandCallback(Callback)
        self.CommandCallback = Callback
    end
    if Option(Params, "CommandInput", false) or Data.CommandCallback then
        Output.Instance.Size = UDim2.new(1, -14, 1, -110)
        local Input = Library:Create("TextBox", {
            Name = "Input", Parent = Data.Items.MainFrame, Size = UDim2.new(1, -14, 0, 23),
            Position = UDim2.new(0, 7, 1, -61), PlaceholderText = "Command ...", ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
        }):AddToTheme({ BackgroundColor3 = "Element", PlaceholderColor3 = "Inactive Text" })
        Border(Input)
        Data.Items.Input = Input
        Input:Connect("FocusLost", function(Enter)
            if Enter and Input.Instance.Text ~= "" then
                local Value = Input.Instance.Text
                Input.Instance.Text = ""
                Library:SafeCall(Data.CommandCallback, Value, Data)
            end
        end)
    end
    Clear:Connect("Activated", function()
        Data:Clear()
    end)
    if Option(Params, "CaptureLogs", false) then
        local LogService = game:GetService("LogService")
        Library:Connect(LogService.MessageOut, function(Value, MessageType)
            if MessageType == Enum.MessageType.MessageError then
                Data:AddError(Value)
            elseif MessageType == Enum.MessageType.MessageWarning then
                Data:AddWarning(Value)
            else
                Data:AddOutput(Value)
            end
        end, Data.Items.MainFrame)
    end
    AttachPanelButton(Data, "Console")
    return Data
end
Library.Console = Library.ConsoleLogger

Library.LuaWindow = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "Lua", Vector2.new(430, 312), UDim2.fromScale(0.65705, 0.46951))
    Data.Items.LuaWindow = Data.Items.MainFrame
    Data.Files, Data.Selected, Data.Callback = {}, nil, Option(Params, "Callback")
    local Toolbar = Frame(Data.Items.MainFrame, "LuaButtons_Frame", UDim2.new(1, -14, 0, 21), UDim2.fromOffset(7, 39))
    List(Toolbar, 5, true)
    local File = Button(Toolbar, "File_Button", "File", UDim2.fromOffset(50, 21))
    local ExecuteButton = Button(Toolbar, "Execute_Button", "Execute", UDim2.fromOffset(60, 21))
    local Delete = Button(Toolbar, "Delete_Button", "Delete", UDim2.fromOffset(50, 21))
    Border(File)
    Border(ExecuteButton)
    Border(Delete)
    local Tabs = Library:Create("ScrollingFrame", {
        Name = "LuaFile_Frame", Parent = Data.Items.MainFrame, Size = UDim2.new(1, -14, 0, 23),
        Position = UDim2.fromOffset(7, 65), BackgroundTransparency = 1,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0,
    })
    List(Tabs, 5, true)
    Border(Tabs)
    local EditorScroll = Library:Create("ScrollingFrame", {
        Name = "Code_ScrollingFrame", Parent = Data.Items.MainFrame, Size = UDim2.new(1, -14, 1, -104),
        Position = UDim2.fromOffset(7, 96), BackgroundTransparency = 1, CanvasSize = UDim2.new(),
        ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.XY,
    })
    Border(EditorScroll)
    local Numbers = Text(EditorScroll, "LineNumbers", "1", UDim2.fromOffset(34, 20), UDim2.fromOffset(0, 5), "Inactive Text")
    Numbers.Instance.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    Numbers.Instance.TextYAlignment = Enum.TextYAlignment.Top
    Numbers.Instance.TextTruncate = Enum.TextTruncate.None
    local Editor = Library:Create("TextBox", {
        Name = "Editor", Parent = EditorScroll, Size = UDim2.new(1, -42, 1, -10), Position = UDim2.fromOffset(38, 5),
        MultiLine = true, ClearTextOnFocus = false, BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = false, FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json"),
        TextSize = 12, TextStrokeTransparency = 1,
    })
    Data.Items.Editor, Data.Items.LineNumbers, Data.Items.CodeScroll, Data.Items.Files = Editor, Numbers, EditorScroll, Tabs
    Data.Items.Execute, Data.Items.Delete, Data.Items.File = ExecuteButton, Delete, File
    local Changing = false
    local function UpdateEditorSize()
        local Source = Editor.Instance.Text
        local Count = 1
        for _ in Source:gmatch("\n") do
            Count = Count + 1
        end
        local Lines = {}
        for Index = 1, Count do
            Lines[Index] = tostring(Index)
        end
        Numbers.Instance.Text = table.concat(Lines, "\n")
        local Height = math.max(Editor.Instance.TextBounds.Y + 12, EditorScroll.Instance.AbsoluteWindowSize.Y - 10)
        local Width = math.max(Editor.Instance.TextBounds.X + 14, EditorScroll.Instance.AbsoluteWindowSize.X - 42)
        Editor.Instance.Size = UDim2.fromOffset(Width, Height)
        Numbers.Instance.Size = UDim2.fromOffset(34, Height)
        EditorScroll.Instance.CanvasSize = UDim2.fromOffset(Width + 42, Height + 10)
    end
    function Data:AddFile(Name, Source)
        Name = tostring(Name or "Untitled.lua")
        if self.Files[Name] then
            return self.Files[Name]
        end
        local Tab = Button(Tabs, "FileName_Button", Name, UDim2.fromOffset(math.max(70, #Name * 7), 23))
        local Entry = { Name = Name, Source = tostring(Source or ""), Button = Tab }
        self.Files[Name] = Entry
        Tab:Connect("Activated", function()
            Data:SelectFile(Name)
        end)
        self:SelectFile(Name)
        return Entry
    end
    function Data:SelectFile(Name)
        local Entry = self.Files[Name]
        if not Entry then
            return false
        end
        if self.Selected and self.Files[self.Selected] then
            self.Files[self.Selected].Source = Editor.Instance.Text
        end
        self.Selected = Name
        Changing = true
        Editor.Instance.Text = Entry.Source
        Changing = false
        for OtherName, Other in pairs(self.Files) do
            Other.Button:AddToTheme({ TextColor3 = OtherName == Name and "Accent" or "Inactive Text" })
        end
        UpdateEditorSize()
        return true
    end
    function Data:SetCode(Source)
        Editor.Instance.Text = tostring(Source or "")
        if self.Selected then
            self.Files[self.Selected].Source = Editor.Instance.Text
        end
        UpdateEditorSize()
    end
    function Data:GetCode()
        return Editor.Instance.Text
    end
    function Data:DeleteFile(Name)
        Name = Name or self.Selected
        local Entry = self.Files[Name]
        if not Entry then
            return false
        end
        Entry.Button:Destroy()
        self.Files[Name] = nil
        if self.Selected == Name then
            self.Selected = nil
            local NextName = next(self.Files)
            if NextName then
                self:SelectFile(NextName)
            else
                self:AddFile("Untitled.lua", "")
            end
        end
        return true
    end
    function Data:Execute()
        -- Intentionally callback-driven; the library never evaluates arbitrary source itself.
        if type(self.Callback) ~= "function" then
            Library:Notification("Supply LuaWindow.Callback to handle Execute", 3)
            return false
        end
        return Library:SafeCall(self.Callback, self:GetCode(), self.Selected, self)
    end
    Library:Connect(Editor.Instance:GetPropertyChangedSignal("Text"), function()
        if not Changing and Data.Selected then
            Data.Files[Data.Selected].Source = Editor.Instance.Text
        end
        UpdateEditorSize()
    end, EditorScroll)
    Library:Connect(Editor.Instance:GetPropertyChangedSignal("TextBounds"), UpdateEditorSize, EditorScroll)
    Library:Connect(EditorScroll.Instance:GetPropertyChangedSignal("AbsoluteSize"), UpdateEditorSize, EditorScroll)
    File:Connect("Activated", function()
        local Index = 1
        while Data.Files["Untitled" .. Index .. ".lua"] do
            Index = Index + 1
        end
        Data:AddFile("Untitled" .. Index .. ".lua", "")
    end)
    Delete:Connect("Activated", function()
        Data:DeleteFile()
    end)
    ExecuteButton:Connect("Activated", function()
        Data:Execute()
    end)
    Data:AddFile(Option(Params, "FileName", "Example.lua"), Option(Params, "Source", "-- Write Luau here"))
    AttachPanelButton(Data, "Lua")
    return Data
end
Library.Lua = Library.LuaWindow

Library.ESPPreview = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "Esp Preview", Vector2.new(240, 255), UDim2.fromScale(0.65705, 0.14878))
    Data.Items.ESPPreview = Data.Items.MainFrame
    local Background = Frame(Data.Items.MainFrame, "Preview_Frame", UDim2.new(1, -14, 1, -50),
        UDim2.fromOffset(7, 40), "Section")
    Border(Background)
    local Viewport = Library:Create("ViewportFrame", {
        Name = "Viewport", Parent = Background, Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Ambient = Color3.fromRGB(200, 200, 200),
        LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1),
    })
    local World = Library:Create("WorldModel", { Name = "PreviewWorld", Parent = Viewport })
    local Camera = Library:Create("Camera", { Parent = Viewport, FieldOfView = 35 })
    Viewport.Instance.CurrentCamera = Camera.Instance
    Data.Items.Viewport, Data.Items.Background, Data.Items.World = Viewport, Background, World
    Data.PreviewModel, Data.Player, Data.RebuildVersion = nil, nil, 0
    function Data:BuildFromModel(Model)
        if self.PreviewModel then
            self.PreviewModel:Destroy()
            self.PreviewModel = nil
        end
        self.Player = Model
        if not Model or not Model:IsA("Model") then
            return false
        end
        local WasArchivable = Model.Archivable
        local Success, Clone = pcall(function()
            Model.Archivable = true
            return Model:Clone()
        end)
        Model.Archivable = WasArchivable
        if not Success or not Clone then
            return false
        end
        for _, Object in ipairs(Clone:GetDescendants()) do
            if Object:IsA("LuaSourceContainer") then
                Object:Destroy()
            elseif Object:IsA("BasePart") then
                Object.Anchored = true
                Object.CanCollide = false
            elseif Object:IsA("Humanoid") then
                Object.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
        end
        Clone.Parent = World.Instance
        Clone:PivotTo(CFrame.new())
        local Center, Size = Clone:GetBoundingBox()
        local Distance = math.max(Size.Y, Size.X) / (2 * math.tan(math.rad(35 / 2))) * 1.3
        Camera.Instance.CFrame = CFrame.lookAt(Center.Position + Vector3.new(0, 0, -Distance), Center.Position)
        self.PreviewModel = Clone
        return true
    end
    function Data:SetImage(Image)
        if not self.Items.Image then
            self.Items.Image = Library:Create("ImageLabel", {
                Parent = Background, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            })
        end
        self.Items.Image.Instance.Image = Image
        self.Items.Image.Instance.Visible = Image ~= ""
        Viewport.Instance.Visible = Image == ""
    end
    local function Rebuild(Character)
        Data.RebuildVersion = Data.RebuildVersion + 1
        local Version = Data.RebuildVersion
        Library:Delay(0.5, function()
            if Version == Data.RebuildVersion and Data.Instance.Parent then
                Data:BuildFromModel(Character)
            end
        end)
    end
    if Option(Params, "UseLocalCharacter", true) then
        if LocalPlayer.Character then
            Rebuild(LocalPlayer.Character)
        end
        Library:Connect(LocalPlayer.CharacterAdded, Rebuild, Data.Items.MainFrame)
        Library:Connect(LocalPlayer.CharacterAppearanceLoaded, Rebuild, Data.Items.MainFrame)
    end
    AttachPanelButton(Data, "Esp")
    return Data
end

Library.Playerlist = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "Players", Vector2.new(205, 265), UDim2.fromScale(0.20549, 0.49756))
    Data.Items.Playerlist = Data.Items.MainFrame
    Data.Players, Data.Selected, Data.Callback = {}, nil, Option(Params, "Callback")
    local Search = Library:Create("TextBox", {
        Name = "Search", Parent = Data.Items.MainFrame, Size = UDim2.new(1, -14, 0, 25),
        Position = UDim2.fromOffset(7, 37), PlaceholderText = "Search ...", ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }):AddToTheme({ BackgroundColor3 = "Element", PlaceholderColor3 = "Inactive Text" })
    Border(Search)
    local Holder = Scroll(Data.Items.MainFrame, "Players_ScrollingFrame", UDim2.new(1, -14, 1, -138),
        UDim2.fromOffset(7, 69), 3)
    Border(Holder)
    local Avatar = Library:Create("ImageLabel", {
        Name = "PlayerProfile_Image", Parent = Data.Items.MainFrame, Size = UDim2.fromOffset(54, 54),
        Position = UDim2.new(0, 7, 1, -61), BackgroundTransparency = 1,
    })
    Border(Avatar)
    local Display = Text(Data.Items.MainFrame, "Display", "No player", UDim2.new(1, -75, 0, 16), UDim2.new(0, 68, 1, -61))
    Display.Instance.TextXAlignment = Enum.TextXAlignment.Left
    local Id = Text(Data.Items.MainFrame, "UserId", "UserId | -", UDim2.new(1, -75, 0, 16), UDim2.new(0, 68, 1, -45), "Inactive Text")
    Id.Instance.TextXAlignment = Enum.TextXAlignment.Left
    local Change = Button(Data.Items.MainFrame, "ChangeStatus_Button", "Change", UDim2.new(0.5, -38, 0, 18), UDim2.new(0, 68, 1, -25))
    local Teleport = Button(Data.Items.MainFrame, "Teleport_Button", "Teleport", UDim2.new(0.5, -38, 0, 18), UDim2.new(0.5, 35, 1, -25))
    Border(Change)
    Border(Teleport)
    Data.Items.Holder, Data.Items.Search, Data.Items.Avatar = Holder, Search, Avatar
    Data.Items.Display, Data.Items.UserID, Data.Items.Change, Data.Items.Teleport = Display, Id, Change, Teleport
    local function Filter()
        local Query = Search.Instance.Text:lower()
        for _, Entry in pairs(Data.Players) do
            Entry.Items.NewPlayer.Instance.Visible = (Entry.Name .. " " .. Entry.Display):lower():find(Query, 1, true) ~= nil
        end
    end
    function Data:Select(Entry)
        if type(Entry) == "string" then
            Entry = self.Players[Entry]
        end
        self.Selected = Entry
        for _, Other in pairs(self.Players) do
            Other.IsSelected = Other == Entry
            Other.Items.Username:AddToTheme({ TextColor3 = Other.IsSelected and "Accent" or "Inactive Text" })
        end
        Display.Instance.Text = Entry and Entry.Display or "No player"
        Id.Instance.Text = "UserId | " .. (Entry and tostring(Entry.Player.UserId) or "-")
        Avatar.Instance.Image = ""
        if Entry then
            Library:Thread(function()
                local Success, Image = pcall(function()
                    return Players:GetUserThumbnailAsync(Entry.Player.UserId,
                        Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
                end)
                if Success and not Library.Destroyed and Data.Selected == Entry then
                    Avatar.Instance.Image = Image
                end
            end)
        end
        Library:SafeCall(self.Callback, Entry)
    end
    function Data:Add(Player)
        if self.Players[Player.Name] then
            return self.Players[Player.Name]
        end
        local Row = Button(Holder, "Player_Frame", "", UDim2.new(1, 0, 0, 20))
        local Name = Text(Row, "Name_Label", Player.DisplayName or Player.Name, UDim2.new(0.62, 0, 1, 0), nil, "Inactive Text")
        Name.Instance.TextXAlignment = Enum.TextXAlignment.Left
        local Status = Text(Row, "Status_Label", "neutral", UDim2.new(0.38, 0, 1, 0), UDim2.fromScale(0.62, 0), "Inactive Text")
        Status.Instance.TextXAlignment = Enum.TextXAlignment.Right
        local Entry = {
            Name = Player.Name, Display = Player.DisplayName or Player.Name, Player = Player,
            Status = "Neutral", IsSelected = false, Items = { NewPlayer = Row, Username = Name, Status = Status },
        }
        function Entry:Set()
            if Data.Selected == self then
                Data:Select(nil)
            else
                Data:Select(self)
            end
        end
        function Entry:SetStatus(Value)
            if not table.find({ "Neutral", "Enemy", "Friendly" }, Value) then
                return false
            end
            self.Status = Value
            Status.Instance.Text = Value:lower()
            Library:SafeCall(Option(Params, "StatusCallback"), self, Value)
            return true
        end
        Row:Connect("Activated", function()
            Entry:Set()
        end)
        self.Players[Player.Name] = Entry
        Filter()
        return Entry
    end
    function Data:Remove(Player)
        local Name = type(Player) == "string" and Player or Player.Name
        local Entry = self.Players[Name]
        if Entry then
            Entry.Items.NewPlayer:Destroy()
            self.Players[Name] = nil
            if self.Selected == Entry then
                self:Select(nil)
            end
        end
    end
    Change:Connect("Activated", function()
        if Data.Selected then
            local Values = { "Neutral", "Enemy", "Friendly" }
            local Index = table.find(Values, Data.Selected.Status) or 1
            Data.Selected:SetStatus(Values[Index % #Values + 1])
        end
    end)
    Teleport:Connect("Activated", function()
        if not Data.Selected then
            return
        end
        local Callback = Option(Params, "TeleportCallback")
        if Callback then
            Library:SafeCall(Callback, Data.Selected.Player, Data.Selected)
        else
            Library:Notification("Supply Playerlist.TeleportCallback for this action", 3)
        end
    end)
    Library:Connect(Search.Instance:GetPropertyChangedSignal("Text"), Filter, Data.Items.MainFrame)
    Library:Connect(Players.PlayerAdded, function(Player)
        Data:Add(Player)
    end, Data.Items.MainFrame)
    Library:Connect(Players.PlayerRemoving, function(Player)
        Data:Remove(Player)
    end, Data.Items.MainFrame)
    for _, Player in ipairs(Players:GetPlayers()) do
        Data:Add(Player)
    end
    AttachPanelButton(Data, "Players")
    return Data
end
Library.PlayerList = Library.Playerlist

Library.KeySystem = function(Self, Params)
    Params = Params or {}
    local Data = Panel(Params, "Atarazia System", Vector2.new(185, 160), UDim2.fromScale(0.82487, 0.28902))
    Data.Items.KeyWindow = Data.Items.MainFrame
    local Content = Frame(Data.Items.MainFrame, "Content", UDim2.new(1, -26, 1, -45), UDim2.fromOffset(13, 39))
    List(Content, 7)
    local Settings = setmetatable({ Kind = "Settings", Items = { Content = Content } }, Library)
    Data.Username = Settings:Textbox({ Name = "Username", Flag = Flag({}, "KeyUsername"), Placeholder = "Username ..." })
    Data.Key = Settings:Textbox({ Name = "Key", Flag = Flag({}, "KeyInput"), Placeholder = "Key Here ..." })
    Library.IgnoreFlags[Data.Username.Flag], Library.IgnoreFlags[Data.Key.Flag] = true, true
    local Actions = Frame(Content, "GetKeys_Frame", UDim2.new(1, 0, 0, 25))
    local GetKey = Button(Actions, "GetKey_Button", "Get Key", UDim2.new(0.5, -2, 1, 0))
    local Submit = Button(Actions, "InputKey_Button", "Input Key", UDim2.new(0.5, -2, 1, 0), UDim2.new(0.5, 2, 0, 0))
    Border(GetKey)
    Border(Submit)
    Data.Items.GetKey, Data.Items.Submit = GetKey, Submit
    local Busy = false
    function Data:Submit()
        if Busy then
            return false
        end
        local Validator = Option(Params, "Callback", Option(Params, "Validate"))
        if not Validator then
            Library:Notification("Supply KeySystem.Callback to validate the key", 3)
            return false
        end
        Busy = true
        Submit.Instance.Text = "..."
        local Success, Accepted, Message = Library:SafeCall(Validator, self.Username.Value, self.Key.Value, self)
        Busy = false
        if Library.Destroyed then
            return false
        end
        Submit.Instance.Text = "Input Key"
        if Success and Accepted == true then
            self:SetVisibility(false)
            Library:SafeCall(Option(Params, "SuccessCallback"), self)
            return true
        end
        Library:Notification(tostring(Message or "Key rejected"), 3, Library.Theme.Risky)
        return false
    end
    GetKey:Connect("Activated", function()
        Library:SafeCall(Option(Params, "GetKeyCallback"), Data)
    end)
    Submit:Connect("Activated", function()
        Data:Submit()
    end)
    AttachPanelButton(Data, "Key")
    return Data
end

Library.RegisterLayout = function(Self, Id, Data)
    Library.LayoutRegistry[Id] = Data
    return Data
end

Library.GetLayoutConfig = function(Self)
    local Result = {}
    for Id, Data in pairs(Library.LayoutRegistry) do
        local Object = Data.Instance
        if Object.Parent then
            local Entry = {}
            if Data.SavePosition ~= false then
                local Position = Object.AbsolutePosition - RootOrigin()
                Entry.Position = { X = math.round(Position.X), Y = math.round(Position.Y) }
            end
            if Data.SaveSize then
                Entry.Size = { X = math.round(Object.AbsoluteSize.X), Y = math.round(Object.AbsoluteSize.Y) }
            end
            Result[Id] = Entry
        end
    end
    return Result
end

Library.ApplyLayoutConfig = function(Self, Layout)
    if type(Layout) ~= "table" then
        return false
    end
    local Bounds = ScreenSize()
    for Id, Entry in pairs(Layout) do
        local Data = Library.LayoutRegistry[Id]
        if Data and Data.Instance.Parent and type(Entry) == "table" then
            local Object = Data.Instance
            if Data.SaveSize and type(Entry.Size) == "table" then
                local Minimum = Data.MinimumSize or Vector2.new(100, 100)
                Object.Size = UDim2.fromOffset(
                    math.clamp(tonumber(Entry.Size.X) or Object.AbsoluteSize.X, math.min(Minimum.X, Bounds.X - 36), math.max(100, Bounds.X - 36)),
                    math.clamp(tonumber(Entry.Size.Y) or Object.AbsoluteSize.Y, math.min(Minimum.Y, Bounds.Y - 42), math.max(100, Bounds.Y - 42)))
            end
            if Data.SavePosition ~= false and type(Entry.Position) == "table" then
                Object.AnchorPoint = Vector2.new(0, 0)
                local Width, Height = Object.Size.X.Offset, Object.Size.Y.Offset
                Object.Position = UDim2.fromOffset(
                    math.clamp(tonumber(Entry.Position.X) or 28, 28, math.max(28, Bounds.X - Width - 3)),
                    math.clamp(tonumber(Entry.Position.Y) or 32, 32, math.max(32, Bounds.Y - Height - 3)))
            end
        end
    end
    return true
end

Library.GetConfig = function(Self)
    local Flags = {}
    for Name, Value in pairs(Library.Flags) do
        if Library.IgnoreFlags[Name] then
            -- Do not persist key-system credentials into a configuration file.
        elseif type(Value) == "table" and Value.Color then
            Flags[Name] = { Color = "#" .. Value.Color:ToHex(), Alpha = Value.Alpha }
        elseif typeof(Value) == "EnumItem" then
            Flags[Name] = tostring(Value)
        else
            Flags[Name] = Value
        end
    end
    return HttpService:JSONEncode({ Flags = Flags, Layout = Library:GetLayoutConfig() })
end

Library.LoadConfig = function(Self, Source)
    local Success, Result = pcall(function()
        local Config = type(Source) == "table" and Source or HttpService:JSONDecode(Source)
        assert(type(Config) == "table", "Config must be a JSON object")
        local Flags = Config.Flags or Config
        assert(type(Flags) == "table", "Config.Flags must be an object")
        -- Load primary values before keybind tables, avoiding derived-mode ordering bugs.
        for _, KeybindPass in ipairs({ false, true }) do
            for Name, Value in pairs(Flags) do
                local IsKeybind = type(Value) == "table" and Value.Key ~= nil
                local Set = Library.SetFlags[Name]
                if Set and IsKeybind == KeybindPass then
                    Set(Value)
                end
            end
        end
        if Config.Layout then
            Library:ApplyLayoutConfig(Config.Layout)
        end
    end)
    if Success then
        return true
    end
    return false, tostring(Result)
end

local function FileAPI(Name)
    local Value = Environment[Name]
    if type(Value) == "function" then
        return Value
    end
    return nil
end

local function ConfigPath(Name)
    assert(type(Name) == "string" and Name:match("^[%w_%- ]+$") and #Name <= 64,
        "Config name must be 1-64 letters, digits, spaces, underscores, or hyphens")
    return Library.Directory .. Library.Folders.Configs .. "/" .. Name .. ".json"
end

local function EnsureFolders()
    local IsFolder, MakeFolder = FileAPI("isfolder"), FileAPI("makefolder")
    assert(IsFolder and MakeFolder, "This host does not support file configs; use GetConfig/LoadConfig instead")
    if not IsFolder(Library.Directory) then
        MakeFolder(Library.Directory)
    end
    local Path = Library.Directory .. Library.Folders.Configs
    if not IsFolder(Path) then
        MakeFolder(Path)
    end
end

Library.SaveConfig = function(Self, Name)
    return pcall(function()
        local Path = ConfigPath(Name)
        EnsureFolders()
        local Write = FileAPI("writefile")
        assert(Write, "writefile is unavailable")
        Write(Path, Library:GetConfig())
    end)
end

Library.LoadConfigFile = function(Self, Name)
    local Success, Source = pcall(function()
        local Read = FileAPI("readfile")
        assert(Read, "readfile is unavailable")
        return Read(ConfigPath(Name))
    end)
    if not Success then
        return false, tostring(Source)
    end
    return Library:LoadConfig(Source)
end

Library.DeleteConfig = function(Self, Name)
    return pcall(function()
        local Delete = FileAPI("delfile")
        assert(Delete, "delfile is unavailable")
        Delete(ConfigPath(Name))
    end)
end

Library.GetConfigsList = function(Self, Element)
    local Names = {}
    local Success, Error = pcall(function()
        EnsureFolders()
        local Files = FileAPI("listfiles")
        assert(Files, "listfiles is unavailable")
        for _, Path in ipairs(Files(Library.Directory .. Library.Folders.Configs)) do
            local Name = Path:gsub("\\", "/"):match("([^/]+)%.json$")
            if Name then
                table.insert(Names, Name)
            end
        end
    end)
    table.sort(Names)
    if Element then
        Element:Refresh(Names)
    end
    if Success then
        return Names
    end
    return Names, tostring(Error)
end

Library.OpenConfirmDialog = function(Self, Params)
    Params = Params or {}
    if Library.ActiveConfirmDialog then
        Library.ActiveConfirmDialog:Close(false, true)
    end
    Library:CloseOpenFrames()
    local Overlay = Button(Library.Root, "ModalOverlay", "", nil, nil, "Border")
    Overlay.Instance.ZIndex = 300
    Overlay.Instance.BackgroundTransparency = 0.35
    Overlay.Instance.Modal = true
    local PanelItem = Frame(Overlay, "ConfirmDialog", UDim2.fromOffset(284, 130), UDim2.fromScale(0.5, 0.5), "Background")
    PanelItem.Instance.AnchorPoint = Vector2.new(0.5, 0.5)
    Border(PanelItem)
    local Title = Text(PanelItem, "Title", Option(Params, "Title", "Confirm"), UDim2.new(1, -20, 0, 20),
        UDim2.fromOffset(10, 6), "Accent")
    Title.Instance.TextXAlignment = Enum.TextXAlignment.Left
    local Message = Text(PanelItem, "Message", Option(Params, "Message", "Are you sure?"),
        UDim2.new(1, -20, 0, 55), UDim2.fromOffset(10, 30))
    Message.Instance.TextWrapped = true
    Message.Instance.TextXAlignment = Enum.TextXAlignment.Left
    Message.Instance.TextYAlignment = Enum.TextYAlignment.Top
    local Cancel = Button(PanelItem, "Cancel", Option(Params, "CancelText", "Cancel"),
        UDim2.new(0.5, -15, 0, 24), UDim2.new(0, 10, 1, -34), "Element")
    local Confirm = Button(PanelItem, "Confirm", Option(Params, "ConfirmText", "Confirm"),
        UDim2.new(0.5, -15, 0, 24), UDim2.new(0.5, 5, 1, -34), "Element")
    Border(Cancel)
    Border(Confirm)
    local Data = { Closed = false }
    function Data:Close(Accepted, SkipCallback)
        if self.Closed then
            return
        end
        self.Closed = true
        Library.ActiveConfirmDialog = nil
        Overlay:Destroy()
        if not SkipCallback then
            Library:SafeCall(Option(Params, "Callback"), Accepted == true)
        end
    end
    Cancel:Connect("Activated", function()
        Data:Close(false)
    end)
    Confirm:Connect("Activated", function()
        Data:Close(true)
    end)
    Overlay:Connect("Activated", function()
        if not InBounds(PanelItem, Pointer()) then
            Data:Close(false)
        end
    end)
    Library.ActiveConfirmDialog = Data
    return Data
end

Library.RegisterSettingsWidget = function(Self, Data)
    table.insert(Library.SettingsWidgets, Data)
end

Library.CreateSettingsPage = function(Self)
    local Page = Self:Page({ Name = "Settings" })
    local Configs = Page:SubPage({ Name = "Configs" })
    local Other = Page:SubPage({ Name = "Other" })
    local Section = Configs:Section({ Name = "Configs", Side = 1 })
    local Selected, Name = "", ""
    local Dropdown = Section:Dropdown({ Name = "Configs", Flag = "ConfigsDropdown", Callback = function(Value)
        Selected = Value
    end })
    Section:Textbox({ Name = "Config name", Flag = "ConfigName", Placeholder = "Config name ...", Callback = function(Value)
        Name = Value
    end })
    local function Report(Success, Error, Action)
        Library:Notification(Success and (Action .. " config") or tostring(Error), 3,
            Success and Library.Theme.Accent or Library.Theme.Risky)
        Library:GetConfigsList(Dropdown)
    end
    Section:Button({ Name = "Create", Callback = function()
        local Success, Error = Library:SaveConfig(Name)
        Report(Success, Error, "Created")
    end })
    Section:Button({ Name = "Save", Callback = function()
        local Success, Error = Library:SaveConfig(Selected)
        Report(Success, Error, "Saved")
    end })
    Section:Button({ Name = "Load", Callback = function()
        local Success, Error = Library:LoadConfigFile(Selected)
        Report(Success, Error, "Loaded")
    end })
    Section:Button({ Name = "Delete", Callback = function()
        if Selected == "" then
            return
        end
        local Target = Selected
        Library:OpenConfirmDialog({ Title = "Delete config", Message = "Delete " .. Target .. "?", Callback = function(Accepted)
            if Accepted then
                local Success, Error = Library:DeleteConfig(Target)
                Report(Success, Error, "Deleted")
            end
        end })
    end })
    Section:Button({ Name = "Refresh", Callback = function()
        Library:GetConfigsList(Dropdown)
    end })
    Library:GetConfigsList(Dropdown)
    local ThemeSection = Other:Section({ Name = "Theming", Side = 1 })
    local ThemeNames = {}
    for Key in pairs(Library.Theme) do
        table.insert(ThemeNames, Key)
    end
    table.sort(ThemeNames)
    for _, Key in ipairs(ThemeNames) do
        ThemeSection:Label({ Name = Key }):Colorpicker({ Flag = Key .. "Theme", Default = Library.Theme[Key],
            Callback = function(Color)
                Library:ChangeTheme(Key, Color)
            end })
    end
    local Settings = Other:Section({ Name = "Settings", Side = 2 })
    Settings:Label({ Name = "UI Bind" }):Keybind({ Flag = "UIBind", Default = Library.MenuKeybind,
        Callback = function()
            if Library.Flags.UIBind then
                Library.MenuKeybind = Library.Flags.UIBind.Key
            end
        end })
    Settings:Slider({ Name = "Animation Speed", Flag = "AnimationSpeed", Default = Library.Animation.Time,
        Min = 0, Max = 1.5, Decimals = 0.01, Callback = function(Value)
            Library.Animation.Time = Value
        end })
    Settings:Button({ Name = "Unload", Callback = function()
        Library:Exit()
    end })
    if #Library.SettingsWidgets > 0 then
        local Widgets = Other:Section({ Name = "Widgets", Side = 2 })
        for _, Widget in ipairs(Library.SettingsWidgets) do
            local Toggle = Widgets:Toggle(Widget)
            if Widget.Settings then
                Library:SafeCall(Widget.Settings, Toggle:Settings(), Toggle)
            end
        end
    end
    return Page
end

Library.Exit = function(Self)
    if Library.Destroyed then
        return
    end
    Library.Destroyed = true
    Library.Drag, Library.PickingKeybind = nil, nil
    for Connection in pairs(Library.Connections) do
        Connection:Disconnect()
    end
    table.clear(Library.Connections)
    for Thread in pairs(Library.Threads) do
        if Thread ~= coroutine.running() then
            pcall(task.cancel, Thread)
        end
    end
    table.clear(Library.Threads)
    for Tween in pairs(Library.ActiveTweens) do
        Tween:Cancel()
    end
    table.clear(Library.ActiveTweens)
    Library.Holder.Instance:Destroy()
    table.clear(Library.OpenFrames)
    table.clear(Library.PopupRegistry)
    table.clear(Library.CleanupRegistry)
    table.clear(Library.ThemeMap)
    table.clear(Library.SetFlags)
    table.clear(Library.Keybinds)
    table.clear(Library.WindowVisibilityBindings)
    table.clear(Library.VisibilityOwners)
    if Environment.Library == Library then
        Environment.Library = nil
    end
    if Environment.AtaraziaLibrary == Library then
        Environment.AtaraziaLibrary = nil
    end
    if _G.Library == Library then
        _G.Library = nil
    end
end

Library:Connect(UserInputService.InputChanged, function(Input)
    local Drag = Library.Drag
    if Drag and (Input.UserInputType == Enum.UserInputType.MouseMovement
        or (Input.UserInputType == Enum.UserInputType.Touch and Input == Drag.Input)) then
        Drag.Update(Pointer(Input), false)
    end
end)

Library:Connect(UserInputService.InputEnded, function(Input)
    if Library.Drag and ((Input == Library.Drag.Input) or Input.UserInputType == Enum.UserInputType.MouseButton1) then
        Library.Drag = nil
    end
    -- Always release Hold bindings, even if Roblox consumed the release event.
    for Keybind in pairs(Library.Keybinds) do
        if Keybind.Mode == "Hold" and Keybind.Toggled
            and (Keybind.Key == tostring(Input.KeyCode) or Keybind.Key == tostring(Input.UserInputType)) then
            Keybind:Press(false)
        end
    end
end)

Library:Connect(UserInputService.InputBegan, function(Input, Processed)
    if Library.ActiveConfirmDialog then
        if not UserInputService:GetFocusedTextBox() then
            if Input.KeyCode == Enum.KeyCode.Escape then
                Library.ActiveConfirmDialog:Close(false)
            elseif Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.KeypadEnter then
                Library.ActiveConfirmDialog:Close(true)
            end
        end
        return
    end
    if Library.PickingKeybind then
        local Picking = Library.PickingKeybind
        if Input.KeyCode == Enum.KeyCode.Escape then
            Picking:CancelPicking()
        elseif Input.UserInputType == Enum.UserInputType.Keyboard then
            Picking:Set(Input.KeyCode)
        elseif Input.UserInputType == Enum.UserInputType.MouseButton1
            or Input.UserInputType == Enum.UserInputType.MouseButton2
            or Input.UserInputType == Enum.UserInputType.MouseButton3 then
            Picking:Set(Input.UserInputType)
        end
        return
    end
    if Primary(Input) then
        local Point, Close = Pointer(Input), {}
        for PopupData in pairs(Library.OpenFrames) do
            local Inside = InBounds(PopupData.Frame, Point) or InBounds(PopupData.AttachedButton, Point)
            if not Inside then
                for Child in pairs(Library.OpenFrames) do
                    if Child.AttachedButton:IsDescendantOf(PopupData.Frame) and InBounds(Child.Frame, Point) then
                        Inside = true
                        break
                    end
                end
            end
            if not Inside then
                table.insert(Close, PopupData)
            end
        end
        for _, PopupData in ipairs(Close) do
            PopupData:SetOpen(false)
        end
    end
    if UserInputService:GetFocusedTextBox() then
        return
    end
    if Library.MainWindow and (tostring(Input.KeyCode) == Library.MenuKeybind
        or tostring(Input.UserInputType) == Library.MenuKeybind) then
        Library.MainWindow:SetOpen(not Library.WindowOpenState)
        return
    end
    if Processed then
        return
    end
    for Keybind in pairs(Library.Keybinds) do
        if not Keybind.Disabled and Keybind.Key ~= "None" and not Keybind.Picking
            and (tostring(Input.KeyCode) == Keybind.Key or tostring(Input.UserInputType) == Keybind.Key) then
            Keybind:Press(true)
        end
    end
end)

Library:Connect(RunService.RenderStepped, function()
    if next(Library.OpenFrames) then
        Library:GlobalUpdateOpenFrames()
    end
end)

Library:Connect(Library.Root.Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
    if Library.MainWindow then
        Library:ApplyLayoutConfig(Library:GetLayoutConfig())
    end
end)

Environment.AtaraziaLibrary = Library
Environment.Library = Library
_G.Library = Library
return Library
