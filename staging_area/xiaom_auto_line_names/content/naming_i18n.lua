local M = {}
local labels = {
    zh_CN = {bus="公交",truck="卡车",tram="电车",train="铁路",ship="水运",aircraft="航空",helicopter="直升机",
        passengers="客运",goods="货运",mixed="客货混运",pending="待定",unknown="未知物品",join="、",space=""},
    en = {bus="Bus",truck="Truck",tram="Tram",train="Train",ship="Ship",aircraft="Aircraft",helicopter="Helicopter",
        passengers="Passenger",goods="Cargo",mixed="Mixed",pending="Pending",unknown="Unknown cargo",join=", ",space=" "},
}
local messages = {
    zh_CN = {bulk="批量自动命名",reload="重新载入配置",preview="线路命名预览",selected="所选线路",all="当前玩家全部线路",
        include="包含受保护的名称",confirm="确认并开启自动管理",close="关闭",refresh="刷新预览",previous="上一页",next="下一页",
        protected="受保护的名称",incomplete="站点或类型未确定",pending="等待改名命令完成",changed="线路或编号已变化，请刷新预览后再次确认",
        applying="正在重命名…",done="已提交，线路继续自动管理",imported="配置已保存到当前存档",error="配置错误：",empty="没有符合条件的线路",
        configNote="修改配置文件后请重启游戏，再重新载入配置。",working="正在准备预览…",old="原名称",new="新名称"},
    en = {bulk="Auto-name lines",reload="Reload configuration",preview="Line naming preview",selected="Selected lines",all="All player lines",
        include="Include protected names",confirm="Confirm and enable automatic updates",close="Close",refresh="Refresh preview",previous="Previous",next="Next",
        protected="Protected name",incomplete="Stops or transport type undetermined",pending="Waiting for rename command",changed="Lines or numbering changed. Refresh and confirm again.",
        applying="Renaming…",done="Submitted; automatic updates enabled",imported="Configuration saved in this savegame",error="Configuration error: ",empty="No eligible lines",
        configNote="Restart the game after editing the configuration file, then reload it here.",working="Preparing preview…",old="Old name",new="New name"},
}
function M.language(choice)
    if choice == "zh_CN" or choice == "en" then return choice end
    return type(_) == "function" and _("aln_language") == "zh_CN" and "zh_CN" or "en"
end
function M.labels(lang, override)
    local r = {}; for k,v in pairs(labels[lang] or labels.en) do r[k]=v end
    for k,v in pairs(override or {}) do r[k]=v end; return r
end
function M.text(lang, key) return (messages[lang] or messages.en)[key] or key end
return M
