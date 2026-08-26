
local InputDialog = require("ui/widget/inputdialog")
local UIManager   = require("ui/uimanager")

local function createNeoDialog(opts)
    local orig_onTap = InputDialog.onTap
    local dialog

    dialog = InputDialog:new{
        title      = opts.title,
        input      = opts.input or "",
        input_type = opts.input_type,
        input_hint = opts.input_hint,
        title_bar_left_icon = "close",
        title_bar_left_icon_tap_callback = function()
            UIManager:close(dialog)
            if opts.close_callback then opts.close_callback() end
        end,
        buttons = {
            {
                {
                    text             = opts.button_text,
                    is_enter_default = true,
                    callback         = function() opts.button_callback(dialog) end,
                },
            },
        },
    }

    function dialog:onTap(arg, ges)
        if self.deny_keyboard_hiding then return end
        if self:isKeyboardVisible() then
            local kb = self._input_widget and self._input_widget.keyboard
            if kb and kb.dimen
               and ges.pos:notIntersectWith(kb.dimen)
               and ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                self:onCloseKeyboard()
                UIManager:close(self)
                return true
            end
            return orig_onTap(self, arg, ges)
        else
            if ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                UIManager:close(self)
                return true
            end
        end
    end

    return dialog
end

return createNeoDialog
