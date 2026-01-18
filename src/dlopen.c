/**
 * Copyright (C) 2026 Masatoshi Fukunaga
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
#include "./config.h"
// POSIX
#include <dlfcn.h>
#include <ffi.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
// Lua
#include <lauxlib.h>
#include <lua.h>

#define MODULE_MT "dlopen"

#define FFI_MAX_ARGS 32

typedef enum {
    T_VOID,
    T_VOID_PTR,
    T_CHAR_PTR,
    T_CHAR,
    T_SCHAR,
    T_UCHAR,
    T_SHORT,
    T_USHORT,
    T_INT8,
    T_UINT8,
    T_INT16,
    T_UINT16,
    T_INT,
    T_UINT,
    T_INT32,
    T_UINT32,
    T_INT64,
    T_UINT64,
    T_LONG,
    T_ULONG,
    T_LONG_LONG,
    T_ULONG_LONG,
    T_FLOAT,
    T_DOUBLE,
    T_SIZE_T,
    T_SSIZE_T,

    // sentinel value - must be last
    // used for array sizing and iteration bounds
    T_LAST,
} datatype_t;

typedef struct syminfo_st syminfo_t;

struct syminfo_st {
    int ref;
    void *addr;
    syminfo_t *next;
    // function signature for FFI calls
    size_t len;
    char *name;
    datatype_t ret_type;
    ffi_type *ret_ffi_type;
    size_t nargs;
    datatype_t arg_types[FFI_MAX_ARGS];
    ffi_type *arg_ffi_types[FFI_MAX_ARGS]; // must remain valid for cif
    ffi_cif cif;
};

typedef struct {
    void *handle;
    char *path;
    syminfo_t *symbols_head;
    syminfo_t *symbols_tail;
} dso_t;

#if SIZE_MAX == UINT32_MAX
# define FFI_TYPE_SIZE_T  ffi_type_uint32
# define FFI_TYPE_SSIZE_T ffi_type_sint32
#elif SIZE_MAX == UINT64_MAX
# define FFI_TYPE_SIZE_T  ffi_type_uint64
# define FFI_TYPE_SSIZE_T ffi_type_sint64
#else
# error "Unsupported size_t width"
#endif

static inline const char *ffi_status_message(ffi_status st)
{
    switch (st) {
    case FFI_OK:
        return "FFI_OK";
    case FFI_BAD_TYPEDEF:
        return "FFI_BAD_TYPEDEF (invalid ffi_type definition)";
    case FFI_BAD_ABI:
        return "FFI_BAD_ABI (unsupported ABI)";
#ifdef HAS_FFI_BAD_ARGTYPE
    case FFI_BAD_ARGTYPE:
        return "FFI_BAD_ARGTYPE (invalid argument type)";
#endif
    default:
        return "FFI_UNKNOWN_STATUS";
    }
}

static datatype_t check_ffitype(lua_State *L, int idx, ffi_type **ffi_type_out)
{
    static const char *const type_names[] = {
        [T_VOID]       = "void",
        [T_VOID_PTR]   = "void*",
        [T_CHAR_PTR]   = "char*",
        [T_CHAR]       = "char",
        [T_SCHAR]      = "signed char",
        [T_UCHAR]      = "unsigned char",
        [T_SHORT]      = "short",
        [T_USHORT]     = "unsigned short",
        [T_INT8]       = "int8",
        [T_UINT8]      = "uint8",
        [T_INT16]      = "int16",
        [T_UINT16]     = "uint16",
        [T_INT]        = "int",
        [T_UINT]       = "unsigned int",
        [T_INT32]      = "int32",
        [T_UINT32]     = "uint32",
        [T_INT64]      = "int64",
        [T_UINT64]     = "uint64",
        [T_LONG]       = "long",
        [T_ULONG]      = "unsigned long",
        [T_LONG_LONG]  = "long long",
        [T_ULONG_LONG] = "unsigned long long",
        [T_FLOAT]      = "float",
        [T_DOUBLE]     = "double",
        [T_SIZE_T]     = "size_t",
        [T_SSIZE_T]    = "ssize_t",
        NULL,
    };

    // luaL_checkoption will raise error for unknown option
    switch ((datatype_t)luaL_checkoption(L, idx, NULL, type_names)) {
    default:
        // should never reach here: implementation bug (missing case)
        luaL_error(L, "missing case for datatype");

#define FFI_TYPE_CASE(TYPE_ENUM, FFI_TYPE_PTR)                                 \
    case TYPE_ENUM:                                                            \
        *ffi_type_out = &FFI_TYPE_PTR;                                         \
        return TYPE_ENUM

        FFI_TYPE_CASE(T_VOID, ffi_type_void);
        FFI_TYPE_CASE(T_VOID_PTR, ffi_type_pointer);
        FFI_TYPE_CASE(T_CHAR_PTR, ffi_type_pointer);
        FFI_TYPE_CASE(T_CHAR, ffi_type_schar);
        FFI_TYPE_CASE(T_SCHAR, ffi_type_schar);
        FFI_TYPE_CASE(T_UCHAR, ffi_type_uchar);
        FFI_TYPE_CASE(T_SHORT, ffi_type_sshort);
        FFI_TYPE_CASE(T_USHORT, ffi_type_ushort);
        FFI_TYPE_CASE(T_INT8, ffi_type_sint8);
        FFI_TYPE_CASE(T_UINT8, ffi_type_uint8);
        FFI_TYPE_CASE(T_INT16, ffi_type_sint16);
        FFI_TYPE_CASE(T_UINT16, ffi_type_uint16);
        FFI_TYPE_CASE(T_INT, ffi_type_sint);
        FFI_TYPE_CASE(T_UINT, ffi_type_uint);
        FFI_TYPE_CASE(T_INT32, ffi_type_sint32);
        FFI_TYPE_CASE(T_UINT32, ffi_type_uint32);
        FFI_TYPE_CASE(T_INT64, ffi_type_sint64);
        FFI_TYPE_CASE(T_UINT64, ffi_type_uint64);
        FFI_TYPE_CASE(T_LONG, ffi_type_slong);
        FFI_TYPE_CASE(T_ULONG, ffi_type_ulong);
        FFI_TYPE_CASE(T_LONG_LONG, ffi_type_sint64);
        FFI_TYPE_CASE(T_ULONG_LONG, ffi_type_uint64);
        FFI_TYPE_CASE(T_FLOAT, ffi_type_float);
        FFI_TYPE_CASE(T_DOUBLE, ffi_type_double);
        FFI_TYPE_CASE(T_SIZE_T, FFI_TYPE_SIZE_T);
        FFI_TYPE_CASE(T_SSIZE_T, FFI_TYPE_SSIZE_T);

#undef FFI_TYPE_CASE
    }
}

typedef union {
    void *p;
    int8_t i8;
    uint8_t u8;
    int16_t i16;
    uint16_t u16;
    int32_t i32;
    uint32_t u32;
    int64_t i64;
    uint64_t u64;
    char c;
    signed char sc;
    unsigned char uc;
    short s;
    unsigned short us;
    int i;
    unsigned int ui;
    long l;
    unsigned long ul;
    long long ll;
    unsigned long long ull;
    float f;
    double d;
    size_t sz;
    ssize_t ssz;
} callval_u;

static int symcall_lua(lua_State *L)
{
    // exclude module userdata
    int nargs            = lua_gettop(L) - 1;
    syminfo_t *sym       = (syminfo_t *)lua_touserdata(L, lua_upvalueindex(1));
    // prepare return value
    callval_u retval     = {0};
    void *RETVAL[T_LAST] = {
        [T_VOID]       = NULL, // no return value for void
        [T_VOID_PTR]   = &retval.p,
        [T_CHAR_PTR]   = &retval.p,
        [T_CHAR]       = &retval.c,
        [T_SCHAR]      = &retval.sc,
        [T_UCHAR]      = &retval.uc,
        [T_SHORT]      = &retval.s,
        [T_USHORT]     = &retval.us,
        [T_INT8]       = &retval.i8,
        [T_UINT8]      = &retval.u8,
        [T_INT16]      = &retval.i16,
        [T_UINT16]     = &retval.u16,
        [T_INT]        = &retval.i,
        [T_UINT]       = &retval.ui,
        [T_INT32]      = &retval.i32,
        [T_UINT32]     = &retval.u32,
        [T_INT64]      = &retval.i64,
        [T_UINT64]     = &retval.u64,
        [T_LONG]       = &retval.l,
        [T_ULONG]      = &retval.ul,
        [T_LONG_LONG]  = &retval.ll,
        [T_ULONG_LONG] = &retval.ull,
        [T_FLOAT]      = &retval.f,
        [T_DOUBLE]     = &retval.d,
        [T_SIZE_T]     = &retval.sz,
        [T_SSIZE_T]    = &retval.ssz,
    };
    void *ret_value                = RETVAL[sym->ret_type];
    // prepare argument values
    callval_u args[FFI_MAX_ARGS]   = {0};
    void *arg_values[FFI_MAX_ARGS] = {NULL};

    // check number of arguments
    if (sym->nargs != (size_t)nargs) {
        return luaL_error(L,
                          "invalid number of arguments for symbol '%s': "
                          "expected %d but got %d",
                          sym->name, (int)sym->nargs, nargs);
    }

    // check return-value
    if (!ret_value && sym->ret_type != T_VOID) {
        return luaL_error(L, "unsupported return type for symbol '%s'",
                          sym->name);
    }

    // check arguments
    for (int i = 0; i < nargs; i++) {
        int index = 2 + i;

        switch (sym->arg_types[i]) {
        default:
            return luaL_error(L, "unsupported argument type for symbol '%s'",
                              sym->name);

        case T_VOID:
            // GUARD: void should be rejected by dlsym_lua(), but this case
            //        provides a safety net for implementation bugs
            return luaL_error(L, "argument %d: void cannot be used as argument",
                              i + 1);

#define CHECK_RVAL2LVAL(LVAL, RVAL, LUA_CHECK_FUNC)                            \
    RVAL = (typeof(RVAL))LUA_CHECK_FUNC(L, index);                             \
    LVAL = (void *)&RVAL;

        case T_VOID_PTR:
            switch (lua_type(L, index)) {
            case LUA_TNIL:
            case LUA_TNONE:
                args[i].p     = NULL;
                arg_values[i] = &args[i].p;
                break;
            case LUA_TLIGHTUSERDATA:
            case LUA_TUSERDATA:
                CHECK_RVAL2LVAL(arg_values[i], args[i].p, lua_topointer);
                break;
            default:
                return luaL_error(
                    L,
                    "argument %d: void* requires nil, lightuserdata "
                    "or userdata, got %s",
                    i + 1, lua_typename(L, lua_type(L, index)));
            }
            break;

        case T_CHAR_PTR:
            switch (lua_type(L, index)) {
            case LUA_TNIL:
            case LUA_TNONE:
                args[i].p     = NULL;
                arg_values[i] = &args[i].p;
                break;
            case LUA_TSTRING:
                CHECK_RVAL2LVAL(arg_values[i], args[i].p, lua_tostring);
                break;
            default:
                return luaL_error(
                    L, "argument %d: char* requires nil or string, got %s",
                    i + 1, lua_typename(L, lua_type(L, index)));
            }
            break;

#define CHECK_CASE(TYPE_ENUM, FIELD, LUA_CHECK_FUNC)                           \
    case TYPE_ENUM:                                                            \
        CHECK_RVAL2LVAL(arg_values[i], args[i].FIELD, LUA_CHECK_FUNC);         \
        break

            CHECK_CASE(T_CHAR, c, luaL_checkinteger);
            CHECK_CASE(T_SCHAR, sc, luaL_checkinteger);
            CHECK_CASE(T_UCHAR, uc, luaL_checkinteger);
            CHECK_CASE(T_SHORT, s, luaL_checkinteger);
            CHECK_CASE(T_USHORT, us, luaL_checkinteger);
            CHECK_CASE(T_INT8, i8, luaL_checkinteger);
            CHECK_CASE(T_UINT8, u8, luaL_checkinteger);
            CHECK_CASE(T_INT16, i16, luaL_checkinteger);
            CHECK_CASE(T_UINT16, u16, luaL_checkinteger);
            CHECK_CASE(T_INT, i, luaL_checkinteger);
            CHECK_CASE(T_UINT, ui, luaL_checkinteger);
            CHECK_CASE(T_INT32, i32, luaL_checkinteger);
            CHECK_CASE(T_UINT32, u32, luaL_checkinteger);
            CHECK_CASE(T_INT64, i64, luaL_checkinteger);
            CHECK_CASE(T_UINT64, u64, luaL_checkinteger);
            CHECK_CASE(T_LONG, l, luaL_checkinteger);
            CHECK_CASE(T_ULONG, ul, luaL_checkinteger);
            CHECK_CASE(T_LONG_LONG, ll, luaL_checkinteger);
            CHECK_CASE(T_ULONG_LONG, ull, luaL_checkinteger);
            CHECK_CASE(T_FLOAT, f, luaL_checknumber);
            CHECK_CASE(T_DOUBLE, d, luaL_checknumber);
            CHECK_CASE(T_SIZE_T, sz, luaL_checkinteger);
            CHECK_CASE(T_SSIZE_T, ssz, luaL_checkinteger);

#undef CHECK_CASE
#undef CHECK_RVAL2LVAL
        }
    }

    // call symbol function
    ffi_call(&sym->cif, FFI_FN(sym->addr), ret_value, arg_values);

    // push return value
    switch (sym->ret_type) {
    default:
        return luaL_error(L, "unsupported return type for symbol '%s'",
                          sym->name);

    case T_VOID:
        return 0;

    case T_VOID_PTR:
        (retval.p) ? lua_pushlightuserdata(L, retval.p) : lua_pushnil(L);
        return 1;

    case T_CHAR_PTR:
        (retval.p) ? lua_pushstring(L, retval.p) : lua_pushnil(L);
        return 1;

#define PUSH_CASE(TYPE_ENUM, PUSHFN, FIELD)                                    \
    case TYPE_ENUM:                                                            \
        PUSHFN(L, retval.FIELD);                                               \
        return 1

        PUSH_CASE(T_CHAR, lua_pushinteger, c);
        PUSH_CASE(T_SCHAR, lua_pushinteger, sc);
        PUSH_CASE(T_UCHAR, lua_pushinteger, uc);
        PUSH_CASE(T_SHORT, lua_pushinteger, s);
        PUSH_CASE(T_USHORT, lua_pushinteger, us);
        PUSH_CASE(T_INT8, lua_pushinteger, i8);
        PUSH_CASE(T_UINT8, lua_pushinteger, u8);
        PUSH_CASE(T_INT16, lua_pushinteger, i16);
        PUSH_CASE(T_UINT16, lua_pushinteger, u16);
        PUSH_CASE(T_INT, lua_pushinteger, i);
        PUSH_CASE(T_UINT, lua_pushinteger, ui);
        PUSH_CASE(T_INT32, lua_pushinteger, i32);
        PUSH_CASE(T_UINT32, lua_pushinteger, u32);
        PUSH_CASE(T_INT64, lua_pushinteger, i64);
        PUSH_CASE(T_UINT64, lua_pushinteger, u64);
        PUSH_CASE(T_LONG, lua_pushinteger, l);
        PUSH_CASE(T_ULONG, lua_pushinteger, ul);
        PUSH_CASE(T_LONG_LONG, lua_pushinteger, ll);
        PUSH_CASE(T_ULONG_LONG, lua_pushinteger, ull);
        PUSH_CASE(T_FLOAT, lua_pushnumber, f);
        PUSH_CASE(T_DOUBLE, lua_pushnumber, d);
        PUSH_CASE(T_SIZE_T, lua_pushinteger, sz);
        PUSH_CASE(T_SSIZE_T, lua_pushinteger, ssz);

#undef PUSH_CASE
    }
}

static int dlsym_lua(lua_State *L)
{
    int nargs         = lua_gettop(L) - 1;
    dso_t *dso        = (dso_t *)luaL_checkudata(L, 1, MODULE_MT);
    size_t len        = 0;
    const char *name  = NULL;
    syminfo_t *sym    = lua_newuserdata(L, sizeof(syminfo_t));
    ffi_status status = FFI_OK;

    // number of arguments must be FFI_MAX_ARGS + 2
    // +2 for including return-type and function-name
    if (nargs < 2 || nargs > FFI_MAX_ARGS + 2) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "number of arguments at least 2 and at most %d",
                        FFI_MAX_ARGS + 2);
        return 2;
    }

    // check return-type
    sym->ret_type = check_ffitype(L, 2, &sym->ret_ffi_type);
    // check function-name
    name          = luaL_checklstring(L, 3, &len);
    // check arguments
    sym->nargs    = nargs - 2; // exclude return type and function name
    for (size_t i = 0; i < sym->nargs; i++) {
        sym->arg_types[i] = check_ffitype(L, 4 + i, &sym->arg_ffi_types[i]);
        if (sym->arg_types[i] == T_VOID) {
            lua_pushboolean(L, 0);
            lua_pushfstring(L, "void cannot be used as argument type");
            return 2;
        }
    }

    // copy symbol name
    sym->len = len;
    if (!(sym->name = strdup(name))) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "failed to allocate memory for symbol name");
        return 2;
    }

    // find symbol address
    if (!(sym->addr = dlsym(dso->handle, name))) {
        free(sym->name);
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "failed to find symbol '%s': %s", name, dlerror());
        return 2;
    }

    // prepare FFI call interface
    status = ffi_prep_cif(&sym->cif, FFI_DEFAULT_ABI, sym->nargs,
                          sym->ret_ffi_type, sym->arg_ffi_types);
    if (status != FFI_OK) {
        free(sym->name);
        lua_pushboolean(L, 0);
        lua_pushfstring(
            L, "failed to prepare FFI call interface for symbol '%s' (%s)",
            name, ffi_status_message(status));
        return 2;
    }

    // keep reference to syminfo
    sym->ref  = luaL_ref(L, LUA_REGISTRYINDEX);
    // append to symbol list
    sym->next = NULL;
    if (!dso->symbols_head) {
        dso->symbols_head = sym;
        dso->symbols_tail = sym;
    } else {
        dso->symbols_tail->next = sym;
        dso->symbols_tail       = sym;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int dso_close(lua_State *L, dso_t *dso)
{
    void *handle   = dso->handle;
    syminfo_t *sym = dso->symbols_head;

    if (handle) {
        // free path
        free(dso->path);
        dso->path = NULL;

        // free symbol entry
        while (sym) {
            syminfo_t *next = sym->next;
            free(sym->name);
            luaL_unref(L, LUA_REGISTRYINDEX, sym->ref);
            sym->ref  = LUA_NOREF;
            sym->next = NULL;
            sym       = next;
        }

        // close module
        dso->handle = NULL;
        return dlclose(handle);
    }
    return 0;
}

static int dlclose_lua(lua_State *L)
{
    dso_t *dso = (dso_t *)luaL_checkudata(L, 1, MODULE_MT);

    if (dso_close(L, dso) == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }
    // dlclose failed
    lua_pushboolean(L, 0);
    lua_pushfstring(L, "failed to close module: %s", dlerror());
    return 2;
}

static int index_lua(lua_State *L)
{
    dso_t *dso         = (dso_t *)luaL_checkudata(L, 1, MODULE_MT);
    size_t len         = 0;
    const char *method = luaL_checklstring(L, 2, &len);

    // check if module is closed
    if (!dso->handle) {
        return luaL_error(L, "module is closed");
    }

    // dispatch method
    if (strncmp(method, "dlsym", len) == 0) {
        lua_pushcfunction(L, dlsym_lua);
        return 1;
    } else if (strncmp(method, "dlclose", len) == 0) {
        lua_pushcfunction(L, dlclose_lua);
        return 1;
    }

    // traverse symbols
    for (syminfo_t *sym = dso->symbols_head; sym; sym = sym->next) {
        if (len == sym->len && strncmp(method, sym->name, len) == 0) {
            // found symbol
            lua_rawgeti(L, LUA_REGISTRYINDEX, sym->ref);
            lua_pushcclosure(L, symcall_lua, 1);
            return 1;
        }
    }

    // unknown method
    return luaL_error(L, "attempt to index invalid unknown field '%s'",
                      lua_tostring(L, 2));
}

static int gc_lua(lua_State *L)
{
    dso_t *dso = (dso_t *)luaL_checkudata(L, 1, MODULE_MT);
    dso_close(L, dso);
    return 0;
}

static int tostring_lua(lua_State *L)
{
    dso_t *dso = (dso_t *)lua_touserdata(L, 1);
    lua_pushfstring(L, "%s: %p (%s)", MODULE_MT, dso->handle, dso->path);
    return 1;
}

static int new_lua(lua_State *L)
{
    size_t len       = 0;
    const char *path = luaL_checklstring(L, 1, &len);
    dso_t *dso       = NULL;

    // clear stack except path
    lua_settop(L, 1);

    // open module
    dso               = (dso_t *)lua_newuserdata(L, sizeof(dso_t));
    // initialize fields
    dso->symbols_head = NULL;
    dso->symbols_tail = NULL;
    // duplicate path string
    if (!(dso->path = strdup(path))) {
        lua_pushnil(L);
        lua_pushfstring(L, "failed to allocate memory for path");
        return 2;
    }
    // open shared library
    if (!(dso->handle = dlopen(path, RTLD_NOW | RTLD_LOCAL))) {
        // dlopen failed
        free(dso->path);
        lua_pushnil(L);
        lua_pushfstring(L, "failed to open module '%s': %s", path, dlerror());
        return 2;
    }

    // set metatable
    luaL_getmetatable(L, MODULE_MT);
    lua_setmetatable(L, -2);
    return 1;
}

LUALIB_API int luaopen_dlopen(lua_State *L)
{
    // create metatable
    if (luaL_newmetatable(L, MODULE_MT)) {
        struct luaL_Reg mmethod[] = {
            {"__gc",       gc_lua      },
            {"__tostring", tostring_lua},
            {"__index",    index_lua   },
            {NULL,         NULL        }
        };

        // metamethods
        for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
            lua_pushcfunction(L, ptr->func);
            lua_setfield(L, -2, ptr->name);
        }
        // Protect metatable from external access
        lua_pushliteral(L, "metatable is protected");
        lua_setfield(L, -2, "__metatable");

        lua_pop(L, 1);
    }

    lua_pushcfunction(L, new_lua);
    return 1;
}
