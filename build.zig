const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.option(bool, "tests", "Build tests [default: false]") orelse false;

    const boost = boostLibraries(b, .{
        .target = target,
        .header_only = .no,
    });
    const lib = b.addStaticLibrary(.{
        .name = "beast",
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(b.path("include"));
    for (boost.root_module.include_dirs.items) |include| {
        lib.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    // zig-pkg bypass for header-only
    lib.addCSourceFile(.{
        .file = b.path("test/empty.cc"),
        .flags = cxxFlags,
    });
    lib.linkLibrary(boost);

    if (lib.rootModuleTarget().abi == .msvc)
        lib.linkLibC()
    else
        lib.linkLibCpp();
    lib.installHeadersDirectory(b.path("include"), "", .{});
    lib.step.dependOn(&boost.step);
    b.installArtifact(lib);

    if (tests) {
        // clients
        buildTest(b, .{
            .path = "example/http/client/async/http_client_async.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/client/sync/http_client_sync.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/client/awaitable/http_client_awaitable.cpp",
            .lib = lib,
        });
        if (lib.rootModuleTarget().abi != .msvc) buildTest(b, .{
            .path = "example/http/client/body/json_client.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/client/methods/http_client_methods.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/client/crawl/http_crawl.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/client/async/websocket_client_async.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/client/sync/websocket_client_sync.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/client/awaitable/websocket_client_awaitable.cpp",
            .lib = lib,
        });
        // servers
        buildTest(b, .{
            .path = "example/http/server/async/http_server_async.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/server/sync/http_server_sync.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/server/awaitable/http_server_awaitable.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/server/small/http_server_small.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/server/fast/http_server_fast.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/http/server/stackless/http_server_stackless.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/advanced/server/advanced_server.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/echo-op/echo_op.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/server/async/websocket_server_async.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/server/sync/websocket_server_sync.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/server/stackless/websocket_server_stackless.cpp",
            .lib = lib,
        });
        buildTest(b, .{
            .path = "example/websocket/server/awaitable/websocket_server_awaitable.cpp",
            .lib = lib,
        });
    }
}

const cxxFlags: []const []const u8 = &.{
    "-Wall",
    "-Wextra",
    "-Wpedantic",
    "-std=c++20",
    "-fexperimental-library",
};

fn buildTest(b: *std.Build, info: BuildInfo) void {
    const test_exe = b.addExecutable(.{
        .name = info.filename(),
        .optimize = info.lib.root_module.optimize.?,
        .target = info.lib.root_module.resolved_target.?,
    });
    for (info.lib.root_module.include_dirs.items) |include| {
        test_exe.root_module.include_dirs.append(b.allocator, include) catch {};
    }
    test_exe.step.dependOn(&info.lib.step);
    test_exe.addIncludePath(.{ .cwd_relative = "test" });
    test_exe.addIncludePath(.{ .cwd_relative = "." });
    test_exe.addCSourceFile(.{ .file = .{ .cwd_relative = info.path }, .flags = cxxFlags });
    if (std.mem.endsWith(u8, info.filename(), "crawl")) {
        test_exe.addCSourceFile(.{
            .file = b.path("example/http/client/crawl/urls_large_data.cpp"),
            .flags = cxxFlags,
        });
    }
    if (test_exe.rootModuleTarget().os.tag == .windows) {
        test_exe.want_lto = false;
        test_exe.linkSystemLibrary2("ws2_32", .{ .use_pkg_config = .no });
        test_exe.linkSystemLibrary2("mswsock", .{ .use_pkg_config = .no });
    }
    if (test_exe.rootModuleTarget().abi == .msvc)
        test_exe.linkLibC()
    else
        test_exe.linkLibCpp();
    b.installArtifact(test_exe);

    const run_cmd = b.addRunArtifact(test_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(
        b.fmt("{s}", .{info.filename()}),
        b.fmt("Run the {s} test", .{info.filename()}),
    );
    run_step.dependOn(&run_cmd.step);
}

const BuildInfo = struct {
    lib: *std.Build.Step.Compile,
    path: []const u8,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.splitSequence(u8, std.fs.path.basename(self.path), ".");
        return split.first();
    }
};

fn boostLibraries(b: *std.Build, config: Config) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "boost",
        .target = config.target,
        .optimize = .ReleaseFast, // no compiler-rt
    });

    const boostCore = b.dependency("core", .{}).path("");
    const boostAlg = b.dependency("algorithm", .{}).path("");
    const boostConfig = b.dependency("config", .{}).path("");
    const boostAssert = b.dependency("assert", .{}).path("");
    const boostTraits = b.dependency("type_traits", .{}).path("");
    const boostMP11 = b.dependency("mp11", .{}).path("");
    const boostRange = b.dependency("range", .{}).path("");
    const boostFunctional = b.dependency("functional", .{}).path("");
    const boostPreprocessor = b.dependency("preprocessor", .{}).path("");
    const boostHash = b.dependency("container_hash", .{}).path("");
    const boostDescribe = b.dependency("describe", .{}).path("");
    const boostMpl = b.dependency("mpl", .{}).path("");
    const boostIterator = b.dependency("iterator", .{}).path("");
    const boostStaticAssert = b.dependency("static_assert", .{}).path("");
    const boostMove = b.dependency("move", .{}).path("");
    const boostDetail = b.dependency("detail", .{}).path("");
    const boostThrow = b.dependency("throw_exception", .{}).path("");
    const boostTuple = b.dependency("tuple", .{}).path("");
    const boostPredef = b.dependency("predef", .{}).path("");
    const boostCCheck = b.dependency("concept_check", .{}).path("");
    const boostUtil = b.dependency("utility", .{}).path("");
    const boostEndian = b.dependency("endian", .{}).path("");
    const boostRegex = b.dependency("regex", .{}).path("");
    const boostAsio = b.dependency("asio", .{}).path("");
    const boostAlign = b.dependency("align", .{}).path("");
    const boostSystem = b.dependency("system", .{}).path("");
    const boostIntrusive = b.dependency("intrusive", .{}).path("");
    const boostHana = b.dependency("hana", .{}).path("");
    const boostOutcome = b.dependency("outcome", .{}).path("");
    const boostBind = b.dependency("bind", .{}).path("");
    const boostOptional = b.dependency("optional", .{}).path("");
    const boostDateTime = b.dependency("date_time", .{}).path("");
    const boostSmartPtr = b.dependency("smart_ptr", .{}).path("");
    const boostNumeric = b.dependency("numeric_conversion", .{}).path("");
    const boostLogic = b.dependency("logic", .{}).path("");
    const boostStaticStr = b.dependency("static_string", .{}).path("");
    const boostIO = b.dependency("io", .{}).path("");
    const boostJson = b.dependency("json", .{}).path("");
    const boostContainer = b.dependency("container", .{}).path("");
    const boostVariant2 = b.dependency("variant2", .{}).path("");
    const boostWinApi = b.dependency("winapi", .{}).path("");
    if (config.header_only == .yes)
        // zig-pkg bypass (no header-only)
        lib.addCSourceFile(.{ .file = b.path("test/empty.cc"), .flags = cxxFlags })
    else {
        lib.addCSourceFiles(.{
            .root = boostContainer,
            .files = &.{
                "src/pool_resource.cpp",
                "src/monotonic_buffer_resource.cpp",
                "src/synchronized_pool_resource.cpp",
                "src/unsynchronized_pool_resource.cpp",
                "src/global_resource.cpp",
            },
            .flags = cxxFlags,
        });
        lib.addCSourceFiles(.{
            .root = boostJson,
            .files = &.{
                "src/src.cpp",
            },
            .flags = cxxFlags,
        });
        if (lib.rootModuleTarget().abi == .msvc)
            lib.linkLibC()
        else
            lib.linkLibCpp();
    }
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostCore.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostAlg.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostConfig.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostAssert.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostFunctional.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostMP11.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostTraits.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostRange.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostPreprocessor.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostHash.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostDescribe.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostMpl.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostStaticAssert.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostIterator.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostMove.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostDetail.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostThrow.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostTuple.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostPredef.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostCCheck.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostUtil.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostRegex.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostEndian.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostAsio.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostAlign.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostSystem.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostIntrusive.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostHana.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostOutcome.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostBind.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostOptional.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostDateTime.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostSmartPtr.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostNumeric.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostLogic.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostStaticStr.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostIO.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostJson.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostContainer.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostVariant2.getPath(b), "include" }) });
    lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ boostWinApi.getPath(b), "include" }) });
    return lib;
}

pub const Config = struct {
    header_only: enum {
        yes,
        no,
    },
    target: std.Build.ResolvedTarget,
};
