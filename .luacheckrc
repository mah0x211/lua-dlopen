std = "max"
include_files = {
    "*.lua",
    "test/*_test.lua",
}
ignore = {
    -- unused argument
    '212',
    -- line is too long
    '631',
}
