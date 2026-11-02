wait(5)


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local osClock = os.clock

-- 配置项（仿照原脚本 Config）
local Config = {
    LoadTimeout = 10,
    RequireTimeout = 5,
}

-- 模块加载器（提取自原脚本 GameLib）
local GameLib = { Missing = {} }

--- 降级线程权限为 2（普通游戏脚本身份）后尝试 require，防止游戏模块检测执行器环境
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

--- 安全查找节点：优先在指定父节点下查找，找不到则搜索整个 ReplicatedStorage
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
-- 核心逻辑：加载 PetAssetResolver 并遍历 CachedPets
-- ==========================================

local PetScanner = {
    Resolver = nil,
    Templates = {}, -- 缓存获取到的结果: { [petName] = template }
}

function PetScanner.Init()
    local timeout = Config.LoadTimeout
    
    -- 1. 定位并加载 ReplicatedStorage.SharedUtilities.PetAssetResolver
    local sharedUtils = ReplicatedStorage:WaitForChild("SharedUtilities", timeout)
    local resolverModule = (sharedUtils and sharedUtils:WaitForChild("PetAssetResolver", timeout))
        or GameLib.Find(sharedUtils, "PetAssetResolver", "ModuleScript")
        
    PetScanner.Resolver = GameLib.Require(resolverModule)
    if not PetScanner.Resolver then
        warn("[PetScanner] 无法加载 PetAssetResolver，脚本终止。")
        return false
    end

    -- 2. 定位 ReplicatedStorage.CachedPets
    local cachedPets = ReplicatedStorage:WaitForChild("CachedPets", timeout)
        or ReplicatedStorage:FindFirstChild("CachedPets", true)
    if not cachedPets then
        warn("[PetScanner] 找不到 ReplicatedStorage.CachedPets 文件夹。")
        return false
    end

    -- 3. 遍历所有子节点并调用 GetTemplate(child.Name)
    local count = 0
    for _, child in ipairs(cachedPets:GetChildren()) do
        local petName = child.Name
        
        -- 注意：如果游戏内该函数是用冒号定义的 (function PetAssetResolver:GetTemplate(name))，
        -- 请将下方 pcall 参数改为: pcall(PetScanner.Resolver.GetTemplate, PetScanner.Resolver, petName)
        local ok, template = pcall(function()
            return PetScanner.Resolver.GetTemplate(petName)
        end)

        if ok and template ~= nil then
            PetScanner.Templates[petName] = template
            count = count + 1
            print(string.format("[PetScanner] 成功获取模板: %-20s -> %s", petName, tostring(template)))
        else
            warn(string.format("[PetScanner] 获取模板失败 (%s): %s", petName, tostring(template)))
        end
    end

    print(string.format("[PetScanner] 扫描完成，共解析 %d / %d 个宠物模板。", count, #cachedPets:GetChildren()))
    return true
end

-- 启动执行
PetScanner.Init()