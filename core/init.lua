local ADDON_NAME, ns = ...

ns = ns or {}
ns.name = ADDON_NAME
ns.Core = ns.Core or {}
ns.Tracker = ns.Tracker or {}
ns.UI = ns.UI or {}
ns.Options = ns.Options or {}
ns.Utils = ns.Utils or {}
ns.State = ns.State or {}

local orderedModules = {
  ns.Core,
  ns.Tracker,
  ns.UI,
  ns.Options,
  ns.Utils,
}

function ns:FinalizeAPI()
  for _, moduleTable in ipairs(orderedModules) do
    for key, value in pairs(moduleTable) do
      if rawget(self, key) == nil then
        rawset(self, key, value)
      end
    end
  end

  self.__apiFinalized = true
end
