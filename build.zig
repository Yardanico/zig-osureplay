const Builder = @import("std").build.Builder;
const builtin = @import("builtin");

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("osureader", "src/osureader.zig");
    const t = b.addTest("src/osureplay.zig");
   
    t.setBuildMode(mode);
    exe.setBuildMode(mode);
    
    if (mode == builtin.Mode.ReleaseSmall) {
        // Remove debug symbols in release-small
        exe.strip = true;
    }
    // We need the C library because we use easylzma which depends on libc
    t.linkSystemLibrary("c");
    exe.linkSystemLibrary("c");

    const c_includes = [_][]const u8{
        "src/vendor/easylzma",
        "src/vendor/easylzma/easylzma",
        "src/vendor/easylzma/pavlov"
    };

    const c_files = [_][]const u8{
        "src/vendor/easylzma/lzma_header.c",
        "src/vendor/easylzma/compress.c",
        "src/vendor/easylzma/decompress.c",
        "src/vendor/easylzma/common_internal.c",
        "src/vendor/easylzma/pavlov/7zCrc.c",
        "src/vendor/easylzma/pavlov/Alloc.c",
        "src/vendor/easylzma/pavlov/LzFind.c",
        "src/vendor/easylzma/pavlov/LzmaLib.c",
        "src/vendor/easylzma/pavlov/LzmaEnc.c",
        "src/vendor/easylzma/pavlov/LzmaDec.c",
        "src/vendor/easylzma/easylzma/simple.c",
    };

    for (c_includes) |c_include| {
        exe.addIncludeDir(c_include);
        t.addIncludeDir(c_include);
    }

    for (c_files) |c_file| {
        exe.addCSourceFile(c_file, [_][]const u8{});
        t.addCSourceFile(c_file, [_][]const u8{});
    }

    const run_cmd = exe.run();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&t.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
