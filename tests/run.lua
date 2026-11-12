-- Minimal test runner: `lua tests/run.lua` from the repo root, any Lua 5.1+ or LuaJIT.
package.path = "lua/?.lua;tests/?.lua;" .. package.path

local files = {
  "test_checker", "test_inputs", "test_grader", "test_bench", "test_overlay", "test_launcher",
}

local passed, failed = 0, {}
for _, name in ipairs(files) do
  local ok, cases = pcall(require, name)
  if not ok then
    table.insert(failed, name .. ": " .. tostring(cases))
  else
    for _, case in ipairs(cases) do
      local ok_case, err = pcall(case[2])
      if ok_case then
        passed = passed + 1
      else
        table.insert(failed, name .. " > " .. case[1] .. ": " .. tostring(err))
      end
    end
  end
end

print(string.format("%d passed, %d failed (%s)", passed, #failed, _VERSION))
for _, f in ipairs(failed) do print("FAIL " .. f) end
os.exit(#failed == 0 and 0 or 1)
