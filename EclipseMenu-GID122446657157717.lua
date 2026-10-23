



-- SCRIPT LINK
loadstring(game:HttpGet("https://raw.githubusercontent.com/oMaathDev/repo-secret/refs/heads/main/EclipseMenu-GID122446657157717.lua"))()



---- SOURCE CODE [SNIPER ARENA]

-- ECLIPSE MENU | SNIPER ARENA | TOKYO UI (integracao v6.6 - ADVANCED ESP + TARGETING)
-- Base: TokyoLib Example Diagnostico (layout corrigido)
-- Modulos: ESP + Silent Aim extraidos de Eclipse_Menu_Sniper_Arena_Tokyo_UI_Resgate_v5
-- Teclas: F1 ESP | F2 Silent Aim | F3 parar | DELETE abrir/fechar menu
-- OBS: requer Drawing, game:HttpGet, loadstring e, para Silent Aim, debug.getupvalue/setupvalue.
-- Tokyo Lib carregada pelo link RAW publico. Nao requer token nem GitHub API.
-- CORRECAO v6.3: remove overlay modal invisivel em tela cheia e
-- abre/fecha a BIBLIOTECA toda (nao apenas a janela Drawing).
-- DELETE controla o menu sem bloquear botoes/camera do jogo.
-- v6.4: ESP de players/bots, tracers e elementos visuais individuais.
-- v6.5: Skeleton ESP (R6/R15) para players e bots, cores/espessura ajustaveis.
-- v6.6: Chams (Highlight), Head Dot, Visibility Check, Target Highlight,
-- Aim Part Selector e Target Priority, com configuracoes persistentes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[SA] LocalPlayer não disponível.")
    return
end

local Environment = (type(getgenv) == "function" and getgenv()) or _G
local Existing = Environment.__SniperArenaUpdated
if Existing and type(Existing.Start) == "function" then
    if Existing.UISchemaVersion == "Tokyo-Public-v6.6" then
        Existing.Start()
        return
    end
    -- Desligar versao anterior. Seus hooks antigos continuam em pass-through;
    -- reiniciar o cliente remove o legado completamente.
    if type(Existing.Stop) == "function" then pcall(Existing.Stop) end
    if Existing.UIWindow and Existing.UIWindow.Gui then
        pcall(function() Existing.UIWindow.Gui:Destroy() end)
    end
    if Existing.UIBlur then pcall(function() Existing.UIBlur:Destroy() end) end -- menu legado Neverlose
end

local Settings = {
    Enabled = true,
    FOVRadius = 180,
    AimAtScreenCenter = true,  -- recomendado para touch/BlueStacks
    WallCheck = true,
    AimPart = "Auto",           -- Auto, Head, Torso, Root
    TargetPriority = "Crosshair", -- Crosshair, Distance, Lowest HP
    TargetHighlightEnabled = false,
    TargetHighlightColor = Color3.fromRGB(255, 210, 70),
    TargetHighlightSize = 13,
    ShowFOVCircle = true,
    FOVColor = Color3.fromRGB(255, 255, 255),
    ESPEnabled = true,
    ESPPlayersEnabled = true,
    ESPBotsEnabled = true,
    ESPShowBoxes = true,
    ESPShowNames = true,
    ESPShowDistance = true,
    ESPShowHealthBar = true,
    ESPTracersEnabled = false,
    ESPTracerPlayers = true,
    ESPTracerBots = true,
    ESPTracerFromBottom = true,
    ESPTracerThickness = 1.5,
    ESPTracerColor = Color3.fromRGB(180, 130, 255),
    ESPSkeletonEnabled = false,
    ESPSkeletonPlayers = true,
    ESPSkeletonBots = true,
    ESPSkeletonThickness = 1.5,
    ESPSkeletonColor = Color3.fromRGB(190, 165, 255),
    ESPSkeletonBotColor = Color3.fromRGB(255, 195, 75),
    ESPBotColor = Color3.fromRGB(255, 190, 70),
    ESPChamsEnabled = false,
    ESPChamsPlayers = true,
    ESPChamsBots = true,
    ESPChamsThroughWalls = true,
    ESPChamsFillTransparency = 0.55,
    ESPChamsOutlineTransparency = 0,
    ESPChamsPlayerColor = Color3.fromRGB(175, 95, 255),
    ESPChamsBotColor = Color3.fromRGB(255, 170, 60),
    ESPHeadDotEnabled = false,
    ESPHeadDotPlayers = true,
    ESPHeadDotBots = true,
    ESPHeadDotRadius = 4,
    ESPHeadDotColor = Color3.fromRGB(255, 255, 130),
    ESPVisibilityCheck = false,
    ESPVisibleColor = Color3.fromRGB(75, 255, 145),
    ESPOccludedColor = Color3.fromRGB(255, 80, 95),
    ESPMaxDistance = 2000, -- studs
    ESPUpdateFPS = 30,
    ESPEnemiesOnly = true,
    ESPBoxColor = Color3.fromRGB(255, 50, 50),
    ESPNameColor = Color3.fromRGB(255, 255, 255),
}

local EntityService = require(ReplicatedStorage.Remote.EntityService)
local ClientShootableComponent = require(
    ReplicatedStorage.Client.CombatController.ClientComponent.ClientShootableComponent
)

local State = {
    Active = false,
    Settings = Settings,
    Connections = {},
    ShotTargets = setmetatable({}, { __mode = "k" }),
    ShootPatch = nil,
    ShotsChecked = 0,
    ShotsWithTarget = 0,
    RedirectedShots = 0,
    UISchemaVersion = "Tokyo-Public-v6.6",
    TargetSelection = nil,
    TargetSelectionUntil = 0,
    UIWindow = nil,
    UILibrary = nil,
    UIVisible = false,
    UIKind = nil,
    UIRoot = nil,
    UIFrame = nil,
    NativeScreenGui = nil,
    Controls = {},
}

local Camera = workspace.CurrentCamera
local FOVCircle = nil
local ESPData = {}
local ChamsData = {} -- Highlight criado no proprio rig; limpo ao trocar/encerrar
local TargetMarker = nil
local MAIN_THREAD = {}
local warnings = {}

local function WarnOnce(key, message)
    if warnings[key] then return end
    warnings[key] = true
    warn("[SA] " .. tostring(message))
end

local function Track(connection)
    table.insert(State.Connections, connection)
    return connection
end

local function NewDrawing(kind, properties)
    local drawing = Drawing.new(kind)
    drawing.Visible = false
    for key, value in pairs(properties) do
        drawing[key] = value
    end
    return drawing
end

-- O v6.4 separa players de bots; todos os Drawings sao reutilizados.
local BotESPData = {}
local BotEntityByModel = {}
local EntityModel -- declarado aqui; implementado adiante para o Silent Aim.

local function HideESP(drawings)
    for _, drawing in pairs(drawings) do
        drawing.Visible = false
    end
end

local function RemoveDrawingSet(storage, key)
    local drawings = storage[key]
    if not drawings then return end
    for _, drawing in pairs(drawings) do
        pcall(function() drawing:Remove() end)
    end
    storage[key] = nil
end

local function RemoveChams(model)
    local highlight = model and ChamsData[model]
    if highlight then
        pcall(function() highlight:Destroy() end)
        ChamsData[model] = nil
    end
end

local function HideChams(model)
    local highlight = model and ChamsData[model]
    if highlight then highlight.Enabled = false end
end

local function HideAllChams()
    for _, highlight in pairs(ChamsData) do
        highlight.Enabled = false
    end
end

local function ClearOrphanChams()
    for model in pairs(ChamsData) do
        if not model.Parent or not model:IsDescendantOf(workspace) then
            RemoveChams(model)
        end
    end
end

local function RemoveESP(player)
    RemoveDrawingSet(ESPData, player)
    if player and player.Character then RemoveChams(player.Character) end
end

local function RemoveBotESP(model)
    RemoveDrawingSet(BotESPData, model)
    BotEntityByModel[model] = nil
    RemoveChams(model)
end

local function MakeESPDrawings(label, boxColor)
    return {
        Outline = NewDrawing("Square", {
            Color = Color3.new(0, 0, 0), Thickness = 3, Filled = false,
        }),
        Box = NewDrawing("Square", {
            Color = boxColor, Thickness = 1.5, Filled = false,
        }),
        Name = NewDrawing("Text", {
            Color = Settings.ESPNameColor, Size = 14, Center = true,
            Outline = true, OutlineColor = Color3.new(0, 0, 0), Text = label,
        }),
        Dist = NewDrawing("Text", {
            Color = Color3.fromRGB(180, 180, 180), Size = 12,
            Center = true, Outline = true, OutlineColor = Color3.new(0, 0, 0),
        }),
        HpBg = NewDrawing("Square", {
            Color = Color3.new(0, 0, 0), Thickness = 1, Filled = true,
        }),
        Hp = NewDrawing("Square", {
            Color = Color3.fromRGB(50, 255, 50), Thickness = 1, Filled = true,
        }),
        Tracer = NewDrawing("Line", {
            Color = Settings.ESPTracerColor, Thickness = Settings.ESPTracerThickness,
            Transparency = 1,
        }),
        HeadDot = NewDrawing("Circle", {
            Color = Settings.ESPHeadDotColor, Thickness = 1.5, Radius = Settings.ESPHeadDotRadius,
            Filled = true, NumSides = 24, Transparency = 1,
        }),
    }
end

local function AddESP(player)
    if player == LocalPlayer or ESPData[player] then return end
    ESPData[player] = MakeESPDrawings(player.DisplayName or player.Name, Settings.ESPBoxColor)
end

local function IsTeammate(player)
    return player ~= LocalPlayer
        and not LocalPlayer.Neutral
        and not player.Neutral
        and LocalPlayer.Team ~= nil
        and player.Team == LocalPlayer.Team
end

local function IsPlayerCharacter(model)
    if not (model and model:IsA("Model")) then return false end
    if Players:GetPlayerFromCharacter(model) then return true end
    -- Personagens com submodels/humanoids de cosmeticos nao sao bots.
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character and (model == character or model:IsDescendantOf(character)) then
            return true
        end
    end
    return false
end

local function RegisterBot(model, entity)
    if not State.Active or not (model and model:IsA("Model")) then return end
    if not model:IsDescendantOf(workspace) or IsPlayerCharacter(model) then return end
    if not BotESPData[model] then
        BotESPData[model] = MakeESPDrawings(model.Name, Settings.ESPBotColor)
    end
    if entity then BotEntityByModel[model] = entity end
end

-- EntityService cobre bots com controladores de combate personalizados.
-- O registro por Humanoid cobre NPCs convencionais no Workspace.
local function RefreshBotEntities()
    if not State.Active or not Settings.ESPBotsEnabled then return end
    local ok, err = pcall(function()
        for _, entity in EntityService.Entity.GetAll() do
            local model = EntityModel(entity)
            if model then RegisterBot(model, entity) end
        end
    end)
    if not ok then
        WarnOnce("npc_entities", "Nao foi possivel ler bots via EntityService: " .. tostring(err))
    end
end

local function ScanExistingHumanoids()
    local descendants = workspace:GetDescendants()
    for index, instance in ipairs(descendants) do
        if not State.Active then return end
        if instance:IsA("Humanoid") then
            local model = instance.Parent
            if model and model:IsA("Model") then RegisterBot(model) end
        end
        if index % 1500 == 0 then task.wait() end -- evita congelar o jogo
    end
    RefreshBotEntities()
end

local function ReadHealth(model, humanoid)
    if humanoid then
        return humanoid.Health, humanoid.MaxHealth
    end
    -- Alguns bots usam atributos customizados em vez de Humanoid.
    local health = model:GetAttribute("Health")
    local maximum = model:GetAttribute("MaxHealth")
    if type(health) == "number" and type(maximum) == "number" then
        return health, maximum
    end
    return nil, nil
end

-- Visibility Check usa raycast local da camera ao alvo. Nunca altera hitboxes.
local function IsModelVisible(model, head, camera)
    if not Settings.ESPVisibilityCheck then return true end
    local cameraPosition = camera.CFrame.Position
    local vector = head.Position - cameraPosition
    if vector.Magnitude < 0.01 then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local character = LocalPlayer.Character
    params.FilterDescendantsInstances = character and {character} or {}
    local result = workspace:Raycast(cameraPosition, vector, params)
    return not result or result.Instance:IsDescendantOf(model)
end

local function VisibilityColor(base, visible)
    if not Settings.ESPVisibilityCheck then return base end
    return visible and Settings.ESPVisibleColor or Settings.ESPOccludedColor
end

local function UpdateChams(model, kind, visible)
    local enabled = Settings.ESPEnabled and Settings.ESPChamsEnabled
        and ((kind == "player" and Settings.ESPChamsPlayers)
        or (kind == "bot" and Settings.ESPChamsBots))
    if not enabled then
        HideChams(model)
        return
    end
    local h = ChamsData[model]
    if not h then
        local ok, result = pcall(function()
            local highlight = Instance.new("Highlight")
            highlight.Name = "EclipseChamsLocal"
            highlight.Adornee = model
            highlight.Parent = model
            return highlight
        end)
        if not ok then
            WarnOnce("chams_create", "Nao foi possivel criar Highlight: " .. tostring(result))
            return
        end
        h = result
        ChamsData[model] = h
    end
    local base = kind == "bot" and Settings.ESPChamsBotColor or Settings.ESPChamsPlayerColor
    local color = VisibilityColor(base, visible)
    h.FillColor = color
    h.OutlineColor = color
    h.FillTransparency = Settings.ESPChamsFillTransparency
    h.OutlineTransparency = Settings.ESPChamsOutlineTransparency
    h.DepthMode = Settings.ESPChamsThroughWalls
        and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    h.Enabled = true
end

-- Skeleton ESP - linhas 2D seguindo articulacoes dos rigs R15 e R6.
-- Drawings sao criados sob demanda: zero custo extra de linhas quando desligado.
-- As chaves sao objetos Drawing individuais, compatíveis com HideESP/RemoveDrawingSet.
local MAX_SKELETON_SEGMENTS = 20

local function HideSkeleton(drawings)
    for index = 1, MAX_SKELETON_SEGMENTS do
        local bone = drawings["Bone" .. index]
        if bone then bone.Visible = false end
    end
end

local function RenderSkeleton(drawings, model, kind, camera, visible)
    local active = Settings.ESPSkeletonEnabled
        and ((kind == "player" and Settings.ESPSkeletonPlayers)
            or (kind == "bot" and Settings.ESPSkeletonBots))
    if not active then
        HideSkeleton(drawings)
        return
    end

    local color = VisibilityColor(kind == "bot" and Settings.ESPSkeletonBotColor or Settings.ESPSkeletonColor, visible)
    local thickness = Settings.ESPSkeletonThickness
    local used = 0

    local function part(name)
        local object = model:FindFirstChild(name, true)
        if object and object:IsA("BasePart") then return object end
        return nil
    end

    local function attachment(partObject, attachmentName, fallback)
        if partObject then
            local object = partObject:FindFirstChild(attachmentName)
            if object and object:IsA("Attachment") then return object.WorldPosition end
        end
        return fallback
    end

    -- Desenha cada segmento no momento da coleta, evitando novas tabelas por frame.
    local function link(pointA, pointB)
        if used >= MAX_SKELETON_SEGMENTS
            or typeof(pointA) ~= "Vector3" or typeof(pointB) ~= "Vector3" then
            return
        end
        used += 1
        local key = "Bone" .. used
        local bone = drawings[key]
        if not bone then
            bone = NewDrawing("Line", {
                Color = color, Thickness = thickness, Transparency = 1,
            })
            drawings[key] = bone
        end

        local point2A, visibleA = camera:WorldToViewportPoint(pointA)
        local point2B, visibleB = camera:WorldToViewportPoint(pointB)
        if point2A.Z <= 0 or point2B.Z <= 0 or (not visibleA and not visibleB) then
            bone.Visible = false
            return
        end
        bone.From = Vector2.new(point2A.X, point2A.Y)
        bone.To = Vector2.new(point2B.X, point2B.Y)
        bone.Color = color
        bone.Thickness = thickness
        bone.Visible = true
    end

    local head = part("Head")
    local upper = part("UpperTorso")
    local lower = part("LowerTorso")
    local torso = part("Torso")

    if upper then
        -- R15: pescoco, coluna e membros com pontos reais dos RigAttachments.
        local pelvis = lower or part("HumanoidRootPart")
        local neck = attachment(upper, "NeckRigAttachment",
            upper.CFrame:PointToWorldSpace(Vector3.new(0, upper.Size.Y * 0.5, 0)))
        if head then link(head.Position, neck) end
        link(neck, upper.Position)
        if pelvis then link(upper.Position, pelvis.Position) end

        for _, side in ipairs({ "Left", "Right" }) do
            local upperArm = part(side .. "UpperArm")
            local lowerArm = part(side .. "LowerArm")
            local hand = part(side .. "Hand")
            if upperArm then
                local shoulder = attachment(upper, side .. "ShoulderRigAttachment",
                    attachment(upperArm, side .. "ShoulderRigAttachment", upperArm.Position))
                link(upper.Position, shoulder)
                if lowerArm then
                    local elbow = attachment(upperArm, side .. "ElbowRigAttachment",
                        attachment(lowerArm, side .. "ElbowRigAttachment",
                            (upperArm.Position + lowerArm.Position) * 0.5))
                    link(shoulder, elbow)
                    if hand then
                        local wrist = attachment(lowerArm, side .. "WristRigAttachment",
                            attachment(hand, side .. "WristRigAttachment",
                                (lowerArm.Position + hand.Position) * 0.5))
                        link(elbow, wrist)
                        link(wrist, hand.Position)
                    else
                        link(elbow, lowerArm.Position)
                    end
                else
                    link(shoulder, upperArm.Position)
                end
            end

            local upperLeg = part(side .. "UpperLeg")
            local lowerLeg = part(side .. "LowerLeg")
            local foot = part(side .. "Foot")
            if pelvis and upperLeg then
                local hip = attachment(pelvis, side .. "HipRigAttachment",
                    attachment(upperLeg, side .. "HipRigAttachment", upperLeg.Position))
                link(pelvis.Position, hip)
                if lowerLeg then
                    local knee = attachment(upperLeg, side .. "KneeRigAttachment",
                        attachment(lowerLeg, side .. "KneeRigAttachment",
                            (upperLeg.Position + lowerLeg.Position) * 0.5))
                    link(hip, knee)
                    if foot then
                        local ankle = attachment(lowerLeg, side .. "AnkleRigAttachment",
                            attachment(foot, side .. "AnkleRigAttachment",
                                (lowerLeg.Position + foot.Position) * 0.5))
                        link(knee, ankle)
                        link(ankle, foot.Position)
                    else
                        link(knee, lowerLeg.Position)
                    end
                else
                    link(hip, upperLeg.Position)
                end
            end
        end
    elseif torso then
        -- R6: usa o eixo local do torso para ombros, quadris e pontas dos membros.
        local neck = torso.CFrame:PointToWorldSpace(Vector3.new(0, torso.Size.Y * 0.5, 0))
        local pelvis = torso.CFrame:PointToWorldSpace(Vector3.new(0, -torso.Size.Y * 0.5, 0))
        if head then link(head.Position, neck) end
        link(neck, torso.Position)
        link(torso.Position, pelvis)

        for _, side in ipairs({ "Left", "Right" }) do
            local sign = side == "Left" and -1 or 1
            local arm = part(side .. " Arm")
            local leg = part(side .. " Leg")
            if arm then
                local shoulder = torso.CFrame:PointToWorldSpace(Vector3.new(
                    sign * torso.Size.X * 0.5, torso.Size.Y * 0.35, 0))
                link(torso.Position, shoulder)
                link(shoulder, arm.Position)
                link(arm.Position, arm.CFrame:PointToWorldSpace(Vector3.new(0, -arm.Size.Y * 0.5, 0)))
            end
            if leg then
                local hip = torso.CFrame:PointToWorldSpace(Vector3.new(
                    sign * torso.Size.X * 0.25, -torso.Size.Y * 0.5, 0))
                link(pelvis, hip)
                link(hip, leg.Position)
                link(leg.Position, leg.CFrame:PointToWorldSpace(Vector3.new(0, -leg.Size.Y * 0.5, 0)))
            end
        end
    else
        -- NPC customizado: mostra apenas coluna quando nao ha membros R6/R15.
        local root = part("HumanoidRootPart") or model.PrimaryPart
        if head and root and root:IsA("BasePart") then
            link(head.Position, root.Position)
        end
    end

    -- Evita linhas antigas ao trocar de rig, ressurgir ou perder partes.
    for index = used + 1, MAX_SKELETON_SEGMENTS do
        local bone = drawings["Bone" .. index]
        if bone then bone.Visible = false end
    end
end

local function DrawESPForModel(drawings, model, label, kind, camera, localRoot)
    if not model or not model:IsDescendantOf(workspace) then
        HideESP(drawings)
        HideChams(model)
        return
    end

    local head = model:FindFirstChild("Head", true)
    local root = model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart or model:FindFirstChild("Torso", true)
        or model:FindFirstChild("UpperTorso", true)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not (head and head:IsA("BasePart") and root and root:IsA("BasePart")) then
        HideESP(drawings)
        HideChams(model)
        return
    end
    if humanoid and humanoid.Health <= 0 then
        HideESP(drawings)
        HideChams(model)
        return
    end
    if kind == "player" and not humanoid then
        HideESP(drawings)
        HideChams(model)
        return
    end
    local entity = kind == "bot" and BotEntityByModel[model] or nil
    if kind == "bot" and not humanoid and not entity then
        HideESP(drawings)
        HideChams(model)
        return
    end
    if entity then
        local ok, alive = pcall(function()
            if type(entity.IsAlive) == "function" then
                return entity:IsAlive()
            end
            return nil
        end)
        if ok and alive == false then
            HideESP(drawings)
            HideChams(model)
            return
        end
    end

    local distance = (localRoot.Position - root.Position).Magnitude
    if distance > Settings.ESPMaxDistance then
        HideESP(drawings)
        HideChams(model)
        return
    end

    local visible = IsModelVisible(model, head, camera)
    -- Chams acompanha NPCs mesmo fora da tela; Drawings 2D so aparecem na tela.
    UpdateChams(model, kind, visible)

    local top, topOnScreen = camera:WorldToViewportPoint(
        head.Position + Vector3.new(0, head.Size.Y / 2, 0)
    )
    local bottom, bottomOnScreen = camera:WorldToViewportPoint(
        root.Position - Vector3.new(0, 3, 0)
    )
    if top.Z <= 0 or bottom.Z <= 0 or (not topOnScreen and not bottomOnScreen) then
        HideESP(drawings)
        return -- Highlight permanece ativo mesmo sem coordenada 2D
    end

    local height = math.abs(bottom.Y - top.Y)
    if height < 3 or height > camera.ViewportSize.Y * 3 then
        HideESP(drawings)
        return
    end
    local width = height * 0.6
    local x = (top.X + bottom.X) / 2 - width / 2
    local y = math.min(top.Y, bottom.Y)
    local boxColor = kind == "bot" and Settings.ESPBotColor or Settings.ESPBoxColor
    local centerX = x + width / 2

    -- Caixas e borda podem ser desligadas sem alterar os outros elementos.
    local showBoxes = Settings.ESPShowBoxes
    drawings.Outline.Size = Vector2.new(width, height)
    drawings.Outline.Position = Vector2.new(x, y)
    drawings.Outline.Visible = showBoxes
    drawings.Box.Size = Vector2.new(width, height)
    drawings.Box.Position = Vector2.new(x, y)
    local selected = Settings.TargetHighlightEnabled
        and State.TargetSelection and State.TargetSelection.Model == model
        and os.clock() <= State.TargetSelectionUntil
    drawings.Box.Color = selected and Settings.TargetHighlightColor
        or VisibilityColor(boxColor, visible)
    drawings.Box.Thickness = selected and 2.5 or 1.5
    drawings.Box.Visible = showBoxes

    drawings.Name.Text = label
    drawings.Name.Position = Vector2.new(centerX, y - 16)
    drawings.Name.Color = Settings.ESPNameColor
    drawings.Name.Visible = Settings.ESPShowNames

    drawings.Dist.Text = string.format("%d studs", math.floor(distance + 0.5))
    drawings.Dist.Position = Vector2.new(centerX, y + height + 2)
    drawings.Dist.Visible = Settings.ESPShowDistance

    local health, maxHealth = ReadHealth(model, humanoid)
    local showHealth = Settings.ESPShowHealthBar and health ~= nil
        and type(maxHealth) == "number" and maxHealth > 0
    drawings.HpBg.Visible = showHealth
    drawings.Hp.Visible = false
    if showHealth then
        local ratio = math.clamp(health / maxHealth, 0, 1)
        local filledHeight = height * ratio
        local barX = x - 6
        drawings.HpBg.Size = Vector2.new(4, height)
        drawings.HpBg.Position = Vector2.new(barX, y)
        drawings.Hp.Size = Vector2.new(4, filledHeight)
        drawings.Hp.Position = Vector2.new(barX, y + height - filledHeight)
        drawings.Hp.Color = Color3.fromRGB(
            math.floor(255 * (1 - ratio)), math.floor(255 * ratio), 0
        )
        drawings.Hp.Visible = filledHeight > 0
    end

    -- Head Dot em jogadores e bots, com tamanho e cor independentes.
    local dotEnabled = Settings.ESPHeadDotEnabled
        and ((kind == "player" and Settings.ESPHeadDotPlayers)
            or (kind == "bot" and Settings.ESPHeadDotBots))
    local headScreen, headOnScreen = camera:WorldToViewportPoint(head.Position)
    drawings.HeadDot.Visible = dotEnabled and headOnScreen and headScreen.Z > 0
    if drawings.HeadDot.Visible then
        drawings.HeadDot.Position = Vector2.new(headScreen.X, headScreen.Y)
        drawings.HeadDot.Radius = Settings.ESPHeadDotRadius
        drawings.HeadDot.Color = VisibilityColor(Settings.ESPHeadDotColor, visible)
    end

    -- Skeleton independente de caixas, nomes, barra e tracers.
    RenderSkeleton(drawings, model, kind, camera, visible)

    -- Tracer: da base ou do centro da tela ate os pes do alvo.
    local showTracer = Settings.ESPTracersEnabled
        and (kind == "bot" and Settings.ESPTracerBots
            or kind == "player" and Settings.ESPTracerPlayers)
    drawings.Tracer.Visible = showTracer
    if showTracer then
        local viewport = camera.ViewportSize
        drawings.Tracer.From = Settings.ESPTracerFromBottom
            and Vector2.new(viewport.X * 0.5, viewport.Y - 3)
            or Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
        drawings.Tracer.To = Vector2.new(centerX, y + height)
        drawings.Tracer.Color = VisibilityColor(Settings.ESPTracerColor, visible)
        drawings.Tracer.Thickness = Settings.ESPTracerThickness
    end
end

local function UpdateESP()
    local camera = Camera
    if not State.Active or not Settings.ESPEnabled or not camera then
        for _, drawings in pairs(ESPData) do HideESP(drawings) end
        for _, drawings in pairs(BotESPData) do HideESP(drawings) end
        HideAllChams()
        return
    end
    local localCharacter = LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        for _, drawings in pairs(ESPData) do HideESP(drawings) end
        for _, drawings in pairs(BotESPData) do HideESP(drawings) end
        HideAllChams()
        return
    end

    for player, drawings in pairs(ESPData) do
        if not Settings.ESPPlayersEnabled
            or (Settings.ESPEnemiesOnly and IsTeammate(player)) then
            HideESP(drawings)
            HideChams(player.Character)
        else
            DrawESPForModel(drawings, player.Character,
                player.DisplayName or player.Name, "player", camera, localRoot)
        end
    end

    for model, drawings in pairs(BotESPData) do
        if not model.Parent or not model:IsDescendantOf(workspace) or IsPlayerCharacter(model) then
            RemoveBotESP(model)
        elseif Settings.ESPBotsEnabled then
            DrawESPForModel(drawings, model, model.Name, "bot", camera, localRoot)
        else
            HideESP(drawings)
            HideChams(model)
        end
    end
    ClearOrphanChams()
end

-- A referencia visual e a mesma usada para a busca de alvos.
-- No BlueStacks/controle por toque o ponteiro do mouse nao corresponde
-- necessariamente a mira; por padrao usar o centro do viewport.
local function GetAimScreenPoint()
    local camera = Camera or workspace.CurrentCamera
    if not camera then return Vector2.zero end
    if Settings.AimAtScreenCenter
        or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
        or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
        return camera.ViewportSize * 0.5
    end
    return UserInputService:GetMouseLocation()
end

local function ThreadKey()
    return coroutine.running() or MAIN_THREAD
end

-- A assinatura de debug.getupvalue depende do executor:
-- alguns retornam (nome, valor); outros retornam apenas valor.
local function ReadUpvalue(fn, index)
    if not debug or type(debug.getupvalue) ~= "function" then return nil end
    local ok, a, b = pcall(debug.getupvalue, fn, index)
    if not ok then return nil end
    if type(a) == "string" then return b end
    return a
end

local function FindSharedOrigin(shoot, localShoot)
    local matches = {}
    for i = 1, 80 do
        local candidate = ReadUpvalue(shoot, i)
        if type(candidate) == "function" then
            for j = 1, 80 do
                local other = ReadUpvalue(localShoot, j)
                if other == candidate then
                    table.insert(matches, { Index = i, Function = candidate })
                    break
                end
            end
        end
    end
    if #matches ~= 1 then return nil, nil, #matches end
    return matches[1].Index, matches[1].Function, #matches
end

EntityModel = function(entity)
    local ok, model = pcall(function() return entity:GetModel() end)
    if ok and typeof(model) == "Instance" and model:IsA("Model") then
        return model
    end
    local instance = entity.Instance
    if typeof(instance) ~= "Instance" then return nil end
    if instance:IsA("Player") then return instance.Character end
    if instance:IsA("Model") then return instance end
    return nil
end

local function IsEnemy(selfEntity, other)
    if not other or other == selfEntity then return false end
    local okAlive, alive = pcall(function() return other:IsAlive() end)
    if not okAlive or not alive then return false end
    local okFriend, friendly = pcall(function() return selfEntity:IsFriendly(other) end)
    if okFriend then return not friendly end
    -- Fallback caso IsFriendly nao exista nesta versao do jogo.
    local selfTeam = selfEntity.Team or selfEntity.TeamId
    local theirTeam = other.Team or other.TeamId
    return selfTeam == nil or theirTeam == nil or selfTeam ~= theirTeam
end

local function CreateRayParams(selfEntity)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = false
    local ownModel = EntityModel(selfEntity)
    params.FilterDescendantsInstances = ownModel and { ownModel } or {}

    -- O jogo usa um grupo de colisao de ataque especifico.
    local okCollision, collision = pcall(function()
        return require(ReplicatedStorage.Constant).Collision
    end)
    if okCollision and collision and collision.Attack then
        local okGroup, group = pcall(function()
            return selfEntity:GetCollision(collision.Attack)
        end)
        if okGroup and type(group) == "string" then
            pcall(function() params.CollisionGroup = group end)
        end
    end
    return params
end

local function MaxBulletDistance()
    local ok, config = pcall(function()
        return require(ReplicatedStorage.Config.Config)
    end)
    if ok and config and config.Combat
        and type(config.Combat.BulletMaxDistance) == "number" then
        return config.Combat.BulletMaxDistance
    end
    return 3000
end

local CONE_DOT = math.cos(math.rad(15))
local okHumanoidAPI, HumanoidEntity = pcall(function()
    return require(ReplicatedStorage.Remote.EntityService.Entity.HumanoidEntity)
end)

-- Prioridade nao ignora a validacao por FOV, cone, distancia e paredes.
local function AimPartCandidates()
    if Settings.AimPart == "Head" then return {"Head"} end
    if Settings.AimPart == "Torso" then return {"UpperTorso", "Torso", "LowerTorso"} end
    if Settings.AimPart == "Root" then return {"HumanoidRootPart"} end
    return {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
end

local function FindShotTarget(origin)
    local camera = Camera or workspace.CurrentCamera
    if not camera then return nil end
    local selfEntity = EntityService.GetLocalEntity()
    if not selfEntity then return nil end
    local aliveOK, alive = pcall(function() return selfEntity:IsAlive() end)
    if not aliveOK or not alive then return nil end
    local point2D = GetAimScreenPoint()
    local radiusSquared = Settings.FOVRadius * Settings.FOVRadius
    local rayParams = Settings.WallCheck and CreateRayParams(selfEntity) or nil
    local maxDistance = MaxBulletDistance()
    local winner, bestPrimary, bestCrosshair = nil, math.huge, math.huge
    local candidates = AimPartCandidates()

    for _, entity in EntityService.Entity.GetAll() do
        if not IsEnemy(selfEntity, entity) then continue end
        if okHumanoidAPI then
            local okType, isHumanoid = pcall(function() return HumanoidEntity:is(entity) end)
            if okType and not isHumanoid then continue end
        end
        local model = EntityModel(entity)
        if not model or not model:IsDescendantOf(workspace) then continue end

        -- Uma regiao valida por entidade: no Auto, Head tem preferencia.
        for _, partName in ipairs(candidates) do
            local part = model:FindFirstChild(partName, true)
            if not part or not part:IsA("BasePart") then continue end
            local point = part.Position
            local delta = point - origin.Position
            local distance = delta.Magnitude
            if distance < 0.01 or distance > maxDistance then continue end
            if origin.LookVector:Dot(delta.Unit) < CONE_DOT then continue end
            local screen, onScreen = camera:WorldToViewportPoint(point)
            if not onScreen or screen.Z <= 0 then continue end
            local dx, dy = screen.X - point2D.X, screen.Y - point2D.Y
            local crosshairScore = dx * dx + dy * dy
            if crosshairScore > radiusSquared then continue end

            local hitPart = part
            if rayParams then
                local hit = workspace:Raycast(origin.Position, delta, rayParams)
                if not hit or not hit.Instance:IsDescendantOf(model) then continue end
                hitPart = hit.Instance
            end

            local primaryScore = crosshairScore
            if Settings.TargetPriority == "Distance" then
                primaryScore = distance
            elseif Settings.TargetPriority == "Lowest HP" then
                local hp, maxHp = ReadHealth(model, model:FindFirstChildOfClass("Humanoid"))
                primaryScore = (hp and maxHp and maxHp > 0)
                    and math.clamp(hp / maxHp, 0, 1) or 1
            end
            if primaryScore < bestPrimary
                or (primaryScore == bestPrimary and crosshairScore < bestCrosshair) then
                local okPivot, pivot = pcall(function() return entity:GetPivot(true) end)
                if not okPivot or typeof(pivot) ~= "CFrame" then
                    okPivot, pivot = pcall(function() return model:GetPivot() end)
                end
                if okPivot and typeof(pivot) == "CFrame" then
                    winner = {Entity = entity, Model = model, Part = hitPart,
                        Point = point, Pivot = pivot}
                    bestPrimary, bestCrosshair = primaryScore, crosshairScore
                end
            end
            break -- primeira regiao valida deste personagem
        end
    end
    return winner
end

-- Indicador de alvo: Drawing unico (nao cria Highlights adicionais).
local function UpdateTargetMarker()
    if not TargetMarker then return end
    local candidate = State.TargetSelection
    if not (State.Active and Settings.Enabled and Settings.TargetHighlightEnabled
        and candidate and candidate.Model and candidate.Model:IsDescendantOf(workspace)
        and os.clock() <= State.TargetSelectionUntil) then
        TargetMarker.Visible = false
        return
    end
    local camera = Camera or workspace.CurrentCamera
    if not camera then
        TargetMarker.Visible = false
        return
    end
    local screen, onScreen = camera:WorldToViewportPoint(candidate.Point)
    if not onScreen or screen.Z <= 0 then
        TargetMarker.Visible = false
        return
    end
    TargetMarker.Position = Vector2.new(screen.X, screen.Y)
    TargetMarker.Radius = Settings.TargetHighlightSize
    TargetMarker.Color = Settings.TargetHighlightColor
    TargetMarker.Visible = true
end

-- Em versoes recentes o tiro final acontece via Shoot(), e nao apenas
-- via LocalShoot(). Alem da direcao, o contexto inclui Target e TargetPos.
local function InstallShotHooks()
    if State.ShootPatch then return true end
    if not debug or type(debug.getupvalue) ~= "function"
        or type(debug.setupvalue) ~= "function" then
        WarnOnce("shoot_debug", "Silent Aim requer debug.getupvalue e debug.setupvalue neste executor.")
        return false
    end
    local originalShoot = ClientShootableComponent.Shoot
    local localShoot = ClientShootableComponent.LocalShoot
    if type(originalShoot) ~= "function" or type(localShoot) ~= "function" then
        WarnOnce("shoot_functions", "Shoot/LocalShoot indisponiveis; atualizacao do jogo pode ter mudado as funcoes.")
        return false
    end
    local originIndex, originalOrigin, numberOfMatches = FindSharedOrigin(originalShoot, localShoot)
    if not originIndex then
        WarnOnce("shoot_origin", "Nao foi possivel localizar origem compartilhada do disparo (correspondencias: " .. tostring(numberOfMatches) .. ").")
        return false
    end

    local redirectedOrigin = function(...)
        local results = table.pack(originalOrigin(...))
        local prepared = State.ShotTargets[ThreadKey()]
        if State.Active and Settings.Enabled and prepared
            and typeof(results[1]) == "CFrame" then
            local frame = results[1]
            local diff = prepared.Point - frame.Position
            if diff.Magnitude > 0.001 and frame.LookVector:Dot(diff.Unit) >= CONE_DOT then
                results[1] = CFrame.lookAt(frame.Position, prepared.Point)
                State.RedirectedShots += 1
            end
        end
        return table.unpack(results, 1, results.n)
    end

    local wrappedShoot = function(component, startPosition, direction, context, ...)
        if not State.Active or not Settings.Enabled then
            return originalShoot(component, startPosition, direction, context, ...)
        end
        State.ShotsChecked += 1
        local gotOrigin, frame = pcall(originalOrigin)
        local target = nil
        if gotOrigin and typeof(frame) == "CFrame" then
            local okTarget, targetOrError = pcall(FindShotTarget, frame)
            if okTarget then
                target = targetOrError
            else
                WarnOnce("target_selection", "Falha ao selecionar alvo: " .. tostring(targetOrError))
            end
        else
            WarnOnce("origin_read", "Nao foi possivel ler a origem do disparo.")
        end

        local shotContext = context
        if target then
            State.TargetSelection = target
            State.TargetSelectionUntil = os.clock() + 0.45
            if type(shotContext) ~= "table" then shotContext = {} end
            shotContext.Target = target.Entity.Instance
            shotContext.TargetPos = target.Pivot:PointToObjectSpace(target.Point)
            shotContext.TargetHeadshot = target.Part and target.Part.Name == "Head" or false
            State.ShotsWithTarget += 1
        end

        local key = ThreadKey()
        local previous = State.ShotTargets[key]
        State.ShotTargets[key] = target
        local result = table.pack(pcall(originalShoot,
            component, startPosition, direction, shotContext, ...))
        State.ShotTargets[key] = previous
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end

    local okPatch, reason = pcall(function()
        debug.setupvalue(originalShoot, originIndex, redirectedOrigin)
        assert(ReadUpvalue(originalShoot, originIndex) == redirectedOrigin,
            "setupvalue nao conseguiu atualizar a origem")
        ClientShootableComponent.Shoot = wrappedShoot
        assert(ClientShootableComponent.Shoot == wrappedShoot, "Shoot nao aceita substituicao")
    end)
    if not okPatch then
        pcall(function()
            if ReadUpvalue(originalShoot, originIndex) == redirectedOrigin then
                debug.setupvalue(originalShoot, originIndex, originalOrigin)
            end
        end)
        WarnOnce("shoot_patch", "Falha ao instalar Silent Aim: " .. tostring(reason))
        return false
    end
    State.ShootPatch = {
        OriginalShoot = originalShoot, PatchedShoot = wrappedShoot,
        OriginIndex = originIndex, OriginalOrigin = originalOrigin,
        PatchedOrigin = redirectedOrigin,
    }
    print("[SA] Silent Aim v2 pronto: Shoot/contexto/origem (centro da tela: " .. tostring(Settings.AimAtScreenCenter) .. ")")
    return true
end

local function RemoveShotHooks()
    local patch = State.ShootPatch
    if not patch then return end
    -- Desfazer as alteracoes so se ainda forem nossas.
    if ClientShootableComponent.Shoot == patch.PatchedShoot then
        ClientShootableComponent.Shoot = patch.OriginalShoot
    end
    if ReadUpvalue(patch.OriginalShoot, patch.OriginIndex) == patch.PatchedOrigin then
        pcall(debug.setupvalue, patch.OriginalShoot, patch.OriginIndex, patch.OriginalOrigin)
    end
    State.ShootPatch = nil
end

-- Configuracoes locais: o botao Salvar no menu chama esta rotina.
-- Se o executor nao tiver readfile/writefile, a UI continua funcional.
local CONFIG_FILE = "SniperArena_Neverlose.json"
local savedKeys = {
    "Enabled", "FOVRadius", "AimAtScreenCenter", "WallCheck", "ShowFOVCircle", "ESPEnabled",
    "ESPMaxDistance", "ESPUpdateFPS", "ESPEnemiesOnly", "ESPPlayersEnabled",
    "ESPBotsEnabled", "ESPShowBoxes", "ESPShowNames", "ESPShowDistance",
    "ESPShowHealthBar", "ESPTracersEnabled", "ESPTracerPlayers", "ESPTracerBots",
    "ESPTracerFromBottom", "ESPTracerThickness", "ESPSkeletonEnabled",
    "ESPSkeletonPlayers", "ESPSkeletonBots", "ESPSkeletonThickness",
    "ESPChamsEnabled", "ESPChamsPlayers", "ESPChamsBots", "ESPChamsThroughWalls",
    "ESPChamsFillTransparency", "ESPChamsOutlineTransparency",
    "ESPHeadDotEnabled", "ESPHeadDotPlayers", "ESPHeadDotBots", "ESPHeadDotRadius",
    "ESPVisibilityCheck", "TargetHighlightEnabled", "TargetHighlightSize",
    "AimPart", "TargetPriority",
}

local function ColorToHex(color)
    return string.format("#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

local function SaveSettings()
    if type(writefile) ~= "function" then
        WarnOnce("save_unavailable", "writefile indisponivel; configuracao nao foi salva.")
        return
    end

    local data = {}
    for _, key in ipairs(savedKeys) do
        data[key] = Settings[key]
    end
    data.FOVColor = ColorToHex(Settings.FOVColor)
    data.ESPBoxColor = ColorToHex(Settings.ESPBoxColor)
    data.ESPNameColor = ColorToHex(Settings.ESPNameColor)
    data.ESPBotColor = ColorToHex(Settings.ESPBotColor)
    data.ESPTracerColor = ColorToHex(Settings.ESPTracerColor)
    data.ESPSkeletonColor = ColorToHex(Settings.ESPSkeletonColor)
    data.ESPSkeletonBotColor = ColorToHex(Settings.ESPSkeletonBotColor)
    data.ESPChamsPlayerColor = ColorToHex(Settings.ESPChamsPlayerColor)
    data.ESPChamsBotColor = ColorToHex(Settings.ESPChamsBotColor)
    data.ESPHeadDotColor = ColorToHex(Settings.ESPHeadDotColor)
    data.ESPVisibleColor = ColorToHex(Settings.ESPVisibleColor)
    data.ESPOccludedColor = ColorToHex(Settings.ESPOccludedColor)
    data.TargetHighlightColor = ColorToHex(Settings.TargetHighlightColor)

    local ok, err = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    if ok then
        print("[SA] Configuracao salva em " .. CONFIG_FILE)
    else
        WarnOnce("save_failed", "Falha ao salvar: " .. tostring(err))
    end
end

local function LoadSettings()
    if type(readfile) ~= "function" then return end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(data) ~= "table" then return end

    for _, key in ipairs({
        "Enabled", "AimAtScreenCenter", "WallCheck", "ShowFOVCircle",
        "ESPEnabled", "ESPEnemiesOnly", "ESPPlayersEnabled", "ESPBotsEnabled",
        "ESPShowBoxes", "ESPShowNames", "ESPShowDistance", "ESPShowHealthBar",
        "ESPTracersEnabled", "ESPTracerPlayers", "ESPTracerBots", "ESPTracerFromBottom",
        "ESPSkeletonEnabled", "ESPSkeletonPlayers", "ESPSkeletonBots",
        "ESPChamsEnabled", "ESPChamsPlayers", "ESPChamsBots", "ESPChamsThroughWalls",
        "ESPHeadDotEnabled", "ESPHeadDotPlayers", "ESPHeadDotBots", "ESPVisibilityCheck",
        "TargetHighlightEnabled"
    }) do
        if type(data[key]) == "boolean" then Settings[key] = data[key] end
    end
    for key, bounds in pairs({
        FOVRadius = { 10, 600 },
        ESPMaxDistance = { 100, 5000 },
        ESPUpdateFPS = { 5, 60 },
        ESPHeadDotRadius = { 2, 14 },
        TargetHighlightSize = { 6, 30 },
    }) do
        if type(data[key]) == "number" and data[key] == data[key] then
            Settings[key] = math.floor(math.clamp(data[key], bounds[1], bounds[2]) + 0.5)
        end
    end
    if type(data.ESPTracerThickness) == "number" and data.ESPTracerThickness == data.ESPTracerThickness then
        Settings.ESPTracerThickness = math.clamp(data.ESPTracerThickness, 1, 5)
    end
    if type(data.ESPSkeletonThickness) == "number" and data.ESPSkeletonThickness == data.ESPSkeletonThickness then
        Settings.ESPSkeletonThickness = math.clamp(data.ESPSkeletonThickness, 1, 5)
    end
    for _, key in ipairs({
        "FOVColor", "ESPBoxColor", "ESPNameColor", "ESPBotColor",
        "ESPTracerColor", "ESPSkeletonColor", "ESPSkeletonBotColor",
        "ESPChamsPlayerColor", "ESPChamsBotColor", "ESPHeadDotColor",
        "ESPVisibleColor", "ESPOccludedColor", "TargetHighlightColor"
    }) do
        local hex = data[key]
        if type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$") then
            local colorOK, color = pcall(Color3.fromHex, hex)
            if colorOK then Settings[key] = color end
        end
    end
    for _, field in ipairs({"ESPChamsFillTransparency", "ESPChamsOutlineTransparency"}) do
        if type(data[field]) == "number" and data[field] == data[field] then
            Settings[field] = math.clamp(data[field], 0, 1)
        end
    end
    local parts = {Auto = true, Head = true, Torso = true, Root = true}
    local priorities = {Crosshair = true, Distance = true, ["Lowest HP"] = true}
    if parts[data.AimPart] then Settings.AimPart = data.AimPart end
    if priorities[data.TargetPriority] then Settings.TargetPriority = data.TargetPriority end
    print("[SA] Configuracao local carregada.")
end

-- ======================================================
-- TOKYO LIB PUBLICA: loadstring normal, sem autenticacao
-- ======================================================
local TOKYO_LIB_URL = "https://raw.githubusercontent.com/oMaathDev/repo-secret/main/TokyoLib.lua"

local function LoadTokyoLibrary()
    -- Carrega a source publica. A Tokyo Lib original cria um ImageButton
    -- invisivel e MODAL ocupando toda a tela, o que captura cliques e camera
    -- mesmo quando o codigo apenas oculta a janela Drawing.
    -- Desativamos apenas esse overlay no texto carregado, sem alterar o GitHub.
    local source = game:HttpGet(TOKYO_LIB_URL)
    assert(type(source) == "string" and #source > 0,
        "Tokyo Lib: resposta HTTP vazia.")

    local modifiedCount
    source, modifiedCount = source:gsub(
        "Visible%s*=%s*true,%s*Modal%s*=%s*true,",
        "Visible = false,\n        Modal = false,",
        1
    )
    if modifiedCount == 0 then
        WarnOnce("modal_pattern",
            "Overlay modal nao localizado; fallback: fechar a biblioteca inteira pelo DELETE.")
    else
        print("[ECLIPSE] Overlay invisivel de captura desativado (modo nao bloqueante).")
    end

    local factory, compileError = loadstring(source)
    assert(type(factory) == "function",
        "Tokyo Lib: falha ao compilar a source: " .. tostring(compileError))
    return factory({
        cheatname = "Eclipse Menu",
        gamename = "Sniper Arena",
    })
end

-- Ajuste testado visualmente no TokyoLib_Example_Diagnostico:
-- dimensiona fundo e bordas de acordo com a secao mais alta.
local function AjustarJanelaAoConteudo(janela)
    local fundo = janela.objects and janela.objects.background
    if not (fundo and fundo.Object) then
        WarnOnce("window_bg", "Tokyo Lib: background nao encontrado para ajuste de altura.")
        return
    end

    for _, aba in pairs(janela.tabs or {}) do
        if type(aba.UpdateSections) == "function" then
            pcall(function() aba:UpdateSections() end)
        end
    end

    local janelaTopo = fundo.Object.Position.Y
    local janelaBase = janelaTopo + fundo.Object.Size.Y
    local ultimaBorda = janelaBase

    for _, aba in pairs(janela.tabs or {}) do
        for _, secao in pairs(aba.sections or {}) do
            local desenho = secao.objects and secao.objects.background
            if desenho and desenho.Object then
                local obj = desenho.Object
                ultimaBorda = math.max(ultimaBorda, obj.Position.Y + obj.Size.Y)
            end
        end
    end

    local diferenca = math.max(0, math.ceil(ultimaBorda + 10 - janelaBase))
    if diferenca > 0 then
        local tamanho = fundo.Size
        fundo.Size = UDim2.new(tamanho.X.Scale, tamanho.X.Offset,
            tamanho.Y.Scale, tamanho.Y.Offset + diferenca)
    end

    local camera = workspace.CurrentCamera
    if camera then
        local alturaTela = camera.ViewportSize.Y
        local alturaJanela = fundo.Object.Size.Y
        local posY = fundo.Object.Position.Y
        local deslocamento = 0
        if posY + alturaJanela > alturaTela - 6 then
            deslocamento = alturaTela - 6 - (posY + alturaJanela)
        end
        if posY + deslocamento < 6 then
            deslocamento = 6 - posY
        end
        if deslocamento ~= 0 then
            fundo.Position = fundo.Position + UDim2.fromOffset(0, deslocamento)
        end
        if alturaJanela > alturaTela - 12 then
            WarnOnce("tall_window",
                "Menu maior que a tela: a Tokyo Lib precisa de scrolling nativo para essa resolucao.")
        end
    end
end

-- IMPORTANTE: library:SetOpen fecha tambem a ScreenGui do overlay
-- e libera as capturas/acoes, enquanto window:SetOpen so oculta o Drawing.
local function ToggleUIVisible(visible)
    local lib = State.UILibrary
    if not lib then return end
    visible = not not visible
    if type(lib.SetOpen) ~= "function" then
        WarnOnce("toggle_missing", "Tokyo Lib: library:SetOpen nao encontrado.")
        return
    end

    local ok, reason = pcall(function()
        lib:SetOpen(visible)
    end)
    if ok then
        State.UIVisible = visible
    else
        WarnOnce("toggle_ui", "Falha ao mostrar/ocultar Tokyo UI: " .. tostring(reason))
    end
end

local FLAGS = {
    Enabled = "eclipse_silent",
    ESPEnabled = "eclipse_esp",
}

-- Mantem estado da UI sincronizado com os atalhos F1 e F2.
local function SyncToggleControl(field)
    local value = Settings[field]
    local control = State.Controls[field]
    if control then
        for _, setterName in ipairs({ "SetState", "SetValue", "Set" }) do
            local setter = control[setterName]
            if type(setter) == "function" then
                local ok = pcall(setter, control, value)
                if ok then break end
            end
        end
    end
    local lib = State.UILibrary
    if lib and type(lib.flags) == "table" and FLAGS[field] then
        lib.flags[FLAGS[field]] = value
    end
end

local function CreateUI()
    if State.UIWindow then
        ToggleUIVisible(true)
        return
    end

    local ok, err = pcall(function()
        local library = LoadTokyoLibrary()
        assert(type(library) == "table" and type(library.init) == "function",
            "Tokyo Lib retornou uma API inesperada")
        library:init() -- Obrigatorio ANTES do NewWindow; igual ao exemplo funcional.
        assert(type(library.NewWindow) == "function", "Tokyo Lib sem NewWindow()")

        local window = library.NewWindow({
            title = "ECLIPSE MENU | SNIPER ARENA",
            size = UDim2.new(0, 510, 0.6, 6),
        })
        assert(window and type(window.AddTab) == "function", "Falha ao criar janela Tokyo")

        State.UILibrary = library
        State.UIWindow = window
        State.UIVisible = true
        State.Controls = {}

        -- COMBAT: Silent Aim, campo de visao (duas colunas).
        local combat = window:AddTab(" Combat ")
        local aim = combat:AddSection("Silent Aim", 1)
        State.Controls.Enabled = aim:AddToggle({
            enabled = true,
            text = "Silent Aim ativo", state = Settings.Enabled,
            flag = FLAGS.Enabled, tooltip = "F2 ativa/desativa",
            risky = false,
            callback = function(v) Settings.Enabled = v end,
        })
        aim:AddToggle({
            enabled = true, text = "Mira pelo centro da tela",
            state = Settings.AimAtScreenCenter,
            flag = "eclipse_screen_center", risky = false,
            tooltip = "Recomendado para BlueStacks e touch",
            callback = function(v) Settings.AimAtScreenCenter = v end,
        })
        aim:AddToggle({
            enabled = true, text = "Apenas alvos visiveis",
            state = Settings.WallCheck,
            flag = "eclipse_wallcheck", risky = false,
            callback = function(v) Settings.WallCheck = v end,
        })
        aim:AddSeparator({ enabled = true, text = "Atalho: F2" })

        local fov = combat:AddSection("Field of View", 2)
        local radiusControl = fov:AddSlider({
            enabled = true, text = "Raio do FOV", flag = "eclipse_fov",
            tooltip = "Raio de busca de alvos", suffix = " px",
            min = 10, max = 600, increment = 1,
            callback = function(v) Settings.FOVRadius = v end,
        })
        if radiusControl and type(radiusControl.SetValue) == "function" then
            radiusControl:SetValue(Settings.FOVRadius)
        end
        fov:AddToggle({
            enabled = true, text = "Mostrar circulo FOV",
            state = Settings.ShowFOVCircle,
            flag = "eclipse_showfov", risky = false,
            callback = function(v) Settings.ShowFOVCircle = v end,
        })
        fov:AddColor({
            enabled = true, text = "Cor do circulo", flag = "eclipse_fovcolor",
            color = Settings.FOVColor, trans = 0, risky = false,
            callback = function(v)
                if typeof(v) == "Color3" then Settings.FOVColor = v end
            end,
        })

        -- TARGETING: novas estrategias de selecao e indicador de alvo.
        local targeting = window:AddTab(" Targeting ")
        local selection = targeting:AddSection("Selecao de alvo", 1)
        selection:AddList({
            enabled = true, text = "Aim Part Selector",
            selected = Settings.AimPart, values = {"Auto", "Head", "Torso", "Root"},
            max = 4, multi = false, flag = "eclipse_aimpart",
            callback = function(v)
                if type(v) == "string" and (v == "Auto" or v == "Head" or v == "Torso" or v == "Root") then
                    Settings.AimPart = v
                end
            end,
        })
        selection:AddList({
            enabled = true, text = "Target Priority",
            selected = Settings.TargetPriority,
            values = {"Crosshair", "Distance", "Lowest HP"},
            max = 3, multi = false, flag = "eclipse_priority",
            callback = function(v)
                if type(v) == "string" and (v == "Crosshair" or v == "Distance" or v == "Lowest HP") then
                    Settings.TargetPriority = v
                end
            end,
        })
        selection:AddSeparator({enabled = true, text = "Prioridade aplicada dentro do FOV"})

        local targetHighlight = targeting:AddSection("Target Highlight", 2)
        targetHighlight:AddToggle({
            enabled = true, text = "Destacar alvo selecionado",
            state = Settings.TargetHighlightEnabled, flag = "eclipse_target_highlight",
            risky = false,
            callback = function(v) Settings.TargetHighlightEnabled = v end,
        })
        targetHighlight:AddColor({
            enabled = true, text = "Cor do destaque", color = Settings.TargetHighlightColor,
            flag = "eclipse_target_color", trans = 0, risky = false,
            callback = function(v)
                if typeof(v) == "Color3" then Settings.TargetHighlightColor = v end
            end,
        })
        local focusSize = targetHighlight:AddSlider({
            enabled = true, text = "Tamanho indicador",
            flag = "eclipse_target_size", min = 6, max = 30, increment = 1,
            suffix = " px", callback = function(v) Settings.TargetHighlightSize = v end,
        })
        if focusSize and type(focusSize.SetValue) == "function" then
            focusSize:SetValue(Settings.TargetHighlightSize)
        end

        -- VISUALS: menus independentes por alvo, elementos, tracers e desempenho.
        -- Duas colunas para manter todos os controles dentro da Tokyo Lib.
        local visuals = window:AddTab(" Visuals ")
        local function VisualToggle(section, label, field, flag, tooltip)
            local toggle = section:AddToggle({
                enabled = true, text = label, state = Settings[field],
                flag = flag, risky = false, tooltip = tooltip,
                callback = function(value) Settings[field] = value end,
            })
            State.Controls[field] = toggle
            return toggle
        end
        local function VisualColor(section, label, field, flag)
            return section:AddColor({
                enabled = true, text = label, color = Settings[field],
                flag = flag, trans = 0, risky = false,
                callback = function(value)
                    if typeof(value) == "Color3" then Settings[field] = value end
                end,
            })
        end
        local function VisualSlider(section, label, field, flag, minimum, maximum, step, suffix)
            local control = section:AddSlider({
                enabled = true, text = label, flag = flag,
                suffix = suffix or "", min = minimum, max = maximum,
                increment = step,
                callback = function(value) Settings[field] = value end,
            })
            if control and type(control.SetValue) == "function" then
                control:SetValue(Settings[field])
            end
            return control
        end

        local targets = visuals:AddSection("Alvos ESP", 1)
        VisualToggle(targets, "ESP geral (F1)", "ESPEnabled", FLAGS.ESPEnabled,
            "F1 liga e desliga o ESP completo")
        VisualToggle(targets, "ESP de players", "ESPPlayersEnabled", "eclipse_esp_players")
        VisualToggle(targets, "ESP de bots / NPCs", "ESPBotsEnabled", "eclipse_esp_bots",
            "Detecta bots de combate e NPCs com Humanoid")
        VisualToggle(targets, "Somente players inimigos", "ESPEnemiesOnly", "eclipse_enemies",
            "Filtro de times para players; nao altera o ESP dos bots")

        local elements = visuals:AddSection("Elementos ESP", 1)
        VisualToggle(elements, "Mostrar caixas", "ESPShowBoxes", "eclipse_esp_boxes")
        VisualToggle(elements, "Mostrar nomes", "ESPShowNames", "eclipse_esp_names")
        VisualToggle(elements, "Mostrar distancia", "ESPShowDistance", "eclipse_esp_distance_text")
        VisualToggle(elements, "Mostrar barra de vida", "ESPShowHealthBar", "eclipse_esp_health")

        local colors = visuals:AddSection("Cores ESP", 1)
        VisualColor(colors, "Cor das caixas players", "ESPBoxColor", "eclipse_boxcolor")
        VisualColor(colors, "Cor das caixas bots", "ESPBotColor", "eclipse_botcolor")
        VisualColor(colors, "Cor dos nomes", "ESPNameColor", "eclipse_namecolor")

        local tracers = visuals:AddSection("Tracers", 2)
        VisualToggle(tracers, "Ativar tracers", "ESPTracersEnabled", "eclipse_tracers")
        VisualToggle(tracers, "Tracers em players", "ESPTracerPlayers", "eclipse_tracer_players")
        VisualToggle(tracers, "Tracers em bots", "ESPTracerBots", "eclipse_tracer_bots")
        VisualToggle(tracers, "Origem: base da tela", "ESPTracerFromBottom", "eclipse_tracer_bottom",
            "Desligado: linhas comecam no centro da tela")
        VisualColor(tracers, "Cor dos tracers", "ESPTracerColor", "eclipse_tracer_color")
        VisualSlider(tracers, "Espessura tracers", "ESPTracerThickness",
            "eclipse_tracer_thickness", 1, 5, 0.5, " px")

        local skeleton = visuals:AddSection("Skeleton ESP", 2)
        VisualToggle(skeleton, "Ativar skeleton", "ESPSkeletonEnabled", "eclipse_skeleton")
        VisualToggle(skeleton, "Skeleton em players", "ESPSkeletonPlayers", "eclipse_skeleton_players")
        VisualToggle(skeleton, "Skeleton em bots", "ESPSkeletonBots", "eclipse_skeleton_bots")
        VisualColor(skeleton, "Cor skeleton players", "ESPSkeletonColor", "eclipse_skeleton_color")
        VisualColor(skeleton, "Cor skeleton bots", "ESPSkeletonBotColor", "eclipse_skeleton_botcolor")
        VisualSlider(skeleton, "Espessura skeleton", "ESPSkeletonThickness",
            "eclipse_skeleton_thickness", 1, 5, 0.5, " px")

        local perf = visuals:AddSection("Performance", 2)
        VisualSlider(perf, "Distancia maxima", "ESPMaxDistance",
            "eclipse_distance", 100, 5000, 50, " studs")
        VisualSlider(perf, "Atualizacoes ESP", "ESPUpdateFPS",
            "eclipse_fps", 5, 60, 1, " FPS")

        -- ESP EXTRA: separado para evitar colunas mais altas que a janela.
        local advanced = window:AddTab(" ESP Extra ")
        local chams = advanced:AddSection("Chams ESP", 1)
        VisualToggle(chams, "Ativar Chams", "ESPChamsEnabled", "eclipse_chams")
        VisualToggle(chams, "Chams em players", "ESPChamsPlayers", "eclipse_chams_players")
        VisualToggle(chams, "Chams em bots", "ESPChamsBots", "eclipse_chams_bots")
        VisualToggle(chams, "Exibir atraves paredes", "ESPChamsThroughWalls", "eclipse_chams_depth")
        VisualColor(chams, "Cor Chams players", "ESPChamsPlayerColor", "eclipse_chams_player_color")
        VisualColor(chams, "Cor Chams bots", "ESPChamsBotColor", "eclipse_chams_bot_color")
        VisualSlider(chams, "Transparencia preenchimento", "ESPChamsFillTransparency",
            "eclipse_chams_fill", 0, 1, 0.05, "")
        VisualSlider(chams, "Transparencia contorno", "ESPChamsOutlineTransparency",
            "eclipse_chams_outline", 0, 1, 0.05, "")

        local dots = advanced:AddSection("Head Dot", 2)
        VisualToggle(dots, "Ativar Head Dot", "ESPHeadDotEnabled", "eclipse_head_dot")
        VisualToggle(dots, "Head Dot players", "ESPHeadDotPlayers", "eclipse_head_players")
        VisualToggle(dots, "Head Dot bots", "ESPHeadDotBots", "eclipse_head_bots")
        VisualColor(dots, "Cor Head Dot", "ESPHeadDotColor", "eclipse_head_color")
        VisualSlider(dots, "Raio Head Dot", "ESPHeadDotRadius",
            "eclipse_head_size", 2, 14, 1, " px")

        local visibility = advanced:AddSection("Visibility Check", 2)
        VisualToggle(visibility, "Verificar visibilidade", "ESPVisibilityCheck", "eclipse_visibility",
            "Altera cor quando o alvo esta atras de obstaculos")
        VisualColor(visibility, "Cor visivel", "ESPVisibleColor", "eclipse_visible_color")
        VisualColor(visibility, "Cor oculto", "ESPOccludedColor", "eclipse_hidden_color")

        -- SYSTEM: atalhos e acoes do ECLIPSE MENU.
        local system = window:AddTab(" System ")
        local keys = system:AddSection("Atalhos", 1)
        keys:AddSeparator({ enabled = true, text = "F1 - Alternar ESP" })
        keys:AddSeparator({ enabled = true, text = "F2 - Alternar Silent Aim" })
        keys:AddSeparator({ enabled = true, text = "F3 - Desativar script" })
        keys:AddSeparator({ enabled = true, text = "DELETE - Mostrar/Ocultar" })

        local actions = system:AddSection("Acoes", 2)
        actions:AddButton({
            enabled = true, text = "Salvar configuracoes", confirm = false,
            callback = SaveSettings,
        })
        actions:AddButton({
            enabled = true, text = "Diagnostico dos tiros", confirm = false,
            callback = function()
                print(string.format("[ECLIPSE] Hook=%s | Tiros=%d | Alvos=%d | Redirecionados=%d",
                    tostring(State.ShootPatch ~= nil), State.ShotsChecked,
                    State.ShotsWithTarget, State.RedirectedShots))
            end,
        })
        actions:AddButton({
            enabled = true, text = "Diagnostico do ESP", confirm = false,
            callback = function()
                local playersCount, botsCount = 0, 0
                for _ in pairs(ESPData) do playersCount += 1 end
                for _ in pairs(BotESPData) do botsCount += 1 end
                print(string.format(
                    "[ECLIPSE] ESP=%s | Players=%s (%d) | Bots=%s (%d) | Tracers=%s | Skeleton=%s",
                    tostring(Settings.ESPEnabled), tostring(Settings.ESPPlayersEnabled),
                    playersCount, tostring(Settings.ESPBotsEnabled), botsCount,
                    tostring(Settings.ESPTracersEnabled), tostring(Settings.ESPSkeletonEnabled)
                ))
                print(string.format("[ECLIPSE] Chams=%s | Head Dot=%s | Visibility=%s | Highlight=%s | AimPart=%s | Priority=%s",
                    tostring(Settings.ESPChamsEnabled), tostring(Settings.ESPHeadDotEnabled),
                    tostring(Settings.ESPVisibilityCheck), tostring(Settings.TargetHighlightEnabled),
                    tostring(Settings.AimPart), tostring(Settings.TargetPriority)))
            end,
        })
        actions:AddButton({
            enabled = true, text = "Ocultar menu (DELETE)", confirm = false,
            callback = function() ToggleUIVisible(false) end,
        })
        actions:AddButton({
            enabled = true, text = "Desativar ECLIPSE (F3)", confirm = true,
            callback = function() if State.Stop then State.Stop() end end,
        })

        -- Settings nativo: Config, Main, Indicadores, tema.
        -- O tamanho eh reajustado conforme as secoes do exemplo funcional.
        if type(library.CreateSettingsTab) == "function" then
            library:CreateSettingsTab(window)
        end

        task.defer(function()
            local layoutOK, layoutError = pcall(AjustarJanelaAoConteudo, window)
            if not layoutOK then
                WarnOnce("layout_error", "Erro no ajuste de layout: " .. tostring(layoutError))
            end
        end)
        if type(library.SendNotification) == "function" then
            pcall(function() library:SendNotification("ECLIPSE MENU carregado", 5) end)
        end
    end)

    if not ok then
        warn("[ECLIPSE] Falha ao iniciar Tokyo UI: " .. tostring(err))
        State.UIVisible = false
        State.UILibrary = nil
        State.UIWindow = nil
        State.Controls = {}
    else
        print("[ECLIPSE] Tokyo UI pronta | F1 ESP | F2 Silent Aim | F3 parar | DELETE menu")
    end
end

-- ======================================================
-- CICLO DE VIDA / HOTKEYS / ATUALIZACAO DOS DRAWINGS
-- ======================================================
local function Stop()
    if not State.Active then return end
    State.Active = false
    ToggleUIVisible(false)
    RemoveShotHooks()
    table.clear(State.ShotTargets)

    for _, connection in ipairs(State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(State.Connections)
    for player in pairs(ESPData) do RemoveESP(player) end
    for model in pairs(BotESPData) do RemoveBotESP(model) end
    for model in pairs(ChamsData) do RemoveChams(model) end
    State.TargetSelection = nil
    if TargetMarker then
        pcall(function() TargetMarker:Remove() end)
        TargetMarker = nil
    end
    if FOVCircle then
        pcall(function() FOVCircle:Remove() end)
        FOVCircle = nil
    end

    if State.UILibrary and type(State.UILibrary.Unload) == "function" then
        pcall(function() State.UILibrary:Unload() end)
    end
    State.UIWindow = nil
    State.UILibrary = nil
    State.Controls = {}
    State.UIVisible = false
    print(string.format("[ECLIPSE] Desativado | Tiros: %d | Com alvo: %d | Redirecionados: %d",
        State.ShotsChecked, State.ShotsWithTarget, State.RedirectedShots))
end

local function Start()
    if State.Active then
        CreateUI()
        return
    end
    State.Active = true
    Camera = workspace.CurrentCamera
    InstallShotHooks() -- Lógica do Silent Aim v5 preservada.

    FOVCircle = NewDrawing("Circle", {
        Thickness = 1, Radius = Settings.FOVRadius, Transparency = 0.7,
        Color = Settings.FOVColor, Filled = false, NumSides = 64,
    })
    TargetMarker = NewDrawing("Circle", {
        Thickness = 2, Radius = Settings.TargetHighlightSize, Transparency = 1,
        Color = Settings.TargetHighlightColor, Filled = false, NumSides = 32,
    })

    for _, player in ipairs(Players:GetPlayers()) do AddESP(player) end
    Track(Players.PlayerAdded:Connect(AddESP))
    Track(Players.PlayerRemoving:Connect(RemoveESP))
    Track(workspace.DescendantAdded:Connect(function(instance)
        if instance:IsA("Humanoid") then
            local model = instance.Parent
            if model and model:IsA("Model") then RegisterBot(model) end
        end
    end))
    Track(workspace.DescendantRemoving:Connect(function(instance)
        if BotESPData[instance] then RemoveBotESP(instance) end
    end))
    task.defer(ScanExistingHumanoids)
    Track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = workspace.CurrentCamera
    end))

    local elapsed = 0
    local botsTimer = 0
    local targetTimer = 0
    Track(RunService.RenderStepped:Connect(function(dt)
        if FOVCircle then
            FOVCircle.Position = GetAimScreenPoint()
            FOVCircle.Radius = Settings.FOVRadius
            FOVCircle.Color = Settings.FOVColor
            FOVCircle.Visible = State.Active and Settings.Enabled and Settings.ShowFOVCircle
        end
        -- Preview com limite de 8 verificacoes/segundo, sem scan completo em cada frame.
        targetTimer += dt
        if targetTimer >= 0.125 then
            targetTimer %= 0.125
            if State.Active and Settings.Enabled and Settings.TargetHighlightEnabled then
                local camera = Camera or workspace.CurrentCamera
                if camera then
                    local ok, target = pcall(FindShotTarget, camera.CFrame)
                    if ok and target then
                        State.TargetSelection = target
                        State.TargetSelectionUntil = os.clock() + 0.24
                    elseif os.clock() > State.TargetSelectionUntil then
                        State.TargetSelection = nil
                    end
                end
            else
                State.TargetSelection = nil
            end
        end
        UpdateTargetMarker()
        botsTimer += dt
        if botsTimer >= 2 then
            botsTimer %= 2
            RefreshBotEntities()
        end
        elapsed += dt
        local interval = 1 / math.max(Settings.ESPUpdateFPS, 1)
        if elapsed < interval then return end
        elapsed = elapsed % interval
        local espOK, espError = pcall(UpdateESP)
        if not espOK then
            WarnOnce("esp_update", "Erro no ESP: " .. tostring(espError))
            for _, drawings in pairs(ESPData) do HideESP(drawings) end
            for _, drawings in pairs(BotESPData) do HideESP(drawings) end
            HideAllChams()
        end
    end))

    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.Delete then
            if not UserInputService:GetFocusedTextBox() then
                local lib = State.UILibrary
                ToggleUIVisible(not (lib and lib.open or false))
            end
            return
        end
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.F1 then
            Settings.ESPEnabled = not Settings.ESPEnabled
            SyncToggleControl("ESPEnabled")
            print("[ECLIPSE] ESP:", Settings.ESPEnabled)
        elseif input.KeyCode == Enum.KeyCode.F2 then
            Settings.Enabled = not Settings.Enabled
            SyncToggleControl("Enabled")
            print("[ECLIPSE] Silent Aim:", Settings.Enabled)
        elseif input.KeyCode == Enum.KeyCode.F3 then
            Stop()
        end
    end))

    CreateUI()
    print("[ECLIPSE] Iniciado | F1 ESP | F2 Silent Aim | F3 parar | DELETE menu")
    print("[ECLIPSE] v6.6: Chams, Head Dot, Visibility, Target Highlight, Aim Part e Priority.")
end

State.Stop = Stop
State.Start = Start
Environment.__SniperArenaUpdated = State
LoadSettings()
Start()