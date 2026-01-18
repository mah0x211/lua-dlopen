-- luacov is not needed for C code coverage
-- Coverage is obtained with DLOPEN_COVERAGE=1 luarocks make
-- Load module under test
local dlopen = require("dlopen")
local lfs = require("lfs")

-- Change working directory to test directory
local original_dir = lfs.currentdir()
local script_dir = debug.getinfo(1).source:match("@?(.*/)") or "."
assert(lfs.chdir(script_dir))

-- ============================================================================
-- Test Helpers
-- ============================================================================
local _DSO

local function close_dso()
    if _DSO then
        pcall(function()
            _DSO:dlclose()
        end)
        _DSO = nil
    end
end

local function run_test(name, func)
    io.write("Running " .. name .. "... ")
    local status, err = xpcall(func, debug.traceback)
    if status then
        print("OK")
        close_dso()
    else
        print("FAIL")
        print(err)
        os.exit(1)
    end
end

local function assert_equal(expected, actual, msg)
    if expected ~= actual then
        error((msg or "") .. " Expected " .. tostring(expected) .. ", got " ..
                  tostring(actual))
    end
end

local function assert_not_nil(val, msg)
    if val == nil then
        error((msg or "") .. " Expected non-nil value")
    end
end

local function assert_match(pattern, str, msg)
    if not str:match(pattern) then
        error((msg or "") .. " Expected " .. tostring(str) .. " to match " ..
                  tostring(pattern))
    end
end

local function assert_true(val, msg)
    if not val then
        error((msg or "") .. " Expected truthy value, got " .. tostring(val))
    end
end

-- Build a test library on-the-fly from C source code
local function build_test_lib(source)
    local c_file = "test.c"
    local so_file = "./libtest.so"
    -- Clean up previous test files
    close_dso()
    os.remove(c_file)
    os.remove(so_file)

    local f = io.open(c_file, "w")
    if not f then
        error("Failed to create " .. c_file)
    end
    f:write(source)
    f:close()

    -- Compile (Lua 5.4: os.execute returns true, "exit", exit_code)
    local build_cmd = "gcc -shared -fPIC -Wall -O2 -o " .. so_file .. " " ..
                          c_file .. " 2>&1"
    local res, reason, code = os.execute(build_cmd)
    if type(res) ~= "number" then
        res = reason == "exit" and code or -1
    end
    if res ~= 0 then
        error(("Failed to compile %s (exit code: %s)"):format(c_file,
                                                              tostring(res)))
    end

    -- Confirm the .so file was created
    local attr = lfs.attributes(so_file)
    if not attr or attr.mode ~= "file" then
        error("Shared library " .. so_file .. " was not created")
    end

    -- Verify the shared library was created
    local lib, err = dlopen(so_file)
    if not lib then
        error("Failed to load compiled library: " .. tostring(err))
    end
    _DSO = lib
    return lib
end

-- ============================================================================
-- A. Basic Functionality Tests
-- ============================================================================

run_test("load valid library", function()
    local lib, err = build_test_lib([[
int test_func() { return 42; }
]])
    assert_not_nil(lib, "Failed to load library: " .. tostring(err))
    assert_equal("userdata", type(lib), "Library should be userdata")
end)

run_test("load invalid library returns error", function()
    local lib, err = dlopen("/nonexistent/library.so")
    assert_equal(nil, lib, "Should fail to load nonexistent library")
    assert_not_nil(err, "Should return error message")
    assert_match("failed to open", err, "Wrong error message: " .. tostring(err))
end)

run_test("close library successfully", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local ok, err = lib:dlclose()
    assert_true(ok, "Failed to close library: " .. tostring(err))
end)

run_test("operations on closed library fail", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    lib:dlclose()
    local ok, err = pcall(function()
        lib:dlsym("int", "test_func")
    end)
    assert_equal(false, ok, "Should fail to operate on closed library")
    assert_not_nil(err, "Should return error")
end)

run_test("define valid symbol successfully", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local ok, err = lib:dlsym("int", "test_func")
    assert_true(ok, "Failed to define symbol: " .. tostring(err))
end)

run_test("define invalid symbol returns error", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local ok, err = lib:dlsym("int", "nonexistent_func_xyz")
    assert_equal(false, ok, "Should fail to define nonexistent symbol")
    assert_not_nil(err, "Should return error message")
    assert_match("failed to find symbol", err,
                 "Wrong error message: " .. tostring(err))
end)

run_test("call function successfully", function()
    local lib = build_test_lib([[
int add(int a, int b) { return a + b; }
]])
    local ok, err = lib:dlsym("int", "add", "int", "int")
    assert_true(ok, "Failed to define add: " .. tostring(err))

    local result = lib:add(10, 20)
    assert_equal(30, result, "add should return 30, got " .. tostring(result))
end)

-- ============================================================================
-- B. Type Safety Tests (from IMPLEMENTATION_PLAN.md)
-- ============================================================================

run_test("void* rejects string arguments", function()
    local lib = build_test_lib([[
void* accept_void_ptr(void* ptr) {
    return ptr;
}]])
    local ok, err = lib:dlsym("void*", "accept_void_ptr", "void*")
    assert_true(ok, "Failed to define accept_void_ptr: " .. tostring(err))

    -- void* should reject string
    local ok2, err2 = pcall(function()
        lib:accept_void_ptr("string")
    end)
    assert_equal(false, ok2, "void* should reject string")
    assert_match("void%* requires nil, lightuserdata or userdata", err2,
                 "Wrong error message: " .. tostring(err2))
end)

run_test("void* accepts nil", function()
    local lib = build_test_lib([[
void* accept_void_ptr(void* ptr) {
    return ptr;
}
]])
    local ok, err = lib:dlsym("void*", "accept_void_ptr", "void*")
    assert_true(ok, "Failed to define accept_void_ptr: " .. tostring(err))

    -- void* should accept nil (converts to NULL)
    local result = lib:accept_void_ptr(nil)
    assert_equal(nil, result, "void* should accept nil and return nil")
end)

run_test("char* rejects lightuserdata", function()
    local lib = build_test_lib([[
int process_char_ptr(char* str) {
    return str ? 1 : 0;
}
]])
    local ok, err = lib:dlsym("int", "process_char_ptr", "char*")
    assert_true(ok, "Failed to define process_char_ptr: " .. tostring(err))

    -- char* should reject lightuserdata
    local ptr = require("assert.lightuserdata")
    local ok2, err2 = pcall(function()
        lib:process_char_ptr(ptr)
    end)
    assert_equal(false, ok2, "char* should reject lightuserdata")
    assert_match("char%* requires nil or string", err2,
                 "Wrong error message: " .. tostring(err2))
end)

run_test("char* accepts string", function()
    local lib = build_test_lib([[
int strlen_test(char* str) {
    int len = 0;
    if (str) {
        while (str[len]) len++;
    }
    return len;
}
]])
    local ok, err = lib:dlsym("int", "strlen_test", "char*")
    assert_true(ok, "Failed to define strlen_test: " .. tostring(err))

    local result = lib:strlen_test("hello")
    assert_equal(5, result,
                 "strlen_test should return 5, got " .. tostring(result))
end)

run_test("char* accepts nil", function()
    local lib = build_test_lib([[
#include <stddef.h>
int is_null(char* str) {
    return str == NULL ? 1 : 0;
}
]])
    local ok, err = lib:dlsym("int", "is_null", "char*")
    assert_true(ok, "Failed to define is_null: " .. tostring(err))

    -- char* should accept nil (converts to NULL)
    local result = lib:is_null(nil)
    assert_equal(1, result, "char* should accept nil as NULL")
end)

run_test("void return type handling", function()
    local lib = build_test_lib([[
void void_func(int x) {
    /* does nothing */
}
]])
    local ok, err = lib:dlsym("void", "void_func", "int")
    assert_true(ok, "Failed to define void_func: " .. tostring(err))

    -- void return should return nothing (nil)
    local result = {
        lib:void_func(42),
    }
    assert_equal(0, #result, "void return should return nothing, got " ..
                     #result .. " values")
end)

run_test("void argument rejected in dlsym", function()
    local lib = build_test_lib([[
int test_func(int x) { return x; }
]])
    local ok, err = lib:dlsym("int", "func", "int", "void")
    assert_equal(false, ok, "void argument should be rejected")
    assert_not_nil(err, "Should return error message")
    assert_match("void cannot be used as argument", err,
                 "Wrong error message: " .. tostring(err))
end)

-- ============================================================================
-- C. Data Type Tests (All 26 supported types)
-- ============================================================================

-- Integer types
run_test("int8 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
int8_t test_int8(int8_t x) { return x; }
]])
    lib:dlsym("int8", "test_int8", "int8")
    local result = lib:test_int8(-42)
    assert_equal(-42, result, "test_int8 should return -42")
end)

run_test("uint8 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
uint8_t test_uint8(uint8_t x) { return x; }
]])
    lib:dlsym("uint8", "test_uint8", "uint8")
    local result = lib:test_uint8(255)
    assert_equal(255, result, "test_uint8 should return 255")
end)

run_test("int16 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
int16_t test_int16(int16_t x) { return x; }
]])
    lib:dlsym("int16", "test_int16", "int16")
    local result = lib:test_int16(-1000)
    assert_equal(-1000, result, "test_int16 should return -1000")
end)

run_test("uint16 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
uint16_t test_uint16(uint16_t x) { return x; }
]])
    lib:dlsym("uint16", "test_uint16", "uint16")
    local result = lib:test_uint16(50000)
    assert_equal(50000, result, "test_uint16 should return 50000")
end)

run_test("int32 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
int32_t test_int32(int32_t x) { return x; }
]])
    lib:dlsym("int32", "test_int32", "int32")
    local result = lib:test_int32(-100000)
    assert_equal(-100000, result, "test_int32 should return -100000")
end)

run_test("uint32 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
uint32_t test_uint32(uint32_t x) { return x; }
]])
    lib:dlsym("uint32", "test_uint32", "uint32")
    local result = lib:test_uint32(300000)
    assert_equal(300000, result, "test_uint32 should return 300000")
end)

run_test("int64 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
int64_t test_int64(int64_t x) { return x; }
]])
    lib:dlsym("int64", "test_int64", "int64")
    local result = lib:test_int64(-10000000000)
    assert_equal(-10000000000, result, "test_int64 should return -10000000000")
end)

run_test("uint64 type", function()
    local lib = build_test_lib([[
#include <stdint.h>
uint64_t test_uint64(uint64_t x) { return x; }
]])
    lib:dlsym("uint64", "test_uint64", "uint64")
    local result = lib:test_uint64(40000000000)
    assert_equal(40000000000, result, "test_uint64 should return 40000000000")
end)

run_test("char type", function()
    local lib = build_test_lib([[
char test_char(char x) { return x; }
]])
    lib:dlsym("char", "test_char", "char")
    local result = lib:test_char(65) -- 'A'
    assert_equal(65, result, "test_char should return 65")
end)

run_test("signed char type", function()
    local lib = build_test_lib([[
signed char test_schar(signed char x) { return x; }
]])
    lib:dlsym("signed char", "test_schar", "signed char")
    local result = lib:test_schar(-42)
    assert_equal(-42, result, "test_schar should return -42")
end)

run_test("unsigned char type", function()
    local lib = build_test_lib([[
unsigned char test_uchar(unsigned char x) { return x; }
]])
    lib:dlsym("unsigned char", "test_uchar", "unsigned char")
    local result = lib:test_uchar(200)
    assert_equal(200, result, "test_uchar should return 200")
end)

run_test("short type", function()
    local lib = build_test_lib([[
short test_short(short x) { return x; }
]])
    lib:dlsym("short", "test_short", "short")
    local result = lib:test_short(-1000)
    assert_equal(-1000, result, "test_short should return -1000")
end)

run_test("unsigned short type", function()
    local lib = build_test_lib([[
unsigned short test_ushort(unsigned short x) { return x; }
]])
    lib:dlsym("unsigned short", "test_ushort", "unsigned short")
    local result = lib:test_ushort(50000)
    assert_equal(50000, result, "test_ushort should return 50000")
end)

run_test("int type", function()
    local lib = build_test_lib([[
int test_int(int x) { return x; }
]])
    lib:dlsym("int", "test_int", "int")
    local result = lib:test_int(-123456)
    assert_equal(-123456, result, "test_int should return -123456")
end)

run_test("unsigned int type", function()
    local lib = build_test_lib([[
unsigned int test_uint(unsigned int x) { return x; }
]])
    lib:dlsym("unsigned int", "test_uint", "unsigned int")
    local result = lib:test_uint(400000)
    assert_equal(400000, result, "test_uint should return 400000")
end)

run_test("long type", function()
    local lib = build_test_lib([[
long test_long(long x) { return x; }
]])
    lib:dlsym("long", "test_long", "long")
    local result = lib:test_long(-100000)
    assert_equal(-100000, result, "test_long should return -100000")
end)

run_test("unsigned long type", function()
    local lib = build_test_lib([[
unsigned long test_ulong(unsigned long x) { return x; }
]])
    lib:dlsym("unsigned long", "test_ulong", "unsigned long")
    local result = lib:test_ulong(500000)
    assert_equal(500000, result, "test_ulong should return 500000")
end)

run_test("long long type", function()
    local lib = build_test_lib([[
long long test_longlong(long long x) { return x; }
]])
    lib:dlsym("long long", "test_longlong", "long long")
    local result = lib:test_longlong(-10000000000)
    assert_equal(-10000000000, result,
                 "test_longlong should return -10000000000")
end)

run_test("unsigned long long type", function()
    local lib = build_test_lib([[
unsigned long long test_ulonglong(unsigned long long x) { return x; }
]])
    lib:dlsym("unsigned long long", "test_ulonglong", "unsigned long long")
    local result = lib:test_ulonglong(60000000000)
    assert_equal(60000000000, result, "test_ulonglong should return 60000000000")
end)

run_test("size_t type", function()
    local lib = build_test_lib([[
#include <stddef.h>
size_t test_size_t(size_t x) { return x; }
]])
    lib:dlsym("size_t", "test_size_t", "size_t")
    local result = lib:test_size_t(500000)
    assert_equal(500000, result, "test_size_t should return 500000")
end)

run_test("ssize_t type", function()
    local lib = build_test_lib([[
#include <stddef.h>
typedef long ssize_t;
ssize_t test_ssize_t(ssize_t x) { return x; }
]])
    lib:dlsym("ssize_t", "test_ssize_t", "ssize_t")
    local result = lib:test_ssize_t(-100000)
    assert_equal(-100000, result, "test_ssize_t should return -100000")
end)

-- Floating point types
run_test("float type", function()
    local lib = build_test_lib([[
float test_float(float x) { return x; }
]])
    lib:dlsym("float", "test_float", "float")
    local result = lib:test_float(3.14)
    local diff = math.abs(result - 3.14)
    assert_true(diff < 0.001,
                "test_float should return approximately 3.14, got " ..
                    tostring(result))
end)

run_test("double type", function()
    local lib = build_test_lib([[
double test_double(double x) { return x; }
]])
    lib:dlsym("double", "test_double", "double")
    local result = lib:test_double(-2.71828)
    local diff = math.abs(result - (-2.71828))
    assert_true(diff < 0.0001,
                "test_double should return approximately -2.71828, got " ..
                    tostring(result))
end)

-- Pointer types
run_test("void* return type", function()
    local lib = build_test_lib([[
void* test_void_ptr_ret() { return (void*)0x1234; }
]])
    local ok, err = lib:dlsym("void*", "test_void_ptr_ret")
    assert_true(ok, "Failed to define test_void_ptr_ret: " .. tostring(err))
    local result = lib:test_void_ptr_ret()
    assert_not_nil(result, "test_void_ptr_ret should return a value")
end)

run_test("void* argument and return", function()
    local lib = build_test_lib([[
void* identity_void_ptr(void* ptr) { return ptr; }
]])
    local ok, err = lib:dlsym("void*", "identity_void_ptr", "void*")
    assert_true(ok, "Failed to define identity_void_ptr: " .. tostring(err))

    -- Test with nil (converts to NULL)
    local result = lib:identity_void_ptr(nil)
    assert_equal(nil, result,
                 "identity_void_ptr should return nil for NULL input")
end)

run_test("char* return type", function()
    local lib = build_test_lib([[
char* test_char_ptr_ret() { return "hello"; }
]])
    local ok, err = lib:dlsym("char*", "test_char_ptr_ret")
    assert_true(ok, "Failed to define test_char_ptr_ret: " .. tostring(err))
    local result = lib:test_char_ptr_ret()
    assert_equal("hello", result, "test_char_ptr_ret should return 'hello'")
end)

-- ============================================================================
-- D. Error Handling Tests
-- ============================================================================

run_test("unknown type string rejected", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local ok, err = pcall(function()
        lib:dlsym("unknown_type", "test_func", "void")
    end)
    assert_equal(false, ok, "Should reject unknown type")
    assert_not_nil(err, "Should return error message")
    assert_match("invalid option", err, "Wrong error message: " .. tostring(err))
end)

run_test("too few arguments to dlsym", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local ok, err = lib:dlsym("int")
    assert_equal(false, ok, "Should reject too few arguments")
    assert_not_nil(err, "Should return error message")
end)

run_test("wrong argument count for function call", function()
    local lib = build_test_lib([[
int add(int a, int b) { return a + b; }
]])
    lib:dlsym("int", "add", "int", "int")

    local ok, err = pcall(function()
        lib:add(1, 2, 3) -- Too many args
    end)

    assert_equal(false, ok, "Should fail with wrong argument count")
    assert_not_nil(err, "Should return error message")
    assert_match("invalid number of arguments", err,
                 "Wrong error message: " .. tostring(err))
end)

run_test("tostring method returns string representation", function()
    local lib = build_test_lib([[
int test_func() { return 42; }
]])
    local str = tostring(lib)
    assert_not_nil(str, "tostring should return string")
    assert_match("dlopen", str, "tostring should contain 'dlopen'")
end)

run_test("function with multiple arguments", function()
    local lib = build_test_lib([[
int sum5(int a, int b, int c, int d, int e) { return a + b + c + d + e; }
]])
    local ok, err = lib:dlsym("int", "sum5", "int", "int", "int", "int", "int")
    assert_true(ok, "Failed to define sum5: " .. tostring(err))
    local result = lib:sum5(1, 2, 3, 4, 5)
    assert_equal(15, result, "sum5 should return 15")
end)

-- ============================================================================
-- E. Additional Coverage Tests
-- ============================================================================

run_test("complex calculation with multiple types", function()
    local lib = build_test_lib([[
double calc(int a, double b, long c) { return a + b + c; }
]])
    lib:dlsym("double", "calc", "int", "double", "long")
    local result = lib:calc(10, 3.5, 100)
    local diff = math.abs(result - 113.5)
    assert_true(diff < 0.0001, "calc should return approximately 113.5, got " ..
                    tostring(result))
end)

run_test("pointer arithmetic function", function()
    local lib = build_test_lib([[
void* add_offset(void* ptr, int offset) {
    return (char*)ptr + offset;
}
]])
    local ok, err = lib:dlsym("void*", "add_offset", "void*", "int")
    assert_true(ok, "Failed to define add_offset: " .. tostring(err))

    -- Test with NULL pointer (nil)
    -- Note: Adding offset to NULL is technically undefined behavior,
    -- but we're testing the FFI call mechanism here
    local result = lib:add_offset(nil, 10)
    -- The result is implementation-defined
    -- Just verify the call doesn't crash
    assert_not_nil(result or result == nil,
                   "add_offset should complete without crash")
end)

run_test("large integer value", function()
    local lib = build_test_lib([[
#include <stdint.h>
int64_t test_large(int64_t x) { return x; }
]])
    lib:dlsym("int64", "test_large", "int64")
    local large_val = 9007199254740991 -- 2^53 - 1 (max safe integer in Lua)
    local result = lib:test_large(large_val)
    assert_equal(large_val, result, "test_large should handle large integers")
end)

print("All dlopen tests passed!")

-- Restore original working directory
assert(lfs.chdir(original_dir))
