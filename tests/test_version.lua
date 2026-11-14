local version = require("input_grader.version")
local T = require("helpers")

local function newest_changelog_version()
  local f = assert(io.open("CHANGELOG.md", "r"))
  local text = f:read("*a")
  f:close()
  return text:match("\n## (%d+%.%d+%.%d+)\n")
end

return {
  {
    "the version is semantic: major.minor.patch",
    function()
      T.truthy(version:match("^%d+%.%d+%.%d+$"), version)
    end,
  },
  {
    "the version is the newest section of the changelog, so a release cannot ship without its notes",
    function()
      T.eq(version, newest_changelog_version())
    end,
  },
}
