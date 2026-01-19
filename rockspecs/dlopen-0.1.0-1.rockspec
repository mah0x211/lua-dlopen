rockspec_format = "3.0"
package = "dlopen"
version = "0.1.0-1"
source = {
    url = "git+https://github.com/mah0x211/lua-dlopen.git",
    tag = "v0.1.0",
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
    "luarocks-build-hooks >= 0.1.0",
    "configh >= 0.3.0",
}
build = {
    type = "hooks",
    before_build = {
        "$(pkgconfig)",
        "$(extra-vars)",
        "preprocess.lua",
    },
    extra_variables = {
        CFLAGS = "-Wall -Wno-trigraphs -Wmissing-field-initializers -Wreturn-type -Wmissing-braces -Wparentheses -Wno-switch -Wunused-function -Wunused-label -Wunused-parameter -Wunused-variable -Wunused-value -Wuninitialized -Wunknown-pragmas -Wshadow -Wsign-compare",
    },
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
