local src = debug.getinfo(1, "S").source or ""
local path = (src:sub(1, 1) == "@") and src:sub(2):match("^(.*)/common/[^/]+$") or nil
if path and path:sub(1, 1) ~= "/" then
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    local cwd = ok and lfs and lfs.currentdir()
    if cwd then path = cwd .. "/" .. path end
end
return path
