



---- SOURCE CODE [COLOR OR DIE]

--[[
    COLOR OR DIE | ESP v1.8
    Categorias: monstros, tintas, ferramentas, pinceis, portas coloridas e portas Safe Zone.
    Atalhos: DELETE = mostrar/ocultar menu.
    Script local: nao teleporta, nao altera objetos do servidor, nao coleta itens.
    Execute novamente para substituir a instancia anterior.

    Observacao: nomes internos dos objetos podem mudar entre capitulos/updates.
    A deteccao combina nomes de objetos, modelos e pastas comuns no Workspace.
    Chapter 1: pinceis reais estao em
    Workspace.GameplayAssets.Items.Collectable.Collectable.[1-13].
    Nao depende de MeshId nem do botao APRENDER PINCEL.
    v1.5: contorno de monstros isolado do modelo, com recuperacao de
    Highlight e atualizacao automatica quando a geometria muda.
    v1.6: controle local de WalkSpeed com ativacao, presets, slider,
    entrada numerica, anti-reset opcional e restauracao ao desligar.
    v1.7: ESP separado de portas Safe Zone, deteccao por nome/contexto,
    selecao manual pelo clique quando os nomes internos sao genericos.
    v1.8: raycast ignora colisoes invisiveis e exige confirmar a
    geometria da porta antes de cadastrar manualmente.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
    warn("[COLOR OR DIE ESP] LocalPlayer indisponivel.")
    return
end
local playerGui = player:WaitForChild("PlayerGui")

local env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then env = result end
end

if type(env.ColorOrDieESP_Stop) == "function" then
    pcall(env.ColorOrDieESP_Stop)
end

local alive = true
local scanWorld
local links = {}
local enabled = {
    Monsters = true,
    Paint = true,
    Tools = true,
    Brushes = true,
    Doors = true,
    SafeDoors = true,
    Distance = true,
}
local categoryColors = {
    Monsters = Color3.fromRGB(255, 70, 86),
    Paint = Color3.fromRGB(255, 213, 64),
    Tools = Color3.fromRGB(85, 196, 255),
    Brushes = Color3.fromRGB(205, 110, 255),
    Doors = Color3.fromRGB(248, 248, 248),
    SafeDoors = Color3.fromRGB(76, 250, 181),
}
local tracked = {
    Monsters = {}, Paint = {}, Tools = {}, Brushes = {}, Doors = {}, SafeDoors = {}
}

-- Highlights fora dos modelos do mapa: se um NPC atualiza sua arvore de
-- objetos, o efeito nao e destruido junto de uma peca do personagem.
-- Tambem evita aninhamento de instancias Highlight entre modelos e pecas.
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "COD_ESP_v18_Highlights"
highlightFolder.Parent = Workspace
local paintColors = {
    red = Color3.fromRGB(255, 70, 80), vermelho = Color3.fromRGB(255, 70, 80),
    orange = Color3.fromRGB(255, 154, 54), laranja = Color3.fromRGB(255, 154, 54),
    yellow = Color3.fromRGB(255, 218, 62), amarelo = Color3.fromRGB(255, 218, 62),
    green = Color3.fromRGB(65, 239, 120), verde = Color3.fromRGB(65, 239, 120),
    teal = Color3.fromRGB(50, 225, 209), cyan = Color3.fromRGB(50, 225, 209),
    blue = Color3.fromRGB(80, 150, 255), azul = Color3.fromRGB(80, 150, 255),
    purple = Color3.fromRGB(173, 98, 255), roxo = Color3.fromRGB(173, 98, 255),
    pink = Color3.fromRGB(255, 105, 189), rosa = Color3.fromRGB(255, 105, 189),
    white = Color3.fromRGB(240, 240, 240), branco = Color3.fromRGB(240, 240, 240),
    black = Color3.fromRGB(145, 145, 160), preto = Color3.fromRGB(145, 145, 160)
}

local monsterNames = {
    bill = true, bob = true, ross = true, claude = true, sirleon = true,
    monster = true, monst = true, enemy = true, stickman = true,
    chaser = true, creature = true, killer = true, entity = true,
}

local toolNames = {
    screwdriver = "Chave de fenda", chavefenda = "Chave de fenda",
    saw = "Serra", hacksaw = "Serra", serra = "Serra",
    hammer = "Martelo", martelo = "Martelo",
    plank = "Tabua", woodplank = "Tabua", board = "Tabua",
    triangle = "Triangulo", triangularblock = "Bloco triangular",
    key = "Chave", chave = "Chave", keycard = "Cartao-chave",
    crowbar = "Pe de cabra", torch = "Tocha", flashlight = "Lanterna",
    pickaxe = "Picareta", dynamite = "Dinamite", lasergun = "Arma laser",
    fireextinguisher = "Extintor", grapplinghook = "Gancho",
    puzzlepiece = "Peca do puzzle", staffpass = "Cracha",
    book = "Livro", gear = "Engrenagem",
}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(links, c)
    return c
end

local function norm(s)
    return string.lower(tostring(s or "")):gsub("[^%a%d]", "")
end

local function validPartPosition(part)
    if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return nil end
    local ok, pos = pcall(function()
        if not part:IsDescendantOf(Workspace) then return nil end
        return part.Position
    end)
    if ok and typeof(pos) == "Vector3" then return pos end
    return nil
end

local function insideWorkspace(instance)
    if typeof(instance) ~= "Instance" then return false end
    local ok, res = pcall(function() return instance:IsDescendantOf(Workspace) end)
    return ok and res == true
end

local function insidePlayerCharacter(instance)
    local p = instance
    while p and p ~= Workspace do
        if p:IsA("Model") and Players:GetPlayerFromCharacter(p) then
            return true
        end
        p = p.Parent
    end
    return false
end

local function anchorOf(target)
    if target:IsA("BasePart") then return target end
    if target:IsA("Model") then
        return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function sizeAllowed(target, category)
    if not (target:IsA("Model") or target:IsA("BasePart")) then return false end
    local ok, size = pcall(function()
        return target:IsA("Model") and target:GetExtentsSize() or target.Size
    end)
    if not ok or typeof(size) ~= "Vector3" then return false end
    local largest = math.max(size.X, size.Y, size.Z)
    local smallest = math.min(size.X, size.Y, size.Z)
    if largest < 0.08 or smallest < 0 then return false end
    return largest <= (category == "Monsters" and 100 or ((category == "Doors" or category == "SafeDoors") and 45 or 18))
end

local function contextOf(obj)
    local ctx = {Items = false, Monsters = false, Brushes = false, Paint = false, Tools = false}
    local p = obj.Parent
    local depth = 0
    while p and p ~= Workspace and depth < 14 do
        local n = norm(p.Name)
        if n == "monsters" or n == "enemies" or n == "npcs" or n == "entities" then
            ctx.Monsters = true
        elseif n == "items" or n == "collectibles" or n == "pickups" or n == "itemspawns" then
            ctx.Items = true
        elseif n == "brushes" or n == "paintbrushes" or n == "brushspawns"
            or n == "paintbrushspawns" or n == "brushpickups"
            or n == "paintbrushcollectibles" or n == "brushcollectibles" then
            ctx.Brushes = true
        elseif n == "tools" or n == "toolspawns" then
            ctx.Tools = true
        elseif n == "paints" or n == "paintbuckets" or n == "buckets" then
            ctx.Paint = true
        end
        p = p.Parent
        depth += 1
    end
    return ctx
end

local function hasChildNamed(obj, nameSet)
    -- So e usado para itens ja filtrados por contexto.
    for _, c in ipairs(obj:GetChildren()) do
        if nameSet[norm(c.Name)] then return true end
    end
    return false
end

local PAINT_NAMES = {
    paint = true, paintbucket = true, paintcan = true,
    bucket = true, colorbucket = true, colourbucket = true,
    balde = true, baldetinta = true, tinta = true,
}
-- Pinceis CHAPTER 1, confirmados no Dex++ do jogo:
-- Workspace.GameplayAssets.Items.Collectable.Collectable.1 ... 13
-- O primeiro Collectable pode conter outros tipos de item. Somente os
-- filhos numerados dentro do SEGUNDO Collectable sao considerados pinceis.
local CH1_BRUSHES = 13
local function collectableContainer()
    local assets = Workspace:FindFirstChild("GameplayAssets")
    local items = assets and assets:FindFirstChild("Items")
    local outer = items and items:FindFirstChild("Collectable")
    return outer and outer:FindFirstChild("Collectable") or nil
end

local function brushIndex(name)
    local n = tonumber(tostring(name))
    if n and n == math.floor(n) and n >= 1 and n <= CH1_BRUSHES then
        return n
    end
    return nil
end

-- Um objeto pode ser uma peca interna de um pincel. Subimos ate o
-- filho DIRETO numerado da pasta, garantindo 1 unica marcacao por pincel.
local function collectibleItemFor(obj)
    if typeof(obj) ~= "Instance" then return nil end
    local folder = collectableContainer()
    if not folder or not obj:IsDescendantOf(folder) then return nil end

    local root = obj
    while root and root.Parent ~= folder do
        root = root.Parent
    end
    if not root or not brushIndex(root.Name) then return nil end

    if root:IsA("Model") or root:IsA("BasePart") then return root end

    -- Compatibilidade: caso uma das IDs seja Folder e nao Model.
    if root:IsA("Folder") then
        return root:FindFirstChildWhichIsA("Model", true)
            or root:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function collectibleBrushIndex(obj)
    local folder = collectableContainer()
    if not folder or not obj or not obj:IsDescendantOf(folder) then return nil end
    local root = obj
    while root and root.Parent ~= folder do root = root.Parent end
    return root and brushIndex(root.Name) or nil
end

local function stripIndex(name)
    return name:gsub("%d+$", "")
end

local function categoryFor(obj)
    if not (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool")) then
        return nil
    end
    if insidePlayerCharacter(obj) then return nil end

    local n = norm(obj.Name)
    local bare = stripIndex(n)
    local ctx = contextOf(obj)

    -- Evita destacar portas, paredes, travas, displays e suportes decorativos.
    local environmentObject = n:find("door", 1, true) or n:find("gate", 1, true)
        or n:find("wall", 1, true) or n:find("lock", 1, true)
        or n:find("sign", 1, true) or n:find("display", 1, true)
        or n:find("holder", 1, true) or n:find("frame", 1, true)
        or n:find("stand", 1, true)
    if environmentObject then return nil end

    if monsterNames[n] or (ctx.Monsters and obj:IsA("Model") and obj:FindFirstChildWhichIsA("Humanoid", true)) then
        if ctx.Monsters or obj:IsA("Model") or n == "monster" then
            return "Monsters", obj.Name
        end
    end

    -- V1.4: nenhum MeshId, nome parcial ou decoracao e suficiente.
    -- Somente o item 1..13 do Collectable/Collectable e marcado.
    if collectibleItemFor(obj) then
        return "Brushes", "Pincel"
    end

    if toolNames[n] or toolNames[bare] then
        -- 'Book', 'Gear' e 'Key' podem ser cenarios; nomes genericos sem contexto
        -- so sao aceitos em objetos que parecem pickups.
        if n == "book" or n == "gear" or n == "key" or n == "board" then
            if not (ctx.Items or ctx.Tools or obj:IsA("Tool")) then return nil end
        end
        return "Tools", toolNames[n] or toolNames[bare]
    end

    local prefixedPaint = (ctx.Items or ctx.Paint) and (
        n:match("^paintbucket") or n:match("^colorbucket")
        or n:match("^colourbucket") or n:match("^bucket")
        or n:match("^balde") or n:match("^tinta")
        or n:match("^paint[%a]+")
    )
    if PAINT_NAMES[n] or PAINT_NAMES[bare] or prefixedPaint then
        -- 'Paint' numa parede pode ser um detalhe decorativo. Se nao esta na
        -- pasta de itens, exigimos formato de balde ou indicio de pickup.
        if n == "paint" or n == "tinta" then
            if not (ctx.Items or ctx.Paint or obj:IsA("Tool")) then return nil end
        end
        return "Paint", "Tinta"
    end

    -- Alguns mapas nomeiam o modelo da tinta apenas pela cor. A confirmacao
    -- exige contexto de coletavel + uma parte filha chamada Paint/Bucket.
    if paintColors[n] and (ctx.Items or ctx.Paint) and obj:IsA("Model") then
        if hasChildNamed(obj, PAINT_NAMES) then
            return "Paint", obj.Name
        end
    end

    return nil
end

local function chooseTarget(obj, category)
    if category == "Brushes" then
        -- Mesmo ao iterar submodelos, marcar sempre o item raiz numerado.
        return collectibleItemFor(obj)
    end
    if obj:IsA("Tool") then
        return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    if obj:IsA("Model") then return obj end
    if not obj:IsA("BasePart") then return nil end

    -- Marcar o modelo inteiro quando a parte interna se chama "Paint"/"Brush".
    local model = obj.Parent
    if model and model:IsA("Model") then
        if sizeAllowed(model, category) then
            local parentCategory = categoryFor(model)
            local ctx = contextOf(obj)
            if parentCategory == category or ctx.Items or ctx.Paint
                or ctx.Brushes or ctx.Tools or ctx.Monsters then
                return model
            end
        end
    end
    return obj
end

local function detectName(target, category, fallback)
    if category == "Monsters" then return "MONSTRO: " .. tostring(fallback or target.Name) end
    if category == "Brushes" then
        local number = collectibleBrushIndex(target)
        return number and ("PINCEL #" .. number) or "PINCEL"
    end
    if category == "Tools" then return string.upper(tostring(fallback or target.Name)) end
    local name = norm(target.Name)
    if paintColors[name] then return "TINTA: " .. string.upper(target.Name) end
    local p = target.Parent
    if p and paintColors[norm(p.Name)] then
        return "TINTA: " .. string.upper(p.Name)
    end
    return "BALDE DE TINTA"
end

local function itemAccent(target, category)
    if category ~= "Paint" then return categoryColors[category] end
    local colorName = norm(target.Name)
    if paintColors[colorName] then return paintColors[colorName] end
    if target.Parent and paintColors[norm(target.Parent.Name)] then
        return paintColors[norm(target.Parent.Name)]
    end
    return categoryColors.Paint
end

local function targetIsVisible(target, category)
    -- A placa da porta pode estar presa a uma parte transparente.
    if category == "Monsters" or category == "Doors" or category == "SafeDoors" then return true end
    -- Alguns itens coletados sao ocultados em vez de removidos do Workspace.
    local checked = 0
    if target:IsA("BasePart") then
        return target.Transparency < 0.99 and target.LocalTransparencyModifier < 0.99
    end
    for _, part in ipairs(target:GetDescendants()) do
        if part:IsA("BasePart") then
            checked += 1
            if part.Transparency < 0.99 and part.LocalTransparencyModifier < 0.99 then
                return true
            end
            if checked >= 100 then break end
        end
    end
    return checked == 0 -- objetos sem geometria serao removidos pelo anchor
end

local function remove(category, target)
    local e = tracked[category][target]
    if not e then return end
    tracked[category][target] = nil
    if e.monsterEvents then
        for _, ev in ipairs(e.monsterEvents) do
            pcall(function() ev:Disconnect() end)
        end
        e.monsterEvents = nil
    end
    pcall(function()
        if e.highlight then e.highlight:Destroy() end
    end)
    pcall(function() if e.safeBox then e.safeBox:Destroy() end end)
    pcall(function() e.billboard:Destroy() end)
end

local function createHighlight(category, target, accent)
    local h = Instance.new("Highlight")
    h.Name = "COD_" .. category .. "_Highlight"
    h.Adornee = target
    h.FillColor = accent
    h.OutlineColor = accent
    h.FillTransparency = category == "Monsters" and 0.73 or 0.76
    h.OutlineTransparency = 0
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Enabled = enabled[category]
    h.Parent = highlightFolder
    return h
end

-- Repara instancias removidas ou adulteradas pelo jogo e reaponta o
-- Adornee quando o NPC tem pecas trocadas/recarregadas.
local function ensureHighlight(category, e, show, forceRecreate, forceRebind)
    local h = e.highlight
    local destroyedOrDetached = not h or not h:IsA("Highlight")
        or h.Parent ~= highlightFolder
    if forceRecreate or destroyedOrDetached then
        if h then pcall(function() h:Destroy() end) end
        h = createHighlight(category, e.target, e.accent)
        e.highlight = h
        e.highlightLastRebind = os.clock()
    else
        if forceRebind or h.Adornee ~= e.target then
            -- Trocar o Adornee reenvia a silhueta para o renderizador.
            h.Adornee = nil
            h.Adornee = e.target
            e.highlightLastRebind = os.clock()
        end
    end
    if h.FillColor ~= e.accent then h.FillColor = e.accent end
    if h.OutlineColor ~= e.accent then h.OutlineColor = e.accent end
    if h.OutlineTransparency ~= 0 then h.OutlineTransparency = 0 end
    if h.DepthMode ~= Enum.HighlightDepthMode.AlwaysOnTop then
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end
    h.Enabled = show
    return h
end

local function add(category, target, display, customColor)
    if not alive or tracked[category][target] then return end
    if not insideWorkspace(target) or insidePlayerCharacter(target) then return end
    if not sizeAllowed(target, category) then return end
    local anchor = anchorOf(target)
    if not validPartPosition(anchor) then return end

    local accent = customColor or itemAccent(target, category)
    local highlight = createHighlight(category, target, accent)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "COD_" .. category .. "_Label"
    billboard.Adornee = anchor
    billboard.Size = UDim2.fromOffset(240, 34)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, category == "Monsters" and 4.2 or ((category == "Doors" or category == "SafeDoors") and 3.2 or 2.2), 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 20000
    billboard.Enabled = enabled[category]
    billboard.Parent = playerGui

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.08
    label.TextColor3 = accent
    label.Text = display
    label.Parent = billboard

    local e = {
        target = target, anchor = anchor, highlight = highlight,
        billboard = billboard, label = label, name = display,
        accent = accent, highlightLastRebind = os.clock()
    }
    tracked[category][target] = e

    -- Box 3D dedicado as portas Safe: nao depende do limite de Highlights
    -- da engine e funciona ate em partes transparentes do mapa.
    if category == "SafeDoors" then
        local box = Instance.new("BoxHandleAdornment")
        box.Name = "COD_SafeZone_Box"
        box.Adornee = anchor
        box.Size = anchor.Size
        box.Color3 = accent
        box.Transparency = 0.72
        box.AlwaysOnTop = true
        box.ZIndex = 2
        box.Visible = enabled.SafeDoors
        box.Parent = playerGui
        e.safeBox = box
    end

    if category == "Monsters" and target:IsA("Model") then
        e.monsterEvents = {
            target.DescendantAdded:Connect(function(obj)
                if obj:IsA("BasePart") then e.monsterDirty = true end
            end),
            target.DescendantRemoving:Connect(function(obj)
                if obj:IsA("BasePart") then e.monsterDirty = true end
            end),
        }
    end
end

-- COLOR DOORS (v1.2+)
-- O nome interno pode ser generico. Por isso detectamos tanto o nome
-- de uma porta quanto placas de cor (TextLabel) dentro do Workspace.
-- Nao usamos a cor de paredes como unica prova: causaria falsos positivos.
local doorAliases = {
    {"PRETA", {"preto", "preta", "black"}, paintColors.black},
    {"VERMELHA", {"vermelho", "vermelha", "red"}, paintColors.red},
    {"LARANJA", {"laranja", "orange"}, paintColors.orange},
    {"AMARELA", {"amarelo", "amarela", "yellow"}, paintColors.yellow},
    {"VERDE", {"verde", "green"}, paintColors.green},
    {"CIANO", {"ciano", "cyan", "teal", "turquesa", "verdeagua"}, paintColors.teal},
    {"AZUL", {"azul", "blue"}, paintColors.blue},
    {"ROXA", {"roxo", "roxa", "purple"}, paintColors.purple},
    {"ROSA", {"rosa", "pink"}, paintColors.pink},
    {"BRANCA", {"branco", "branca", "white"}, paintColors.white},
}

local function doorByName(s)
    local n = norm(s)
    local doorWords = {"door", "porta", "gate"}
    -- Exige pares de prefixos para impedir, por exemplo, que
    -- "ColoredDoor" seja interpretado como porta vermelha ("red").
    for _, entry in ipairs(doorAliases) do
        for _, alias in ipairs(entry[2]) do
            for _, word in ipairs(doorWords) do
                if n:sub(1, #alias + #word) == alias .. word
                    or n:sub(1, #alias + #word) == word .. alias then
                    return entry
                end
            end
        end
    end
    return nil
end

local function doorBySign(text)
    local n = norm(text)
    -- Cor isolada na placa, ou texto como "PORTA AMARELA".
    -- Nunca marca texto de HUD: so descobre TextLabels no Workspace.
    for _, entry in ipairs(doorAliases) do
        for _, alias in ipairs(entry[2]) do
            if n == alias or n == "porta" .. alias
                or n == alias .. "door" or n == alias .. "porta"
                or n == "door" .. alias or n == alias .. "room"
                or n == "sala" .. alias or n == alias .. "sala" then
                return entry
            end
        end
    end
    return nil
end

local function doorAdorneePart(source)
    -- SurfaceGui/BillboardGui pode usar Adornee fora da sua hierarquia.
    local cursor = source
    while cursor and cursor ~= Workspace do
        if cursor:IsA("BasePart") then return cursor end
        if cursor:IsA("SurfaceGui") or cursor:IsA("BillboardGui") then
            local a = cursor.Adornee
            if a then
                if a:IsA("BasePart") then return a end
                if a:IsA("Attachment") and a.Parent and a.Parent:IsA("BasePart") then
                    return a.Parent
                end
            end
        end
        cursor = cursor.Parent
    end
    return nil
end

local function doorRoot(part)
    -- Quando ha um modelo pequeno da propria porta, marca-o inteiro;
    -- caso contrario, marca apenas a placa/parte de interacao.
    if not part or not part:IsA("BasePart") then return nil end
    local firstModel
    local cursor = part.Parent
    while cursor and cursor ~= Workspace do
        if cursor:IsA("Model") then
            if not sizeAllowed(cursor, "Doors") then break end
            if doorByName(cursor.Name) then return cursor end
            if not firstModel then firstModel = cursor end
        end
        cursor = cursor.Parent
    end
    -- So expande para modelos pequenos com sinais claros de porta.
    if firstModel then
        local n = norm(firstModel.Name)
        if n:find("door", 1, true) or n:find("porta", 1, true)
            or n:find("gate", 1, true) then
            return firstModel
        end
    end
    return part
end

local function worldAttachedUiText(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return false end
    local p = obj.Parent
    while p and p ~= playerGui do
        if p:IsA("SurfaceGui") or p:IsA("BillboardGui") then
            local a = p.Adornee
            return a ~= nil and insideWorkspace(a)
        end
        p = p.Parent
    end
    return false
end

local function doorCandidate(obj)
    if not insideWorkspace(obj) and not worldAttachedUiText(obj) then return nil end
    if insidePlayerCharacter(obj) then return nil end
    if obj:IsA("Model") or obj:IsA("BasePart") then
        local entry = doorByName(obj.Name)
        if entry then
            if obj:IsA("Model") then
                if sizeAllowed(obj, "Doors") then return obj, entry end
                return nil
            end
            return doorRoot(obj), entry
        end
    end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        local entry = doorBySign(obj.Text)
        if entry then
            local part = doorAdorneePart(obj)
            if part then return doorRoot(part), entry end
        end
    end
    -- Uma porta com nome generico pode ser reconhecida por tag/atributo.
    if obj:IsA("BasePart") or obj:IsA("Model") then
        local namedDoor = false
        local n = norm(obj.Name)
        if n:find("door", 1, true) or n:find("porta", 1, true)
            or n:find("gate", 1, true) then namedDoor = true end
        if namedDoor then
            local okAttrs, attrs = pcall(function() return obj:GetAttributes() end)
            if okAttrs then
                for key, value in pairs(attrs) do
                    local k = norm(key)
                    if k == "color" or k == "colour" or k == "cor"
                        or k == "paint" or k == "doorcolor" then
                        local entry = doorBySign(value)
                        if entry then
                            if obj:IsA("Model") then
                                if sizeAllowed(obj, "Doors") then return obj, entry end
                            else
                                return doorRoot(obj), entry
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ===== PORTAS DA SAFE ZONE (v1.8) =====
-- Bloqueia a pasta de colisoes e nomes de hitboxes: a versao anterior
-- podia selecionar GameplayParts.Colliders.MonsterColliders.Colider
-- mesmo quando o usuario clicava visualmente na porta Safe Zone.
local function isCollisionOnlyObject(obj)
    local p = obj
    local depth = 0
    while p and p ~= Workspace and depth < 18 do
        local n = norm(p.Name)
        if n == "colliders" or n == "monstercolliders" or n == "collider"
            or n == "colider" or n == "collisions" or n == "collision"
            or n == "hitboxes" or n == "hitbox" or n == "collisionparts"
            or n == "boundingbox" or n == "triggercolliders" then
            return true
        end
        p = p.Parent
        depth += 1
    end
    return false
end

local function partHasVisibleSurface(part)
    if not part or not part:IsA("BasePart") then return false end
    if isCollisionOnlyObject(part) then return false end
    if part.Transparency >= 0.97 then return false end
    if part.LocalTransparencyModifier >= 0.97 then return false end
    return true
end


-- Somente nomes e contexto relacionados a SAFE ZONE sao provas automaticas.
-- Nao trata toda parede colorida, spawn ou modelo SafeZone como porta.
-- Como os nomes internos nao foram confirmados via Dex++, o jogador tambem
-- pode clicar numa porta real para cadastrá-la (sem alterar o servidor).
local manualSafeDoors = {}

local function isSafeZoneName(name)
    local n = norm(name)
    return n:find("safezone", 1, true) ~= nil
        or n:find("safearea", 1, true) ~= nil
        or n:find("saferoom", 1, true) ~= nil
        or n:find("safespot", 1, true) ~= nil
        or n:find("zonasegura", 1, true) ~= nil
        or n:find("areasafe", 1, true) ~= nil
        or n:find("safetyzone", 1, true) ~= nil
end

local function isDoorName(name)
    local n = norm(name)
    for _, word in ipairs({"door", "gate", "entrance", "exit", "portal", "barrier",
        "passage", "opening", "porta", "portao", "entrada", "saida"}) do
        if n:find(word, 1, true) then return true end
    end
    return false
end

local function safeZoneAncestor(obj)
    local cursor = obj
    local depth = 0
    while cursor and cursor ~= Workspace and depth < 12 do
        if isSafeZoneName(cursor.Name) then return true end
        cursor = cursor.Parent
        depth += 1
    end
    return false
end

local function explicitSafeDoor(name)
    local n = norm(name)
    -- Aceita ambos os sentidos: SafeZoneDoor, DoorSafeZone,
    -- SafeDoor, SafeZoneExit, EntradaZonaSegura etc.
    if isSafeZoneName(name) and isDoorName(name) then return true end
    if n:find("safedoor", 1, true) or n:find("safegate", 1, true)
        or n:find("safeexit", 1, true) or n:find("safeentrance", 1, true)
        or n:find("portasegura", 1, true) or n:find("portadasafe", 1, true) then
        return true
    end
    return false
end

-- Em modelos com diversas pecas, prioriza o modelo da porta, nao a
-- pasta/zona inteira. Nunca sobe ate um agrupamento chamado apenas SafeZone.
local function safeDoorShape(obj, manual)
    if not obj or not insideWorkspace(obj) or insidePlayerCharacter(obj)
        or isCollisionOnlyObject(obj) then
        return nil
    end
    local start = obj
    if not (start:IsA("BasePart") or start:IsA("Model")) then return nil end
    local cursor = start
    local depth = 0
    while cursor and cursor ~= Workspace and depth < 7 do
        if (cursor:IsA("Model") or cursor:IsA("BasePart"))
            and isDoorName(cursor.Name) and sizeAllowed(cursor, "SafeDoors") then
            return cursor
        end
        cursor = cursor.Parent
        depth += 1
    end
    if manual then
        if start:IsA("Model") and sizeAllowed(start, "SafeDoors") then return start end
        if start:IsA("BasePart") then
            local model = start:FindFirstAncestorOfClass("Model")
            if model and sizeAllowed(model, "SafeDoors")
                and not isSafeZoneName(model.Name) then return model end
            return start
        end
    end
    return nil
end

local function safeDoorCandidate(obj)
    if not obj or not insideWorkspace(obj) or insidePlayerCharacter(obj)
        or isCollisionOnlyObject(obj) then return nil end
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return nil end
    local explicit = explicitSafeDoor(obj.Name)
    local inSafeZone = safeZoneAncestor(obj)
    if not explicit and not (inSafeZone and isDoorName(obj.Name)) then return nil end
    -- Se o nome aponta para a porta, mas o objeto e uma pasta grande,
    -- preferimos esperar por um filho com geometria para evitar falsos ESP.
    if explicit and sizeAllowed(obj, "SafeDoors") then return obj end
    return safeDoorShape(obj, false)
end

local function isAlreadySafeDoor(target)
    if tracked.SafeDoors[target] then return true end
    -- Quando ja marcamos um modelo, nao criamos destaques para cada peca.
    local p = target.Parent
    while p and p ~= Workspace do
        if tracked.SafeDoors[p] then return true end
        p = p.Parent
    end
    return false
end

local function registerSafeDoor(target, isManual)
    if not alive or not target or isCollisionOnlyObject(target)
        or not sizeAllowed(target, "SafeDoors") then return false end
    if not validPartPosition(anchorOf(target)) or insidePlayerCharacter(target) then return false end
    if isAlreadySafeDoor(target) then return true end

    -- Um modelo completo substitui seus filhos previamente marcados.
    if target:IsA("Model") then
        local redundant = {}
        for old in pairs(tracked.SafeDoors) do
            if old:IsDescendantOf(target) then table.insert(redundant, old) end
        end
        for _, old in ipairs(redundant) do
            manualSafeDoors[old] = nil
            remove("SafeDoors", old)
        end
    end

    -- A porta branca da fase final pode receber ambas as deteccoes.
    -- Evita um segundo Highlight na mesma geometria.
    if tracked.Doors[target] then remove("Doors", target) end
    if isManual then manualSafeDoors[target] = true end
    add("SafeDoors", target, "PORTA SAFE ZONE", categoryColors.SafeDoors)
    return tracked.SafeDoors[target] ~= nil
end

local function considerSafeDoor(obj)
    if not alive then return end
    local target = safeDoorCandidate(obj)
    if target then registerSafeDoor(target, false) end
end

local function considerDoor(obj)
    if not alive then return end
    local target, entry = doorCandidate(obj)
    if not target or not entry or not sizeAllowed(target, "Doors") then return end
    if tracked.Doors[target] or tracked.SafeDoors[target] then return end
    -- Se o modelo ja esta marcado, nao marca as pecas/placas novamente.
    local p = target.Parent
    while p and p ~= Workspace do
        if tracked.Doors[p] then return end
        p = p.Parent
    end
    -- Um modelo pode substituir o registro anterior de uma placa.
    if target:IsA("Model") then
        local olds = {}
        for old in pairs(tracked.Doors) do
            if old:IsDescendantOf(target) then table.insert(olds, old) end
        end
        for _, old in ipairs(olds) do remove("Doors", old) end
    end
    add("Doors", target, "PORTA " .. entry[1], entry[3])
end

local function consider(obj)
    if not alive or not insideWorkspace(obj) then return end
    local category, display = categoryFor(obj)
    if not category then return end
    local target = chooseTarget(obj, category)
    if not target or not sizeAllowed(target, category) then return end
    -- Trava extra: nao permitir objetos fora dos 13 IDs confirmados.
    if category == "Brushes" and collectibleItemFor(target) ~= target then return end
    -- Impede marcacoes duplicadas se um modelo tiver varios filhos com nomes iguais.
    if target:IsA("BasePart") and target.Parent and target.Parent:IsA("Model") then
        if tracked[category][target.Parent] then return end
    end
    add(category, target, detectName(target, category, display))
end

local function localPosition()
    local char = player.Character
    return validPartPosition(char and char:FindFirstChild("HumanoidRootPart"))
end

-- ===== CONTROLE LOCAL DE VELOCIDADE (v1.6) =====
-- WalkSpeed e uma propriedade do Humanoid. Em jogos que validam o
-- movimento no servidor, alterar o valor no cliente pode nao ser eficaz.
-- Nunca altera a velocidade dos outros jogadores.
local speed = {
    active = false,
    value = 24,
    min = 0,
    max = 250,
    keep = true,              -- reaplica apos resets locais do jogo
    humanoid = nil,
    original = nil,           -- lido novamente em cada respawn
    watch = nil,
    characterToken = 0,
}
local speedElapsed = 0
local refreshSpeedUi -- preenchido quando os controles forem criados

local function speedNumber(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.floor(math.clamp(v, speed.min, speed.max) * 10 + 0.5) / 10
end

local function prettySpeed(v)
    v = tonumber(v) or 0
    if math.abs(v - math.floor(v)) < 0.001 then
        return tostring(math.floor(v))
    end
    return string.format("%.1f", v)
end

local function setActualSpeed(target)
    local hum = speed.humanoid
    if not hum or not hum.Parent or hum.Health <= 0 then return false end
    return pcall(function()
        if math.abs(hum.WalkSpeed - target) > 0.01 then
            hum.WalkSpeed = target
        end
    end)
end

local function setSpeedActive(value)
    speed.active = value == true
    if speed.active then
        setActualSpeed(speed.value)
    elseif speed.original ~= nil then
        setActualSpeed(speed.original)
    end
    if refreshSpeedUi then refreshSpeedUi() end
end

local function setSpeedValue(value)
    local number = speedNumber(value)
    if number == nil then return false end
    speed.value = number
    if speed.active then setActualSpeed(number) end
    if refreshSpeedUi then refreshSpeedUi() end
    return true
end

local function bindSpeedCharacter(character)
    speed.characterToken += 1
    local token = speed.characterToken
    if speed.watch then
        speed.watch:Disconnect()
        speed.watch = nil
    end
    speed.humanoid = nil
    speed.original = nil
    if refreshSpeedUi then refreshSpeedUi() end

    task.spawn(function()
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 12)
        if not alive or token ~= speed.characterToken or not humanoid
            or not humanoid:IsA("Humanoid") then return end
        speed.humanoid = humanoid
        speed.original = humanoid.WalkSpeed
        speed.watch = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if not alive or token ~= speed.characterToken then return end
            -- Atualiza o valor original somente quando o controle esta OFF.
            -- Quando ON, nao substitui o valor original pelo valor ajustado.
            if not speed.active then
                speed.original = humanoid.WalkSpeed
            end
            if refreshSpeedUi then refreshSpeedUi() end
        end)
        if speed.active then setActualSpeed(speed.value) end
        if refreshSpeedUi then refreshSpeedUi() end
    end)
end

connect(player.CharacterAdded, bindSpeedCharacter)
if player.Character then bindSpeedCharacter(player.Character) end

local function restoreAndDisconnectSpeed()
    speed.active = false
    if speed.original ~= nil then setActualSpeed(speed.original) end
    if speed.watch then
        pcall(function() speed.watch:Disconnect() end)
        speed.watch = nil
    end
end

-- Interface independente de bibliotecas, GitHub ou API externa.
local gui = Instance.new("ScreenGui")
gui.Name = "ColorOrDieESP_UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(272, 602)
panel.Position = UDim2.new(0, 20, 0.14, 0)
panel.BackgroundColor3 = Color3.fromRGB(22, 25, 36)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 11)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(12, 11)
title.Size = UDim2.fromOffset(242, 21)
title.BackgroundTransparency = 1
title.Text = "COLOR OR DIE | ESP v1.8"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(12, 33)
subtitle.Size = UDim2.fromOffset(242, 17)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Monstros • Itens • Pinceis • Portas • Safe Zone"
subtitle.TextSize = 10
subtitle.Font = Enum.Font.Gotham
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextColor3 = Color3.fromRGB(175, 181, 198)
subtitle.Parent = panel

local buttons = {}
local buttonConfigs = {
    {"Monsters", "MONSTROS", 59},
    {"Paint", "BALDES DE TINTA", 99},
    {"Tools", "FERRAMENTAS", 139},
    {"Brushes", "PINCEIS", 179},
    {"Doors", "PORTAS DE TINTA", 219},
    {"SafeDoors", "PORTAS SAFE ZONE", 259},
    {"Distance", "MOSTRAR DISTANCIA", 299},
}

local function refreshButton(category)
    local button = buttons[category]
    if not button then return end
    local state = enabled[category]
    button.Text = button:GetAttribute("Caption") .. (state and "  [ON]" or "  [OFF]")
    button.TextColor3 = state and Color3.fromRGB(244, 246, 255) or Color3.fromRGB(149, 155, 173)
    button.BackgroundColor3 = state and Color3.fromRGB(41, 47, 67) or Color3.fromRGB(31, 34, 46)
end

for _, config in ipairs(buttonConfigs) do
    local category, caption, y = config[1], config[2], config[3]
    local b = Instance.new("TextButton")
    b.Name = category .. "Toggle"
    b.Position = UDim2.fromOffset(11, y)
    b.Size = UDim2.fromOffset(250, 34)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b:SetAttribute("Caption", caption)
    b.Parent = panel
    local rounded = Instance.new("UICorner")
    rounded.CornerRadius = UDim.new(0, 7)
    rounded.Parent = b
    buttons[category] = b
    refreshButton(category)
    connect(b.MouseButton1Click, function()
        if not alive then return end
        enabled[category] = not enabled[category]
        refreshButton(category)
        if category ~= "Distance" then
            for _, e in pairs(tracked[category]) do
                local on = enabled[category] and targetIsVisible(e.target, category)
                ensureHighlight(category, e, on, false, false)
                if e.safeBox then e.safeBox.Visible = on end
                e.billboard.Enabled = on
            end
        end
    end)
end

local counts = Instance.new("TextLabel")
counts.Position = UDim2.fromOffset(11, 516)
counts.Size = UDim2.fromOffset(250, 20)
counts.BackgroundTransparency = 1
counts.Text = "Detectados: pesquisando..."
counts.Font = Enum.Font.Gotham
counts.TextSize = 11
counts.TextXAlignment = Enum.TextXAlignment.Left
counts.TextColor3 = Color3.fromRGB(226, 231, 240)
counts.Parent = panel

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(11, 543)
status.Size = UDim2.fromOffset(250, 50)
status.BackgroundTransparency = 1
status.Text = "Chapter 1: pinceis numerados de 1 a 13. DELETE = menu."
status.TextWrapped = true
status.TextYAlignment = Enum.TextYAlignment.Top
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(159, 165, 188)
status.Parent = panel

local refreshBrushesButton = Instance.new("TextButton")
refreshBrushesButton.Name = "RefreshBrushes"
refreshBrushesButton.Position = UDim2.fromOffset(11, 383)
refreshBrushesButton.Size = UDim2.fromOffset(250, 38)
refreshBrushesButton.BackgroundColor3 = Color3.fromRGB(83, 48, 116)
refreshBrushesButton.BorderSizePixel = 0
refreshBrushesButton.Text = "ATUALIZAR PINCEIS COLETAVEIS"
refreshBrushesButton.TextColor3 = Color3.fromRGB(255, 250, 255)
refreshBrushesButton.TextSize = 12
refreshBrushesButton.Font = Enum.Font.GothamSemibold
refreshBrushesButton.Parent = panel
local refreshCorner = Instance.new("UICorner")
refreshCorner.CornerRadius = UDim.new(0, 7)
refreshCorner.Parent = refreshBrushesButton

connect(refreshBrushesButton.MouseButton1Click, function()
    if not alive then return end
    local folder = collectableContainer()
    if not folder then
        status.Text = "A pasta Collectable/Collectable nao esta carregada."
        return
    end
    local checked = 0
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local brush = collectibleItemFor(obj)
            if brush then
                consider(obj)
                checked += 1
            end
        end
    end
    status.Text = "Pinceis Chapter 1 (IDs 1-13). Pesquisa atualizada."
    print("[COD ESP v1.8] Varredura de pinceis concluida; componentes checados:", checked)
end)

-- Botao manual de recuperacao: util quando o renderizador continua
-- mostrando o nome do NPC, mas deixa de desenhar sua silhueta.
local refreshMonstersButton = Instance.new("TextButton")
refreshMonstersButton.Name = "RefreshMonsters"
refreshMonstersButton.Position = UDim2.fromOffset(11, 430)
refreshMonstersButton.Size = UDim2.fromOffset(250, 34)
refreshMonstersButton.BackgroundColor3 = Color3.fromRGB(80, 44, 59)
refreshMonstersButton.BorderSizePixel = 0
refreshMonstersButton.Text = "REPARAR CONTORNO DOS MONSTROS"
refreshMonstersButton.TextColor3 = Color3.fromRGB(255, 245, 247)
refreshMonstersButton.TextSize = 11
refreshMonstersButton.Font = Enum.Font.GothamSemibold
refreshMonstersButton.Parent = panel
local monsterCorner = Instance.new("UICorner")
monsterCorner.CornerRadius = UDim.new(0, 7)
monsterCorner.Parent = refreshMonstersButton

connect(refreshMonstersButton.MouseButton1Click, function()
    if not alive then return end
    local count = 0
    for _, e in pairs(tracked.Monsters) do
        ensureHighlight("Monsters", e, enabled.Monsters, true, true)
        e.monsterDirty = false
        count += 1
    end
    status.Text = "Contornos de " .. count .. " monstro(s) recriados."
end)

-- Marcacao assistida v1.8: clique -> selecao visivel -> confirmacao.
-- Ignora mouse.Target: esse alvo costuma ser uma hitbox invisivel de monstro.
local safeDoorClickArmed = false
local pendingSafeTarget = nil
local safePreview = nil

local markSafeButton = Instance.new("TextButton")
markSafeButton.Name = "MarkSafeDoor"
markSafeButton.Position = UDim2.fromOffset(11, 472)
markSafeButton.Size = UDim2.fromOffset(250, 35)
markSafeButton.BackgroundColor3 = Color3.fromRGB(33, 102, 80)
markSafeButton.BorderSizePixel = 0
markSafeButton.Text = "MARCAR PORTA SAFE (CLIQUE)"
markSafeButton.TextColor3 = Color3.fromRGB(238, 255, 247)
markSafeButton.TextSize = 11
markSafeButton.Font = Enum.Font.GothamSemibold
markSafeButton.Parent = panel
local markSafeCorner = Instance.new("UICorner")
markSafeCorner.CornerRadius = UDim.new(0, 7)
markSafeCorner.Parent = markSafeButton

local function clearSafePreview()
    if safePreview then
        pcall(function() safePreview:Destroy() end)
        safePreview = nil
    end
    pendingSafeTarget = nil
end

local function paintSafePreview(part)
    if safePreview then pcall(function() safePreview:Destroy() end) end
    safePreview = Instance.new("SelectionBox")
    safePreview.Name = "COD_Safe_Preview"
    safePreview.Adornee = part
    safePreview.Color3 = Color3.fromRGB(255, 239, 95)
    safePreview.SurfaceTransparency = 0.85
    safePreview.LineThickness = 0.08
    safePreview.Parent = playerGui
end

local function raycastVisibleSafeDoor(input)
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local pos = UserInputService:GetMouseLocation()
    if input and input.UserInputType == Enum.UserInputType.Touch then
        pos = Vector2.new(input.Position.X, input.Position.Y)
    end
    -- ScreenPointToRay considera a barra superior, pois GetMouseLocation
    -- usa coordenadas da janela inteira.
    local ray = camera:ScreenPointToRay(pos.X, pos.Y)
    local ignores = {}
    if player.Character then table.insert(ignores, player.Character) end

    -- Pula o conjunto inteiro de colliders quando ele existir.
    local gp = Workspace:FindFirstChild("GameplayParts")
    local colliders = gp and gp:FindFirstChild("Colliders")
    if colliders then table.insert(ignores, colliders) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    params.RespectCanCollide = false
    for _ = 1, 32 do
        params.FilterDescendantsInstances = ignores
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
        if not result then return nil end
        local part = result.Instance
        if partHasVisibleSurface(part) and not insidePlayerCharacter(part) then
            return part
        end
        table.insert(ignores, part)
    end
    return nil
end

connect(markSafeButton.MouseButton1Click, function()
    if not alive then return end
    if pendingSafeTarget then
        local chosen = pendingSafeTarget
        if registerSafeDoor(chosen, true) then
            print("[COD ESP v1.8] Porta Safe confirmada:", chosen:GetFullName())
            status.Text = "ESP Safe Zone confirmado: " .. chosen:GetFullName()
            safeDoorClickArmed = false
            clearSafePreview()
            markSafeButton.Text = "MARCAR PORTA SAFE (CLIQUE)"
        else
            status.Text = "Objeto nao e uma geometria valida. Clique outra vez na porta."
            clearSafePreview()
            safeDoorClickArmed = true
            markSafeButton.Text = "AGUARDANDO CLIQUE NA PORTA..."
        end
        return
    end
    safeDoorClickArmed = not safeDoorClickArmed
    markSafeButton.Text = safeDoorClickArmed
        and "AGUARDANDO CLIQUE NA PORTA..." or "MARCAR PORTA SAFE (CLIQUE)"
    status.Text = safeDoorClickArmed
        and "Clique na PARTE VISIVEL da porta. Colliders invisiveis sao ignorados."
        or "Marcacao Safe Zone cancelada."
end)

connect(UserInputService.InputBegan, function(input, processed)
    if not alive or not safeDoorClickArmed or processed then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end

    local selected = raycastVisibleSafeDoor(input)
    if not selected then
        clearSafePreview()
        status.Text = "Nenhuma parte visivel encontrada. Clique na face da porta."
        return
    end
    local target = safeDoorShape(selected, true)
    if not target or isCollisionOnlyObject(target) then
        clearSafePreview()
        status.Text = "Objeto invalido: " .. selected:GetFullName()
        return
    end

    pendingSafeTarget = target
    paintSafePreview(selected)
    local path = target:GetFullName()
    status.Text = "PREVIA: " .. path .. "  | Clique em CONFIRMAR para marcar, ou clique em outra parte."
    markSafeButton.Text = "CONFIRMAR PORTA SAFE"
    print("[COD ESP v1.8] PREVIA da porta (nao confirmada):", path)
end)

-- Painel de velocidade separado, aberto pelo botao principal.
-- Ele pode ser arrastado para nao atrapalhar a tela nem o Dex++.
local speedSettingsOpen = false
local speedMenuButton = Instance.new("TextButton")
speedMenuButton.Name = "SpeedSettingsButton"
speedMenuButton.Position = UDim2.fromOffset(11, 339)
speedMenuButton.Size = UDim2.fromOffset(250, 34)
speedMenuButton.BorderSizePixel = 0
speedMenuButton.Font = Enum.Font.GothamSemibold
speedMenuButton.TextSize = 12
speedMenuButton.Parent = panel
local speedMenuCorner = Instance.new("UICorner")
speedMenuCorner.CornerRadius = UDim.new(0, 7)
speedMenuCorner.Parent = speedMenuButton

local speedPanel = Instance.new("Frame")
speedPanel.Name = "SpeedSettings"
speedPanel.Size = UDim2.fromOffset(315, 367)
speedPanel.BackgroundColor3 = Color3.fromRGB(20, 25, 36)
speedPanel.BorderSizePixel = 0
speedPanel.Active = true
speedPanel.Draggable = true
speedPanel.Visible = false
speedPanel.ZIndex = 8
speedPanel.Parent = gui
local vpsz = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
if vpsz and vpsz.X < 680 then
    speedPanel.Position = UDim2.fromOffset(15, 55)
else
    speedPanel.Position = UDim2.fromOffset(310, 200)
end
local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 11)
speedCorner.Parent = speedPanel

local function speedText(name, textValue, pos, size, fontSize, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = pos
    label.Size = size
    label.BackgroundTransparency = 1
    label.Text = textValue
    label.Font = Enum.Font.Gotham
    label.TextSize = fontSize or 12
    label.TextColor3 = color or Color3.fromRGB(227, 231, 242)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 9
    label.Parent = speedPanel
    return label
end

local function speedButton(name, caption, position, size, bg)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Position = position
    b.Size = size
    b.BackgroundColor3 = bg or Color3.fromRGB(41, 47, 67)
    b.BorderSizePixel = 0
    b.Text = caption
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(247, 248, 255)
    b.ZIndex = 9
    b.Parent = speedPanel
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b
    return b
end

local speedTitle = speedText("SpeedTitle", "MOVIMENTO | VELOCIDADE", UDim2.fromOffset(13, 12),
    UDim2.fromOffset(274, 20), 15, Color3.fromRGB(255, 255, 255))
speedTitle.Font = Enum.Font.GothamBold
local speedClose = speedButton("CloseSpeed", "X", UDim2.fromOffset(284, 9), UDim2.fromOffset(20, 24))
speedClose.BackgroundTransparency = 1
speedClose.TextColor3 = Color3.fromRGB(229, 121, 131)

local speedToggle = speedButton("ToggleSpeed", "VELOCIDADE [OFF]", UDim2.fromOffset(12, 42),
    UDim2.fromOffset(291, 39))
speedText("SpeedValueLabel", "Velocidade (studs/s)", UDim2.fromOffset(12, 95),
    UDim2.fromOffset(150, 21), 12)
local minusSpeed = speedButton("MinusSpeed", "-5", UDim2.fromOffset(12, 125), UDim2.fromOffset(59, 34))
local plusSpeed = speedButton("PlusSpeed", "+5", UDim2.fromOffset(244, 125), UDim2.fromOffset(59, 34))
local speedInput = Instance.new("TextBox")
speedInput.Name = "CustomSpeed"
speedInput.Position = UDim2.fromOffset(80, 125)
speedInput.Size = UDim2.fromOffset(155, 34)
speedInput.BackgroundColor3 = Color3.fromRGB(35, 40, 56)
speedInput.BorderSizePixel = 0
speedInput.ClearTextOnFocus = false
speedInput.Text = prettySpeed(speed.value)
speedInput.PlaceholderText = "Ex.: 32"
speedInput.Font = Enum.Font.GothamBold
speedInput.TextSize = 15
speedInput.TextColor3 = Color3.fromRGB(255, 255, 255)
speedInput.ZIndex = 9
speedInput.Parent = speedPanel
local speedInputCorner = Instance.new("UICorner")
speedInputCorner.CornerRadius = UDim.new(0, 6)
speedInputCorner.Parent = speedInput

-- Controle deslizante de 0 ate 250. Entrada manual tambem aceita decimais.
local sliderBar = Instance.new("Frame")
sliderBar.Name = "SpeedSlider"
sliderBar.Position = UDim2.fromOffset(13, 179)
sliderBar.Size = UDim2.fromOffset(289, 9)
sliderBar.BackgroundColor3 = Color3.fromRGB(50, 55, 77)
sliderBar.BorderSizePixel = 0
sliderBar.Active = true
sliderBar.ZIndex = 9
sliderBar.Parent = speedPanel
local sliderCorner = Instance.new("UICorner")
sliderCorner.CornerRadius = UDim.new(1, 0)
sliderCorner.Parent = sliderBar
local sliderFill = Instance.new("Frame")
sliderFill.Name = "Fill"
sliderFill.BackgroundColor3 = Color3.fromRGB(77, 198, 255)
sliderFill.BorderSizePixel = 0
sliderFill.Size = UDim2.fromScale(speed.value / speed.max, 1)
sliderFill.ZIndex = 10
sliderFill.Parent = sliderBar
local sliderFillCorner = Instance.new("UICorner")
sliderFillCorner.CornerRadius = UDim.new(1, 0)
sliderFillCorner.Parent = sliderFill
local sliderKnob = Instance.new("Frame")
sliderKnob.Name = "Handle"
sliderKnob.Size = UDim2.fromOffset(15, 15)
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Position = UDim2.fromScale(speed.value / speed.max, 0.5)
sliderKnob.BackgroundColor3 = Color3.fromRGB(232, 245, 255)
sliderKnob.BorderSizePixel = 0
sliderKnob.Active = true
sliderKnob.ZIndex = 11
sliderKnob.Parent = sliderBar
local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = sliderKnob
speedText("SpeedRange", "0                                         250", UDim2.fromOffset(13, 192),
    UDim2.fromOffset(289, 17), 10, Color3.fromRGB(161, 169, 192))

local speedPresets = {16, 24, 32, 50}
for index, preset in ipairs(speedPresets) do
    local b = speedButton("SpeedPreset" .. preset, tostring(preset),
        UDim2.fromOffset(12 + (index - 1) * 74, 220), UDim2.fromOffset(69, 33))
    connect(b.MouseButton1Click, function()
        if alive then setSpeedValue(preset) end
    end)
end
local keepToggle = speedButton("KeepSpeed", "MANTER VELOCIDADE [ON]",
    UDim2.fromOffset(12, 265), UDim2.fromOffset(291, 32))
local restoreSpeed = speedButton("RestoreDefault", "DESATIVAR E RESTAURAR ORIGINAL",
    UDim2.fromOffset(12, 305), UDim2.fromOffset(291, 32), Color3.fromRGB(76, 49, 62))
local speedInfo = speedText("SpeedInfo", "", UDim2.fromOffset(12, 344),
    UDim2.fromOffset(291, 17), 10, Color3.fromRGB(164, 175, 199))

refreshSpeedUi = function()
    if not alive then return end
    local on = speed.active
    speedMenuButton.Text = "VELOCIDADE: " .. prettySpeed(speed.value) .. " [" .. (on and "ON" or "OFF") .. "]  >"
    speedMenuButton.TextColor3 = on and Color3.fromRGB(241, 253, 255) or Color3.fromRGB(204, 210, 232)
    speedMenuButton.BackgroundColor3 = on and Color3.fromRGB(30, 81, 91) or Color3.fromRGB(41, 47, 67)
    speedToggle.Text = on and "VELOCIDADE [ON]" or "VELOCIDADE [OFF]"
    speedToggle.BackgroundColor3 = on and Color3.fromRGB(30, 101, 85) or Color3.fromRGB(48, 53, 71)
    keepToggle.Text = "MANTER VELOCIDADE [" .. (speed.keep and "ON" or "OFF") .. "]"
    keepToggle.BackgroundColor3 = speed.keep and Color3.fromRGB(39, 68, 81) or Color3.fromRGB(48, 53, 71)
    if not speedInput:IsFocused() then speedInput.Text = prettySpeed(speed.value) end
    local ratio = math.clamp(speed.value / speed.max, 0, 1)
    sliderFill.Size = UDim2.fromScale(ratio, 1)
    sliderKnob.Position = UDim2.fromScale(ratio, 0.5)
    local current = speed.humanoid and speed.humanoid.Parent and prettySpeed(speed.humanoid.WalkSpeed) or "--"
    local original = speed.original ~= nil and prettySpeed(speed.original) or "--"
    speedInfo.Text = "Original: " .. original .. "    Atual: " .. current .. " studs/s"
end

connect(speedMenuButton.MouseButton1Click, function()
    if not alive then return end
    speedSettingsOpen = not speedSettingsOpen
    speedPanel.Visible = panel.Visible and speedSettingsOpen
end)
connect(speedClose.MouseButton1Click, function()
    speedSettingsOpen = false
    speedPanel.Visible = false
end)
connect(speedToggle.MouseButton1Click, function()
    if alive then setSpeedActive(not speed.active) end
end)
connect(minusSpeed.MouseButton1Click, function()
    if alive then setSpeedValue(speed.value - 5) end
end)
connect(plusSpeed.MouseButton1Click, function()
    if alive then setSpeedValue(speed.value + 5) end
end)
connect(speedInput.FocusLost, function()
    if not alive then return end
    local raw = speedInput.Text:gsub(",", ".")
    if not setSpeedValue(raw) then refreshSpeedUi() end
    speedInput.Text = prettySpeed(speed.value)
end)
connect(keepToggle.MouseButton1Click, function()
    if not alive then return end
    speed.keep = not speed.keep
    refreshSpeedUi()
end)
connect(restoreSpeed.MouseButton1Click, function()
    if not alive then return end
    setSpeedActive(false)
    if speed.original ~= nil then speed.value = speedNumber(speed.original) or speed.value end
    refreshSpeedUi()
end)

local draggingSpeedSlider = false
local function updateSliderFromPointer(x)
    local left, width = sliderBar.AbsolutePosition.X, sliderBar.AbsoluteSize.X
    if width <= 0 then return end
    local ratio = math.clamp((x - left) / width, 0, 1)
    setSpeedValue(math.floor((ratio * speed.max) * 10 + 0.5) / 10)
end
local function beginSpeedSlider(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingSpeedSlider = true
        updateSliderFromPointer(input.Position.X)
    end
end
connect(sliderBar.InputBegan, beginSpeedSlider)
connect(sliderKnob.InputBegan, beginSpeedSlider)
connect(UserInputService.InputChanged, function(input)
    if not alive or not draggingSpeedSlider then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        updateSliderFromPointer(input.Position.X)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingSpeedSlider = false
    end
end)
refreshSpeedUi()

local closeButton = Instance.new("TextButton")
closeButton.Name = "StopScript"
closeButton.Position = UDim2.fromOffset(243, 10)
closeButton.Size = UDim2.fromOffset(18, 20)
closeButton.BackgroundTransparency = 1
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 12
closeButton.TextColor3 = Color3.fromRGB(220, 118, 124)
closeButton.Parent = panel

local function stop()
    if not alive then return end
    restoreAndDisconnectSpeed()
    if safePreview then pcall(function() safePreview:Destroy() end) end
    alive = false
    for _, c in ipairs(links) do pcall(function() c:Disconnect() end) end
    for category, entries in pairs(tracked) do
        local oldTargets = {}
        for target in pairs(entries) do table.insert(oldTargets, target) end
        for _, target in ipairs(oldTargets) do remove(category, target) end
    end
    pcall(function() gui:Destroy() end)
    pcall(function() highlightFolder:Destroy() end)
    if env.ColorOrDieESP_Stop == stop then env.ColorOrDieESP_Stop = nil end
    print("[COLOR OR DIE ESP] Desligado.")
end
env.ColorOrDieESP_Stop = stop

connect(closeButton.MouseButton1Click, stop)
connect(UserInputService.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.Delete then
        panel.Visible = not panel.Visible
        speedPanel.Visible = panel.Visible and speedSettingsOpen
    end
end)

scanWorld = function()
    if not alive then return end
    local desc = Workspace:GetDescendants()
    -- Os monstros sao criados antes de ferramentas/portas para manter
    -- prioridade no sistema de Highlights do cliente.
    for _, obj in ipairs(desc) do
        if obj:IsA("Model") and monsterNames[norm(obj.Name)] then
            consider(obj)
        end
    end
    for index, obj in ipairs(desc) do
        if not alive then return end
        if obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool") then
            consider(obj)
        end
        if obj:IsA("Model") or obj:IsA("BasePart")
            or obj:IsA("TextLabel") or obj:IsA("TextButton") then
            considerSafeDoor(obj)
            considerDoor(obj)
        end
        -- Evita travar o jogo ao percorrer mapas muito grandes.
        if index % 400 == 0 then task.wait() end
    end
    -- Algumas placas 3D sao guardadas no PlayerGui e apontam para
    -- uma parte no Workspace via SurfaceGui/BillboardGui.Adornee.
    local guiDesc = playerGui:GetDescendants()
    for index, obj in ipairs(guiDesc) do
        if not alive then return end
        if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
            and worldAttachedUiText(obj) then
            considerDoor(obj)
        end
        if index % 400 == 0 then task.wait() end
    end
end

connect(Workspace.DescendantAdded, function(obj)
    if not alive then return end
    if obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool") then
        -- Aguarda o modelo receber as pecas quando spawnado de forma gradual.
        task.defer(function()
            if not alive then return end
            consider(obj)
            considerSafeDoor(obj)
            considerDoor(obj)
            local parent = obj.Parent
            if parent and parent:IsA("Model") then
                consider(parent)
                considerSafeDoor(parent)
                considerDoor(parent)
            end
        end)
    elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
        task.defer(function()
            if alive then considerDoor(obj) end
        end)
    end
end)

connect(playerGui.DescendantAdded, function(obj)
    if not alive then return end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        task.defer(function()
            if alive and worldAttachedUiText(obj) then considerDoor(obj) end
        end)
    end
end)

local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    if not alive then return end
    local delta = tonumber(dt) or 0
    speedElapsed += delta
    if speedElapsed >= 0.3 then
        speedElapsed = 0
        if speed.active and speed.keep then
            setActualSpeed(speed.value)
        end
        if speedPanel.Visible and refreshSpeedUi then refreshSpeedUi() end
    end
    elapsed += delta
    if elapsed < 0.35 then return end
    elapsed = 0

    local me = localPosition()
    local quantities = {Monsters = 0, Paint = 0, Tools = 0, Brushes = 0, Doors = 0, SafeDoors = 0}
    for category, entries in pairs(tracked) do
        local toRemove = {}
        for target, e in pairs(entries) do
            local pos = validPartPosition(e.anchor)
            local anchorChanged = false
            if category == "Monsters" then
                local currentAnchor = anchorOf(target)
                if currentAnchor and currentAnchor ~= e.anchor then
                    local currentPos = validPartPosition(currentAnchor)
                    if currentPos then
                        e.anchor = currentAnchor
                        e.billboard.Adornee = currentAnchor
                        pos = currentPos
                        anchorChanged = true
                    end
                end
            end
            if not insideWorkspace(target) or not pos
                or (category == "Brushes" and collectibleItemFor(target) ~= target) then
                table.insert(toRemove, target)
            else
                local visible = targetIsVisible(target, category)
                local show = visible and enabled[category]
                if category == "Monsters" then
                    -- Nao existe API para saber se um Highlight esta de fato
                    -- visivel na GPU. Entao fazemos manutencao preventiva:
                    -- reapontar se a geometria mudar ou a cada 8 segundos.
                    local forceRebind = e.monsterDirty or anchorChanged
                        or (os.clock() - (e.highlightLastRebind or 0) >= 8)
                    ensureHighlight(category, e, show, false, forceRebind)
                    e.monsterDirty = false
                else
                    ensureHighlight(category, e, show, false, false)
                end
                e.billboard.Enabled = show
                if e.safeBox then
                    e.safeBox.Visible = show
                    if e.safeBox.Adornee ~= e.anchor then e.safeBox.Adornee = e.anchor end
                    if e.safeBox.Size ~= e.anchor.Size then e.safeBox.Size = e.anchor.Size end
                end
                if visible then quantities[category] += 1 end
                if me and enabled.Distance then
                    e.label.Text = string.format("%s | %d studs", e.name, math.floor((pos - me).Magnitude + 0.5))
                else
                    e.label.Text = e.name
                end
            end
        end
        for _, target in ipairs(toRemove) do remove(category, target) end
    end

    counts.Text = string.format("M:%d T:%d F:%d P:%d Cor:%d Safe:%d",
        quantities.Monsters, quantities.Paint, quantities.Tools,
        quantities.Brushes, quantities.Doors, quantities.SafeDoors)
end)

task.spawn(function()
    scanWorld()
    if alive then
        local collectionFolder = collectableContainer()
        print("[COLOR OR DIE ESP] v1.8 carregado. PINCEIS: IDs 1-13; Safe Zone ESP ativo.",
            "Pasta:", collectionFolder and collectionFolder:GetFullName() or "NAO ENCONTRADA")
    end
    while alive do
        task.wait(7)
        if alive then scanWorld() end
    end
end)