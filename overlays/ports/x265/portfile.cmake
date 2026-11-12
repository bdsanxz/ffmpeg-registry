vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO Multicorewareinc/x265
    REF "${VERSION}"
    SHA512 270d0db180ecebfc5c2f1fe6451be66042fab69273d073428f4af00420fa0f8b792ecdc71ec1a15ee2860e3b6a325c56295143f117e94fa3616f0ccecb2ded75
    HEAD_REF master
    PATCHES
        disable-install-pdb.patch
        version.patch
        linkage.diff
        pkgconfig.diff
        pthread.diff
        compiler-target.diff
        neon.diff
        advapi32.patch
)

vcpkg_check_features(OUT_FEATURE_OPTIONS OPTIONS
    FEATURES
        tool   ENABLE_CLI
)

if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86" OR VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
    vcpkg_find_acquire_program(NASM)
    list(APPEND OPTIONS "-DNASM_EXECUTABLE=${NASM}")
    if(VCPKG_LIBRARY_LINKAGE STREQUAL "static" AND NOT VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_OSX)
        list(APPEND OPTIONS "-DENABLE_ASSEMBLY=OFF")
    endif()
elseif(VCPKG_TARGET_IS_WINDOWS)
    list(APPEND OPTIONS "-DENABLE_ASSEMBLY=OFF")
endif()

# For static linkage we build the canonical 8+10+12 multilib so that
# FFmpeg's libx265 wrapper reports 10-bit (and 12-bit) pixel formats.
# Dynamic linkage keeps the upstream single-build behaviour.
if(NOT VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    string(COMPARE EQUAL "${VCPKG_LIBRARY_LINKAGE}" "dynamic" ENABLE_SHARED)
    vcpkg_cmake_configure(
        SOURCE_PATH "${SOURCE_PATH}/source"
        OPTIONS
            ${OPTIONS}
            -DENABLE_SHARED=${ENABLE_SHARED}
            -DENABLE_PIC=ON
            -DENABLE_LIBNUMA=OFF
            -DCMAKE_DISABLE_FIND_PACKAGE_VLD=ON
            "-DVERSION=${VERSION}"
        OPTIONS_DEBUG
            -DENABLE_CLI=OFF
        MAYBE_UNUSED_VARIABLES
            ENABLE_LIBNUMA
    )
    vcpkg_cmake_install()
    vcpkg_copy_pdbs()
    vcpkg_fixup_pkgconfig()
    if("tool" IN_LIST FEATURES)
        vcpkg_copy_tools(TOOL_NAMES x265 AUTO_CLEAN)
    endif()
    if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/x265.h" "#ifdef X265_API_IMPORTS" "#if 1")
    endif()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
    vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
    return()
endif()

# ---------- multilib static build ----------

set(X265_TEMP_DIR "${CURRENT_BUILDTREES_DIR}/x265-multilib")
file(MAKE_DIRECTORY "${X265_TEMP_DIR}")

# Discover the installed static library path after vcpkg_cmake_install().
# Returns via variable name in PARENT_SCOPE.
function(x265_find_installed_lib out_var)
    # Windows MSVC uses x265-static.lib, Unix uses libx265.a
    set(_candidates
        "${CURRENT_PACKAGES_DIR}/lib/x265-static.lib"
        "${CURRENT_PACKAGES_DIR}/lib/libx265.a"
        "${CURRENT_PACKAGES_DIR}/lib/x265.lib"
        "${CURRENT_PACKAGES_DIR}/lib/libx265-static.a"
    )
    foreach(_p IN LISTS _candidates)
        if(EXISTS "${_p}")
            set(${out_var} "${_p}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    # Fallback: glob
    file(GLOB _glob_lib "${CURRENT_PACKAGES_DIR}/lib/*x265*.a" "${CURRENT_PACKAGES_DIR}/lib/*x265*.lib")
    if(_glob_lib)
        list(GET _glob_lib 0 _first)
        set(${out_var} "${_first}" PARENT_SCOPE)
        return()
    endif()
    message(FATAL_ERROR "Could not locate built x265 static library under ${CURRENT_PACKAGES_DIR}/lib")
endfunction()

# Common options shared by all three bit-depth builds
set(X265_COMMON_OPTS
    ${OPTIONS}
    -DENABLE_PIC=ON
    -DENABLE_LIBNUMA=OFF
    -DCMAKE_DISABLE_FIND_PACKAGE_VLD=ON
    "-DVERSION=${VERSION}"
    -DENABLE_SHARED=OFF
)

# 12-bit (Main12) - no C API, no CLI, high bit depth
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/source"
    OPTIONS ${X265_COMMON_OPTS}
        -DHIGH_BIT_DEPTH=ON
        -DMAIN12=ON
        -DEXPORT_C_API=OFF
        -DENABLE_CLI=OFF
    OPTIONS_DEBUG
        -DENABLE_CLI=OFF
    MAYBE_UNUSED_VARIABLES
        ENABLE_LIBNUMA
        CMAKE_DISABLE_FIND_PACKAGE_VLD
    LOGNAME configure-12bit
)
vcpkg_cmake_build()
vcpkg_cmake_install()
x265_find_installed_lib(X265_LIB_12)
# Save copy
if(VCPKG_TARGET_IS_WINDOWS)
    set(X265_DEST_12 "x265-static-main12.lib")
else()
    set(X265_DEST_12 "libx265_main12.a")
endif()
vcpkg_execute_required_process(COMMAND "${CMAKE_COMMAND}" -E copy "${X265_LIB_12}" "${X265_TEMP_DIR}/${X265_DEST_12}" WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}" LOGNAME copy-12bit)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}")

# 10-bit (Main10)
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/source"
    OPTIONS ${X265_COMMON_OPTS}
        -DHIGH_BIT_DEPTH=ON
        -DEXPORT_C_API=OFF
        -DENABLE_CLI=OFF
    OPTIONS_DEBUG
        -DENABLE_CLI=OFF
    MAYBE_UNUSED_VARIABLES
        ENABLE_LIBNUMA
        CMAKE_DISABLE_FIND_PACKAGE_VLD
    LOGNAME configure-10bit
)
vcpkg_cmake_build()
vcpkg_cmake_install()
x265_find_installed_lib(X265_LIB_10)
if(VCPKG_TARGET_IS_WINDOWS)
    set(X265_DEST_10 "x265-static-main10.lib")
else()
    set(X265_DEST_10 "libx265_main10.a")
endif()
vcpkg_execute_required_process(COMMAND "${CMAKE_COMMAND}" -E copy "${X265_LIB_10}" "${X265_TEMP_DIR}/${X265_DEST_10}" WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}" LOGNAME copy-10bit)
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}")

# 8-bit (Main) - links the other two, provides CLI when requested
if("tool" IN_LIST FEATURES)
    set(X265_CLI_8BIT ON)
else()
    set(X265_CLI_8BIT OFF)
endif()

# Prepare EXTRA_LIB argument: points at the previously built 10/12-bit libs
if(VCPKG_TARGET_IS_WINDOWS)
    set(X265_EXTRA_LIB_PATH "${X265_TEMP_DIR}/${X265_DEST_10};${X265_TEMP_DIR}/${X265_DEST_12}")
else()
    set(X265_EXTRA_LIB_PATH "${X265_TEMP_DIR}/${X265_DEST_10};${X265_TEMP_DIR}/${X265_DEST_12}")
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/source"
    OPTIONS ${X265_COMMON_OPTS}
        -DEXPORT_C_API=ON
        -DENABLE_CLI=${X265_CLI_8BIT}
        "-DEXTRA_LIB=${X265_EXTRA_LIB_PATH}"
        -DLINKED_10BIT=ON
        -DLINKED_12BIT=ON
    OPTIONS_DEBUG
        -DENABLE_CLI=OFF
    MAYBE_UNUSED_VARIABLES
        ENABLE_LIBNUMA
        CMAKE_DISABLE_FIND_PACKAGE_VLD
    LOGNAME configure-8bit
)
vcpkg_cmake_build()
vcpkg_cmake_install()
x265_find_installed_lib(X265_LIB_8)
if(VCPKG_TARGET_IS_WINDOWS)
    set(X265_DEST_8 "x265-static-main.lib")
else()
    set(X265_DEST_8 "libx265_main.a")
endif()
# Save the 8-bit library before merging
set(X265_MAIN_LIB_PATH "${X265_TEMP_DIR}/${X265_DEST_8}")
vcpkg_execute_required_process(COMMAND "${CMAKE_COMMAND}" -E copy "${X265_LIB_8}" "${X265_MAIN_LIB_PATH}" WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}" LOGNAME copy-8bit)

# Merge the three static archives into the final installed library.
# The installed 8-bit lib is currently at ${X265_LIB_8}; we replace it with the merged result.
if(VCPKG_TARGET_IS_WINDOWS)
    # Windows: use lib.exe
    find_program(LIB_EXE NAMES lib lib.exe HINTS "$ENV{VSINST}Common7/Tools" "$ENV{ProgramFiles}/Microsoft Visual Studio" NO_CACHE)
    if(NOT LIB_EXE)
        # Fallback: rely on PATH
        set(LIB_EXE "lib")
    endif()
    vcpkg_execute_required_process(
        COMMAND "${LIB_EXE}" /NOLOGO "/OUT:${X265_LIB_8}"
            "${X265_MAIN_LIB_PATH}" "${X265_TEMP_DIR}/${X265_DEST_10}" "${X265_TEMP_DIR}/${X265_DEST_12}"
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
        LOGNAME merge-x265
    )
else()
    set(X265_MERGED "${CURRENT_PACKAGES_DIR}/lib/libx265.a")
    if(VCPKG_TARGET_IS_OSX)
        find_program(LIBTOOL_EXE NAMES libtool REQUIRED)
        vcpkg_execute_required_process(
            COMMAND "${LIBTOOL_EXE}" -static -o "${X265_MERGED}"
                "${X265_MAIN_LIB_PATH}" "${X265_TEMP_DIR}/${X265_DEST_10}" "${X265_TEMP_DIR}/${X265_DEST_12}"
            WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
            LOGNAME merge-x265
        )
    else()
        # Linux / Android (GNU ar). Use single "ar rcs" + ranlib to merge.
        find_program(AR_EXE NAMES ar llvm-ar REQUIRED)
        find_program(RANLIB_EXE NAMES ranlib llvm-ranlib REQUIRED)
        file(REMOVE "${X265_MERGED}")
        vcpkg_execute_required_process(
            COMMAND "${AR_EXE}" rcs "${X265_MERGED}" "${X265_MAIN_LIB_PATH}" "${X265_TEMP_DIR}/${X265_DEST_10}" "${X265_TEMP_DIR}/${X265_DEST_12}"
            WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
            LOGNAME merge-x265
        )
        vcpkg_execute_required_process(
            COMMAND "${RANLIB_EXE}" "${X265_MERGED}"
            WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
            LOGNAME merge-x265-ranlib
        )
    endif()
    # Ensure the final path matches the originally installed lib name
    if(NOT X265_LIB_8 STREQUAL X265_MERGED)
        # Some toolchains install as libx265.a only; keep both consistent
        vcpkg_execute_required_process(COMMAND "${CMAKE_COMMAND}" -E copy "${X265_MERGED}" "${X265_LIB_8}" WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}" LOGNAME copy-merged)
    endif()
endif()

vcpkg_copy_pdbs()
vcpkg_fixup_pkgconfig()

if("tool" IN_LIST FEATURES)
    vcpkg_copy_tools(TOOL_NAMES x265 AUTO_CLEAN)
endif()

if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/x265.h" "#ifdef X265_API_IMPORTS" "#if 1")
endif()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYING")
