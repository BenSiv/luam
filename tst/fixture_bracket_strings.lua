-- Fixture for tst/test_fix_strings.lua -- some plain text using
-- pre-Luam long-bracket strings, so that test has known, stable input
-- to convert, instead of depending on some other real source file
-- happening to still contain [[ ]] brackets (which is what broke when
-- lib/static/static.lua, this test's previous input, was deleted as
-- an orphaned duplicate).
s = [[first bracket string]]
t = [[second bracket string]]
