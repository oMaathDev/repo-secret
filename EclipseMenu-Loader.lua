



--[[
    ECLIPSE LOADER
    Universal Game Detection
    Supported: Sniper Arena, BloxStrike, DOORS
]]

repeat task.wait() until game:IsLoaded()

local GAME_ID = game.GameId

local Games = {
    -- SNIPER ARENA
    [9534705677] = {
        Name = "Sniper Arena",
        Script = "https://raw.githubusercontent.com/oMaathDev/repo-secret/refs/heads/main/EclipseMenu-GID122446657157717.lua"
    },

    -- BLOXSTRIKE
    [7633926880] = {
        Name = "BloxStrike",
        Script = ""
    },

    -- DOORS
    [2440500124] = {
        Name = "DOORS",
        Script = "https://raw.githubusercontent.com/oMaathDev/repo-secret/refs/heads/main/EclipseMenu-GID6516141723.lua"
    },

    -- COLOR OR DIE
    [2440500123] = {
        Name = "COLOR OR DIE",
        Script = "https://raw.githubusercontent.com/oMaathDev/repo-secret/refs/heads/main/EclipseMenu-GID12931609417.lua"
    },

    -- FLEE THE FACILITY
    [2440500123] = {
        Name = "FLEE THE FACILITY",
        Script = "https://raw.githubusercontent.com/oMaathDev/repo-secret/refs/heads/main/EclipseMenu-GID893973440.lua"
    }
}

local SelectedGame = Games[GAME_ID]

if not SelectedGame then
    warn("[ECLIPSE] Jogo não suportado!")
    warn("[ECLIPSE] Game ID: " .. tostring(GAME_ID))
    return
end

print("[ECLIPSE] Jogo detectado: " .. SelectedGame.Name)

if SelectedGame.Script == "" then
    warn("[ECLIPSE] Script ainda não configurado para " .. SelectedGame.Name)
    return
end

local Success, Error = pcall(function()
    loadstring(game:HttpGet(SelectedGame.Script))()
end)

if Success then
    print("[ECLIPSE] Script carregado com sucesso!")
else
    warn("[ECLIPSE] Erro ao carregar: " .. tostring(Error))
end