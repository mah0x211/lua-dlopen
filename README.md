# lua-dlopen

Call C functions in shared libraries using libffi for Lua.

This module allows you to load shared libraries (`.so`, `.dylib`, `.dll`) into your Lua scripts, look up functions within those libraries, and call them as if they were native Lua functions. It handles the conversion of data types between Lua and C.


## Installation

You need to have `libffi` installed on your system.

```bash
# On Debian/Ubuntu
sudo apt-get install libffi-dev

# On RedHat/CentOS
sudo yum install libffi-devel

# On macOS (using Homebrew)
brew install libffi
```

Then, you can install `lua-dlopen` using LuaRocks:

```bash
luarocks install dlopen
```

## Usage

```lua
local dlopen = require('dlopen')

-- load libc
local libc, err = dlopen('libc.so.6')
if not libc then
    error(err)
end

-- define function signature of `puts`
-- int puts(const char *s);
local ok, err = libc:dlsym('int', 'puts', 'char*')
if not ok then
    error(err)
end

-- call `puts`
libc:puts('hello world')

-- define function signature of `strlen`
-- size_t strlen(const char *s);
ok, err = libc:dlsym('size_t', 'strlen', 'char*')
if not ok then
    error(err)
end

-- call `strlen`
local len = libc:strlen('hello world')
print(len)

-- close library
ok, err = libc:dlclose()
if not ok then
    error(err)
end
```

## dso, err = dlopen(path)

Loads a shared library from the given `path`.

**Parameters:**

- `path:string`: The path to the shared library file.

**Returns:**

- `dso:dlopen`: An instance of the `dlopen`, or `nil` on failure.
- `err:string`: An error message if loading fails.

**Example:**

```lua
local lib, err = dlopen('libc.so.6')
if not lib then
    error(err)
end
```

## ok, err = dlopen:dlclose()

Closes the shared library and unloads it from memory. All defined symbols from this library will no longer be available.

**Returns:**

- `ok:boolean`: `true` on success, `false` on failure.
- `err:string`: An error message if closing fails.

**Example:**

```lua
local ok, err = lib:dlclose()
if not ok then
    error(err)
end
```


## ok, err = dlopen:dlsym(return_type, function_name, ...)

Loads a symbol (function) from the shared library and defines its signature.

**Parameters:**

- `return_type:string`: The return type of the C function. See [Supported Data Types](#supported-data-types).
- `function_name:string`: The name of the function to look up.
- `...:string`: A variable number of strings representing the argument types of the C function. See [Supported Data Types](#supported-data-types).

**Returns:**

- `ok:boolean`: `true` on success, `false` on failure.
- `err:string`: An error message if the symbol lookup or definition fails.

**Example:**

```lua
-- define strlen: size_t strlen(const char *s);
local ok, err = lib:dlsym('size_t', 'strlen', 'char*')
if not ok then
    error(err)
end
```

### retval = dlopen:<function_name>(...)

Calls a previously defined C function.

**Parameters:**

- `...`: The arguments to pass to the C function. These must match the types defined with `dlsym`.

**Returns:**

- `retval:any`: The return value from the C function, converted to a corresponding Lua type.

**Example:**

```lua
local len = lib:strlen('hello')
print(len)  -- 5
```

## Supported Data Types

The following string identifiers can be used for `return_type` and `arg_types` in `dlopen:dlsym`.

**Note:** For pointer types, `nil` is converted to `NULL` when passed as arguments, and `NULL` return values are converted to `nil`.

| Type String | C Type | Lua Type |
| --- | --- | --- |
| `void` | `void` | N/A (not allowed) |
| `void*` | `void*` | `nil`, `lightuserdata`, `userdata` |
| `char*` | `char*` | `nil` or `string` |
| `char` | `char` | `number` (integer) |
| `signed char` | `signed char` | `number` (integer) |
| `unsigned char` | `unsigned char` | `number` (integer) |
| `short` | `short` | `number` (integer) |
| `unsigned short` | `unsigned short` | `number` (integer) |
| `int` | `int` | `number` (integer) |
| `unsigned int` | `unsigned int` | `number` (integer) |
| `int8` | `int8_t` | `number` (integer) |
| `uint8` | `uint8_t` | `number` (integer) |
| `int16` | `int16_t` | `number` (integer) |
| `uint16` | `uint16_t` | `number` (integer) |
| `int32` | `int32_t` | `number` (integer) |
| `uint32` | `uint32_t` | `number` (integer) |
| `int64` | `int64_t` | `number` (integer) |
| `uint64` | `uint64_t` | `number` (integer) |
| `long` | `long` | `number` (integer) |
| `unsigned long` | `unsigned long` | `number` (integer) |
| `long long` | `long long` | `number` (integer) |
| `unsigned long long` | `unsigned long long` | `number` (integer) |
| `float` | `float` | `number` |
| `double` | `double` | `number` |
| `size_t` | `size_t` | `number` (integer) |
| `ssize_t` | `ssize_t` | `number` (integer) |



## TODO

### **Test Suite**: Add comprehensive test coverage

- Unit tests for each supported data type
- Integration tests with real C libraries
- Error handling tests (invalid types, missing symbols, etc.)
- Platform-specific tests (Linux, macOS)
- Automated testing on multiple platforms

### **Array Support**: Implement passing arrays to C functions

- Currently not supported; arrays require special handling in libffi
- Design: `dlopen:dlsym(return_type, function_name, type[], length)` or similar syntax

### **Pointer-to-Pointer Types**: Support `void**` and `char**` types

- Functions like `strtol` require pointer-to-pointer arguments (`char **endptr`)
- Current limitation: using `void*` for `char**` causes type mismatch and undefined behavior
- Design: Add `void**` and `char**` type strings to properly handle output parameters
- Example: `lib:dlsym('long', 'strtol', 'char*', 'char**', 'int')`

  
## Under Consideration

The following features are being considered but not yet committed to implementation:

### **Struct Support**: Support passing and receiving C structures

- Design: `dlopen:defstruct(name, fields)`
- Field syntax: `'field_name@type'` (e.g., `'x@int'`, `'str@char*'`)
- Extended syntax:
    - Arrays: `'arr@int#10'` → `int arr[10];`
    - Bit-fields: `'flag@uint:1'` → `unsigned int flag:1;`
    - Function pointers: `'callback@int(int,int)'` → `int (*callback)(int, int);`
    - Multi-level pointers: `'pptr@char**'` → `char** pptr;` (requires type system extension)
    - Const: `'cstr@const char*'` → `const char* cstr;` (requires type system extension)
- Predefined function pointer types:
    ```lua
    -- Define function pointer type
    dlopen:defcallback(return_type, type_name, ...arg_types)

    -- Examples
    dlopen:defcallback('int', 'IntCallback', 'int', 'int')
    dlopen:defcallback('void*', 'MallocFunc', 'size_t')
    dlopen:defcallback('int', 'CompareFunc', 'const void*', 'const void*')

    -- Use in struct definition
    dlopen:defstruct('MyData', {
        'x@int',
        'callback@IntCallback',  -- use predefined type
        'malloc@MallocFunc',
        'compare@CompareFunc'
    })
    ```
    ```c
    typedef int (*IntCallback)(int, int);
    typedef void* (*MallocFunc)(size_t);
    typedef int (*CompareFunc)(const void*, const void*);

    struct MyData {
        int x;
        IntCallback callback;
        MallocFunc malloc;
        CompareFunc compare;
    };
    ```
- Anonymous structs/unions (supports nesting):
    ```lua
    dlopen:defstruct('MyData', {
        'x@int',
        'struct',    -- anonymous struct without field name
        {
            'str@char*',
            'len@size_t'
        },
        'union@value',      -- anonymous union with field name
        {
            'i@int',
            'f@float'
        },
        'field@PredefType'  -- use predefined struct type
    })
    ```
    ```c
    struct MyData {
        int x;
        struct {
            char* str;
            size_t len;
        };
        union {
            int i;
            float f;
        } value;
        PredefType field;
    };
    ```
    ```lua
    -- Nested anonymous structs/unions are supported
    dlopen:defstruct('NestedData', {
        'x@int',
        'struct',
        {
            'str@char*',
            'nested@struct',  -- nested anonymous struct
            {
                'foo@int',
                'bar@int'
            }
        }
    })
    ```
    ```c
    struct NestedData {
        int x;
        struct {
            char* str;
            struct {
                int foo;
                int bar;
            } nested;
        };
    };
    ```
- Data mapping: Lua table ↔ C struct
- Complexity: High - requires ABI alignment handling and type conversion

### **Function Pointers**: Support callbacks (C → Lua function calls)

- Allow passing Lua functions as C callbacks
- Complexity: High - requires managing callback lifetime and cleanup

### **Variadic Functions**: Support for variadic C functions (e.g., `printf`)

- libffi requires special handling for `...`
- Complexity: Medium - could use separate API like `dlopen:dlsym_variadic()`


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
