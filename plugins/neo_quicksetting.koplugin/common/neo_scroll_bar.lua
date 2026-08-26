local function apply_neo_scroll_bar()
    local _       = require("gettext")
    local Device  = require("device")
    local Geom    = require("ui/geometry")
    local Menu    = require("ui/widget/menu")
    local Screen  = Device.screen
    local UIManager = require("ui/uimanager")
    local pager   = require("common/neo_pager")
    pager.setPlugin(rawget(_G, "__NEO_UI_PLUGIN"))
    local target_menus = {
        filemanager = true,
        history = true,
        collections = true,
        library_view = true, -- Rakuyomi
    }

    local BAR_W_PCT = 0.92  -- track width as fraction of screen width

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)

        local is_bookmarks_menu = self.is_borderless
            and self.title_bar_fm_style
            and self.title_bar_left_icon == "appbar.menu"

        if not target_menus[self.name]
           and not (self.covers_fullscreen and self.is_borderless and self.title_bar_fm_style)
           and not is_bookmarks_menu then
            return
        end

        if not self.page_info or not self.page_info_text or not self.page_return_arrow then
            return
        end

        local menu   = self
        local scr_w  = Screen:getWidth()
        local bar_w  = math.floor(scr_w * BAR_W_PCT)
        local bar_x  = math.floor((scr_w - bar_w) / 2)   -- centred offset from left edge
        local foot_h = pager.getStyle() == "page_number" and pager.PN_FOOTER_H or pager.FOOTER_H
        local foot   = Geom:new{ w = scr_w, h = foot_h }

        self.page_info_text.getSize    = function() return foot end
        self.page_return_arrow.getSize = function() return foot end

        self.page_info.getSize = function() return foot end

        self.page_info.paintTo = function(_, bb, x, y)
            pager.paint(bb, x + bar_x, y, bar_w, foot_h, menu.page or 1, menu.page_num or 1)
        end

        local scr_h    = Screen:getHeight()
        local footer_y = self.dimen.y + self.dimen.h - foot_h
        local menu_x   = self.dimen.x

        local rz_left_x   = (menu_x + bar_x) / scr_w
        local rz_right_x  = (menu_x + bar_x + bar_w - pager.CHEV_W) / scr_w
        local rz_center_x = (menu_x + bar_x + pager.CHEV_W) / scr_w
        local rz_chev_w   = pager.CHEV_W / scr_w
        local rz_center_w = math.max(0, bar_w - pager.CHEV_W * 2) / scr_w
        local rz_y        = footer_y / scr_h
        local rz_h        = foot_h / scr_h

        self:registerTouchZones({
            {
                id = "neo_pn_left_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_left_x,   ratio_y = rz_y, ratio_w = rz_chev_w,   ratio_h = rz_h },
                handler = function()
                    if pager.getStyle() ~= "page_number" then return end
                    local target = menu.page > 1 and (menu.page - 1) or menu.page_num
                    menu:onGotoPage(target)
                    return true
                end,
            },
            {
                id = "neo_pn_right_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_right_x,  ratio_y = rz_y, ratio_w = rz_chev_w,   ratio_h = rz_h },
                handler = function()
                    if pager.getStyle() ~= "page_number" then return end
                    local target = menu.page < menu.page_num and (menu.page + 1) or 1
                    menu:onGotoPage(target)
                    return true
                end,
            },
            {
                id = "neo_pn_center_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_center_x, ratio_y = rz_y, ratio_w = rz_center_w, ratio_h = rz_h },
                handler = function()
                    if pager.getStyle() ~= "page_number" then return end
                    local createNeoDialog = require("common/neo_dialog")
                    local nb     = menu.page_num or 1
                    local dialog = createNeoDialog{
                        title           = _("Go to page"),
                        input           = "",
                        input_type      = "number",
                        input_hint      = "1 - " .. tostring(nb),
                        button_text     = "\u{F124} " .. _("Go"),
                        button_callback = function(dialog)
                            local p = tonumber(dialog:getInputText())
                            if p and p >= 1 and p <= nb then
                                UIManager:close(dialog)
                                menu:onGotoPage(math.floor(p))
                            end
                        end,
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                    return true
                end,
            },
            {
                id = "neo_pn_left_hold",
                ges = "hold",
                screen_zone = { ratio_x = rz_left_x,  ratio_y = rz_y, ratio_w = rz_chev_w, ratio_h = rz_h },
                handler = function()
                    if pager.getStyle() ~= "page_number" then return end
                    local skip   = pager.getHoldSkip()
                    local target = skip == "ends"
                        and 1
                        or  math.max(1, menu.page - (tonumber(skip) or 10))
                    menu:onGotoPage(target)
                    return true
                end,
            },
            {
                id = "neo_pn_right_hold",
                ges = "hold",
                screen_zone = { ratio_x = rz_right_x, ratio_y = rz_y, ratio_w = rz_chev_w, ratio_h = rz_h },
                handler = function()
                    if pager.getStyle() ~= "page_number" then return end
                    local skip   = pager.getHoldSkip()
                    local target = skip == "ends"
                        and menu.page_num
                        or  math.min(menu.page_num, menu.page + (tonumber(skip) or 10))
                    menu:onGotoPage(target)
                    return true
                end,
            },
        })

        self:_recalculateDimen()
    end
end

return apply_neo_scroll_bar
