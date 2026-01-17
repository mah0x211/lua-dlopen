rockspec_format = "3.0"
package = "dlopen"
version = "dev-1"
source = {
    url = "git+https://github.com/mah0x211/lua-dlopen.git",
}
description = {
    summary = "Call C functions in shared libraries using libffi for Lua.",
    detailed = [[`dlopen` provides Lua bindings for calling C functions in shared libraries using `dlopen` functions and `libffi`.]],
    homepage = "https://github.com/mah0x211/lua-dlopen",
    maintainer = "Masatoshi Fukunaga",
    license = "MIT",
}
dependencies = {
    "lua >= 5.1",
}
external_dependencies = {
    LIBFFI = {},
}
build_dependencies = {
    "luarocks-build-builtin-hook >= 0.1.0",
}
build = {
    type = "builtin-hook",
    before_build = "$(pkgconfig)",
    modules = {
        dlopen = {
            sources = {
                "src/dlopen.c",
            },
            libraries = {
                "ffi",
            },
            incdirs = {
                "$(LIBFFI_INCDIR)",
            },
            libdirs = {
                "$(LIBFFI_LIBDIR)",
            },
        },
    },
}
