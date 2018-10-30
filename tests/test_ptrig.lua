local luaunit=require("luaunit")
local ubx=require("ubx")
local utils=require("utils")
local bd = require("blockdiagram")

local assert_equals = luaunit.assert_equals

local count_num_trigs = [[
local ubx=require "ubx"

local p_ramp_cnt, p_test_result

function init(b)
   ubx.inport_add(b, "ramp_cnt", "ramp counter in", "uint64_t", 1)
   ubx.outport_add(b, "test_result", "test results", "int", 1)
   p_ramp_cnt = ubx.port_get(b, "ramp_cnt")
   p_test_result = ubx.port_get(b, "test_result")
   return true
end

local trig_cnt = 0
local test_result = 999

function step(b)
   trig_cnt=trig_cnt+1

   local _, res = p_ramp_cnt:read()
   if trig_cnt ~= res:tolua() then
      test_result = -1
   end

   ubx.port_write(p_test_result, test_result)
end

function cleanup(b)
   ubx.port_rm(b, "ramp_cnt")
   ubx.port_rm(b, "test_result")
end
]]

local sys1 = bd.system {
   imports = { "stdtypes", "ptrig", "ramp_uint64", "lfds_cyclic", "luablock" },
   blocks = {
      { name="ramp", type="ramp_uint64" },
      { name="tester", type="lua/luablock" },
      { name="trig", type="std_triggers/ptrig" },
   },
   connections = {
      { src="ramp.out", tgt="tester.ramp_cnt" },
   },

   configurations = {
      { name="ramp", config = { start=0, slope=1 } },
      { name="tester", config = { lua_str=count_num_trigs } },
      { name="trig", config = { period = {sec=0, usec=100000 },
				trig_blocks={
				   { b="#ramp", num_steps=1, measure=0 },
				   { b="#tester", num_steps=1, measure=0 } } } },
   },
}

function test_count_num_trigs()
   local ni = sys1:launch{ nostart=true, verbose=false }
   local p_result = ubx.port_clone_conn(ni:b("tester"), "test_result")
   sys1:startup(ni)
   ubx.clock_mono_sleep(1)
   ni:b("trig"):do_stop()
   local _, res = p_result:read()
   assert_equals(res:tolua(), 999)
   sys1:pulldown(ni)
end


---
--- timing statistics test
---

local dur_test_block_tmpl = [[
local ubx=require "ubx"

function step(b)
   ubx.clock_mono_sleep($SEC, $NSEC)
end
]]

local function gen_dur_test_block(sec, nsec)
   return utils.expand(dur_test_block_tmpl, { SEC=sec, NSEC=nsec})
end


local sys2 = bd.system {
   imports = { "stdtypes", "ptrig", "lfds_cyclic", "luablock" },
   blocks = {
      { name="tb1", type="lua/luablock" },
      { name="tb2", type="lua/luablock" },
      { name="tb3", type="lua/luablock" },
      { name="trig", type="std_triggers/ptrig" },
   },
   configurations = {
      { name="tb1", config = { lua_str=gen_dur_test_block(0, 10*1000*1000) } },
      { name="tb2", config = { lua_str=gen_dur_test_block(0, 50*1000*1000) } },
      { name="tb3", config = { lua_str=gen_dur_test_block(0, 100*1000*1000) } },
      { name="trig", config = { period = {sec=0, usec=100000 },
				tstats_print_on_stop = 1,
				trig_blocks={
				   { b="#tb1", num_steps=1, measure=1 },
				   { b="#tb2", num_steps=1, measure=1 },
				   { b="#tb3", num_steps=1, measure=1 } } } },
   },
}

function test_tstats()
   local ni = sys2:launch{ nostart=true, verbose=false }
   local p_tstats = ubx.port_clone_conn(ni:b("trig"), "tstats", 10)

   sys2:startup(ni)
   ubx.clock_mono_sleep(3)
   ni:b("trig"):do_stop()

   while true do
      local cnt, res = p_tstats:read()
      if cnt <= 0 then break end
      print(res)
   end

   -- give ptrig some time to shutdown cleanly
   ubx.clock_mono_sleep(1)
   sys2:pulldown(ni)
end


os.exit( luaunit.LuaUnit.run() )