---
--- This script is used to configure to build the project.
--- It is used to check whether the current platform is supported.
---
local util = require('luarocks.util')
local configh = require('configh')
local rockspec = ...

-- Create a config.h file
local cfgh = configh(rockspec.variables.CC)
cfgh:output_status(true)
cfgh:add_cppflag('-I' .. rockspec.variables.LIBFFI_INCDIR)
for header, decls in pairs({
    ['ffi.h'] = {
        'FFI_OK',
        'FFI_BAD_TYPEDEF',
        'FFI_BAD_ABI',
        'FFI_BAD_ARGTYPE',
    },
}) do
    if cfgh:check_header(header) then
        for _, decl in ipairs(decls) do
            cfgh:check_decl(header, decl)
        end
    end
end
assert(cfgh:flush('src/config.h'))

if os.getenv('DLOPEN_COVERAGE') then
    -- Enable code coverage flags
    local variables = rockspec.variables
    variables.CFLAGS = table.concat({
        variables.CFLAGS,
        '-O0 -g --coverage',
    }, ' ')
    variables.LIBFLAG = table.concat({
        variables.LIBFLAG,
        '--coverage',
    }, ' ')
    -- Print out the enabled flags
    util.printout("Enabling DLOPEN_COVERAGE flag...")
    util.printout("CFLAGS: " .. variables.CFLAGS)
    util.printout("LIBFLAG: " .. variables.LIBFLAG)
end
