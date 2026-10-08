"""Language coverage and locale-independent queue regression checks.

Prepared for user-authorized testing; adding this file does not run the checks.
"""
import unittest

from test_vehicle_upgrade import runtime
from test_vehicle_upgrade_ui import UI_FIXTURE


class I18nTests(unittest.TestCase):
    def test_chinese_variants_and_every_other_language_policy(self):
        lua = runtime("en")
        resolve = lua.eval('ug_require("upgrade_i18n.lua").resolve')
        for code in ("zh", "zh_CN", "zh_TW", "zh-HK", "ZH-cn", "zh_Hans"):
            with self.subTest(code=code):
                self.assertEqual(resolve(code), "zh")
        for code in ("en", "en_US", "en-GB", "de", "fr_FR", "ja", "ru", "", "zho", None, False):
            with self.subTest(code=code):
                self.assertEqual(resolve(code), "en")

    def test_unavailable_or_failing_profile_defaults_to_english(self):
        lua = runtime("zh_CN")
        lua.execute('''local tr = ug_require("upgrade_i18n.lua")
            assert(tr.refresh() == "zh")
            app = nil
            assert(tr.refresh() == "en" and tr.t("upgrade_button") == "Upgrade Vehicles")
            app = {getUserProfile = function() error("profile unavailable") end}
            assert(tr.refresh() == "en")
            app = {getUserProfile = function() return {getLanguage = function() return {} end} end}
            assert(tr.refresh() == "en")''')

    def ui_runtime(self, language):
        lua = runtime(language)
        lua.execute(UI_FIXTURE)
        lua.execute('''ui = ug_require("upgrade_ui.lua")
            entry = ug_require("upgrade_entry.lua")
            function uiStrings(node, values)
                values = values or {}
                if type(node) ~= "table" then return values end
                local p = node.params
                if p then
                    for _, s in ipairs({p.text or "", p.title or "", p.placeholderText or "", (p.meta or {}).tooltip or ""}) do
                        if s ~= "" then values[#values + 1] = s end
                    end
                end
                for _, child in pairs(node) do
                    if type(child) == "table" then uiStrings(child, values) end
                end
                return values
            end''')
        return lua

    def test_english_and_fallback_preview_cover_warnings_targets_and_failures(self):
        for language in ("en", "en_US", "de", "fr", "ja"):
            with self.subTest(language=language):
                lua = self.ui_runtime(language)
                output = lua.execute('''model(1,{1},10)
                    model(2,{1},20,{year=1950,electric=true,length=20})
                    vehicle(10,{part(1,1)},{refund=500});scan()
                    local r = row();r.expanded = true
                    controller.toggleGroup(r.snapshot.units[1].groupKey)
                    local tab = recipes.XiaomUpgradeVehicleTab({})
                    assert(find(tab,"xiaom-vehicle-upgrade-button").content.params.text == "Upgrade Vehicles")
                    local values = uiStrings(tab)
                    uiStrings(renderWindow(), values)
                    r.error = ug_require("upgrade_i18n.lua").t("purchase_check_retry")
                    uiStrings(renderWindow(), values)
                    native.snapshot = function() error("missing vehicle data") end
                    scan()
                    uiStrings(renderWindow(), values)
                    return table.concat(values,"\\n")''')
                self.assertIn("Vehicle Upgrade", output)
                self.assertIn("Depreciation Credit", output)
                self.assertIn("requires electrification", output)
                self.assertIn("Cannot read vehicle data", output)
                self.assertNotRegex(output, r"[\u3400-\u9fff]")

    def test_chinese_preview_and_entry_for_simplified_and_traditional_settings(self):
        for language in ("zh_CN", "zh_TW"):
            with self.subTest(language=language):
                lua = self.ui_runtime(language)
                output = lua.execute('''model(1,{1},10);model(2,{1},20,{year=1950})
                    vehicle(10,{part(1,1)},{refund=500});scan()
                    local values = uiStrings(recipes.XiaomUpgradeVehicleTab({}))
                    uiStrings(renderWindow(), values)
                    return table.concat(values,"\\n")''')
                self.assertIn("升级载具", output)
                self.assertIn("全公司升级方案", output)
                self.assertIn("折旧抵扣", output)

    def test_english_queue_completion_keeps_machine_status_and_blocks_duplicates(self):
        lua = runtime("fr")
        lua.execute('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});scan()
            assert(controller.read().language == "en" and row().status == "ready")
            preflight();assert(row().status == "queued")
            controller.step();assert(row().status == "applying" and #commands == 1)
            assert(not controller.confirm())
            finishCommand(true);controller.step()
            assert(row().status == "success" and not row().selected)
            assert(controller.read().message:find("Upgrade complete",1,true))
            assert(not controller.confirm() and #commands == 1)''')

    def test_english_failure_stops_remaining_queue_and_translates_reason(self):
        lua = runtime("en")
        lua.execute('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500})
            vehicle(20,{part(1,1)},{refund=400});scan();preflight();controller.step()
            finishCommand(false)
            assert(row(1).status == "failed" and row(2).status == "skipped")
            assert(row(1).error == "The native replacement command failed")
            assert(controller.read().message:find("remaining vehicles were not processed",1,true))''')

    def test_reopen_after_language_change_refreshes_stored_preview_text(self):
        lua = self.ui_runtime("zh_CN")
        lua.execute('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});scan()
            assert(controller.read().language == "zh")
            gameLanguage = "fr";ui.open(gameCtx)
            for _=1,100 do controller.step();if not controller.busy() then break end end
            assert(controller.read().language == "en")
            assert(renderWindow().params.title == "Vehicle Upgrade")
            assert(controller.read().message:find("Scan complete",1,true))''')


if __name__ == "__main__":
    unittest.main()
