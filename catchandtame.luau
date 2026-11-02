
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local osClock = os.clock

-- 配置项
local Config = {
    LoadTimeout = 10,
    RequireTimeout = 5,
    RequestDelay = 0.2, -- 每次请求之间的间隔（秒），如果依然提示 was not received 可适当调大（如 0.5）
}

-- 模块加载器（保持原脚本的安全加载机制）
local GameLib = { Missing = {} }

--- 降级线程权限为 2（普通游戏脚本身份）后尝试 require
function GameLib.RequireAsGame(module)
    local finished, ok, loaded = false, false, nil
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if read and identity == 2 then
            ok, loaded = pcall(require, module)
        end
        finished = true
    end)
    local deadline = osClock() + Config.RequireTimeout
    repeat
        if finished then break end
        task.wait()
    until osClock() > deadline
    return ok, loaded
end

--- 安全 require 模块：先直接尝试，失败则切换线程身份重试
function GameLib.Require(module)
    if not (module and module:IsA("ModuleScript")) then return nil end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    
    local again, retried = GameLib.RequireAsGame(module)
    if again then return retried end

    GameLib.Missing[module.Name] = true
    warn("[PetScanner] require " .. module.Name .. " failed:", loaded)
    return nil
end

--- 安全查找节点
function GameLib.Find(root, name, class)
    local found = root and root:FindFirstChild(name, true)
    if not (found and found:IsA(class)) then
        found = ReplicatedStorage:FindFirstChild(name, true)
    end
    if found and found:IsA(class) then return found end
    
    GameLib.Missing[name] = "Absent"
    warn("[PetScanner] " .. class .. " '" .. name .. "' not found")
    return nil
end

-- ==========================================
-- 核心逻辑：加载 Configs.Pets 并遍历 Key 调用 GetTemplate
-- ==========================================

local PetScanner = {
    Resolver = nil,
    PetsConfig = nil,
    Templates = {}, -- 缓存获取到的模型: { [petName] = Model }
}

function PetScanner.Init()
    local timeout = Config.LoadTimeout
    
    -- 1. 加载 ReplicatedStorage.SharedUtilities.PetAssetResolver
    local sharedUtils = ReplicatedStorage:WaitForChild("SharedUtilities", timeout)
    local resolverModule = (sharedUtils and sharedUtils:WaitForChild("PetAssetResolver", timeout))
        or GameLib.Find(sharedUtils, "PetAssetResolver", "ModuleScript")
        
    PetScanner.Resolver = GameLib.Require(resolverModule)
    if type(PetScanner.Resolver) ~= "table" then
        warn("[PetScanner] 无法加载 PetAssetResolver，脚本终止。")
        return false
    end

    -- 2. 加载 ReplicatedStorage.Configs.Pets
    local configsFolder = ReplicatedStorage:WaitForChild("Configs", timeout)
    local petsModule = (configsFolder and configsFolder:WaitForChild("Pets", timeout))
        or GameLib.Find(configsFolder, "Pets", "ModuleScript")
        
    PetScanner.PetsConfig = GameLib.Require(petsModule)
    if type(PetScanner.PetsConfig) ~= "table" then
        warn("[PetScanner] 无法加载 ReplicatedStorage.Configs.Pets，脚本终止。")
        return false
    end

    -- 3. 收集并排序所有 Key（方便按字母顺序查看日志）
    local petNames = {}
    for petName, petData in pairs(PetScanner.PetsConfig) do
        if type(petName) == "string" then
            table.insert(petNames, petName)
        end
    end
    table.sort(petNames)

    print(string.format("[PetScanner] 从 Configs.Pets 中读取到 %d 个宠物配置，开始获取模板...", #petNames))

    -- 4. 遍历所有 Key 并调用 PetAssetResolver.GetTemplate(petName)
    local successCount = 0
    for index, petName in ipairs(petNames) do
        -- 先检查本地 PetAssets 是否已经缓存过，若已缓存则无需等待冷却
        local cached = PetScanner.Resolver.GetCachedTemplate(petName)
        local ok, template = true, cached

        if not cached then
            ok, template = pcall(PetScanner.Resolver.GetTemplate, petName)
            if Config.RequestDelay > 0 then
                task.wait(Config.RequestDelay)
            end
        end

        if ok and template ~= nil then
            PetScanner.Templates[petName] = template
            successCount = successCount + 1
            print(string.format("[%d/%d] 成功获取模板: %-25s -> %s", index, #petNames, petName, template:GetFullName()))
        else
            warn(string.format("[%d/%d] 获取模板失败: %-25s (原因: %s)", index, #petNames, petName, tostring(template)))
        end
    end

    print(string.format("[PetScanner] 全部遍历完成！成功获取 %d / %d 个宠物模型（已存入 ReplicatedStorage.PetAssets）。", successCount, #petNames))
    return true
end

-- 启动执行
PetScanner.Init()