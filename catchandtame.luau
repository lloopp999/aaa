local ReplicatedStorage = game:GetService("ReplicatedStorage")
local osClock = os.clock

-- 配置项
local Config = {
    LoadTimeout = 10,
    RequireTimeout = 5,
    RequestDelay = 0.2, -- 每次请求之间的间隔（秒）
}

-- 排除列表（共 837 个已排除的宠物名称）
local ExcludedList = {
    
}

-- 将数组转换为 O(1) 查询的哈希表
local ExcludedPets = {}
for _, name in ipairs(ExcludedList) do
    ExcludedPets[name] = true
end

-- 模块加载器
local GameLib = { Missing = {} }

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
-- 核心逻辑：过滤排除列表并调用 GetTemplate
-- ==========================================

local PetScanner = {
    Resolver = nil,
    PetsConfig = nil,
    Templates = {},
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

    -- 3. 收集并过滤所有未排除的 Key
    local petNames = {}
    local skippedCount = 0
    for petName, _ in pairs(PetScanner.PetsConfig) do
        if type(petName) == "string" then
            if ExcludedPets[petName] then
                skippedCount += 1
            else
                table.insert(petNames, petName)
            end
        end
    end
    table.sort(petNames)

    print(string.format("[PetScanner] 已跳过 %d 个排除项，剩余 %d 个宠物待获取模板...", skippedCount, #petNames))

    -- 4. 遍历剩余的 Key 并调用 PetAssetResolver.GetTemplate(petName)
    local successCount = 0
    for index, petName in ipairs(petNames) do
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
            successCount += 1
            print(string.format("[%d/%d] 成功获取模板: %-25s -> %s", index, #petNames, petName, template:GetFullName()))
        else
            warn(string.format("[%d/%d] 获取模板失败: %-25s (原因: %s)", index, #petNames, petName, tostring(template)))
        end
    end

    print(string.format("[PetScanner] 全部遍历完成！成功获取 %d / %d 个新宠物模型。", successCount, #petNames))
    return true
end

-- 启动执行
PetScanner.Init()