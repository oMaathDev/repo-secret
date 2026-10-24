



---- SOURCE CODE [COLOR OR DIE]

--[[
    COLOR OR DIE | ESP v1.5
    Categorias: monstros, baldes de tinta, ferramentas, pinceis e portas coloridas.
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
    Distance = true,
}
local categoryColors = {
    Monsters = Color3.fromRGB(255, 70, 86),
    Paint = Color3.fromRGB(255, 213, 64),
    Tools = Color3.fromRGB(85, 196, 255),
    Brushes = Color3.fromRGB(205, 110, 255),
    Doors = Color3.fromRGB(248, 248, 248),
}
local tracked = {
    Monsters = {}, Paint = {}, Tools = {}, Brushes = {}, Doors = {}
}

-- Highlights fora dos modelos do mapa: se um NPC atualiza sua arvore de
-- objetos, o efeito nao e destruido junto de uma peca do personagem.
-- Tambem evita aninhamento de instancias Highlight entre modelos e pecas.
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "COD_ESP_v15_Highlights"
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
    return largest <= (category == "Monsters" and 100 or (category == "Doors" and 45 or 18))
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
    if category == "Monsters" or category == "Doors" then return true end
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
    billboard.StudsOffsetWorldSpace = Vector3.new(0, category == "Monsters" and 4.2 or (category == "Doors" and 3.2 or 2.2), 0)
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

local function considerDoor(obj)
    if not alive then return end
    local target, entry = doorCandidate(obj)
    if not target or not entry or not sizeAllowed(target, "Doors") then return end
    if tracked.Doors[target] then return end
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

-- Interface independente de bibliotecas, GitHub ou API externa.
local gui = Instance.new("ScreenGui")
gui.Name = "ColorOrDieESP_UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(272, 485)
panel.Position = UDim2.new(0, 20, 0.28, 0)
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
title.Text = "COLOR OR DIE | ESP v1.5"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(12, 33)
subtitle.Size = UDim2.fromOffset(242, 17)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Monstros • Tintas • Ferramentas • Pinceis • Portas"
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
    {"Distance", "MOSTRAR DISTANCIA", 259},
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
                e.billboard.Enabled = on
            end
        end
    end)
end

local counts = Instance.new("TextLabel")
counts.Position = UDim2.fromOffset(11, 398)
counts.Size = UDim2.fromOffset(250, 20)
counts.BackgroundTransparency = 1
counts.Text = "Detectados: pesquisando..."
counts.Font = Enum.Font.Gotham
counts.TextSize = 11
counts.TextXAlignment = Enum.TextXAlignment.Left
counts.TextColor3 = Color3.fromRGB(226, 231, 240)
counts.Parent = panel

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(11, 422)
status.Size = UDim2.fromOffset(250, 46)
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
refreshBrushesButton.Position = UDim2.fromOffset(11, 303)
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
    print("[COD ESP v1.5] Varredura de pinceis concluida; componentes checados:", checked)
end)

-- Botao manual de recuperacao: util quando o renderizador continua
-- mostrando o nome do NPC, mas deixa de desenhar sua silhueta.
local refreshMonstersButton = Instance.new("TextButton")
refreshMonstersButton.Name = "RefreshMonsters"
refreshMonstersButton.Position = UDim2.fromOffset(11, 350)
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
            considerDoor(obj)
            local parent = obj.Parent
            if parent and parent:IsA("Model") then
                consider(parent)
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
    elapsed += tonumber(dt) or 0
    if elapsed < 0.35 then return end
    elapsed = 0

    local me = localPosition()
    local quantities = {Monsters = 0, Paint = 0, Tools = 0, Brushes = 0, Doors = 0}
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

    counts.Text = string.format("M:%d  T:%d  F:%d  P:%d  Portas:%d",
        quantities.Monsters, quantities.Paint, quantities.Tools,
        quantities.Brushes, quantities.Doors)
end)

task.spawn(function()
    scanWorld()
    if alive then
        local collectionFolder = collectableContainer()
        print("[COLOR OR DIE ESP] v1.5 carregado. PINCEIS: IDs 1-13; sem aprendizado.",
            "Pasta:", collectionFolder and collectionFolder:GetFullName() or "NAO ENCONTRADA")
    end
    while alive do
        task.wait(7)
        if alive then scanWorld() end
    end
end)