const std = @import("std");
const builtin = @import("builtin");
const kf = @import("known-folders");

const is_debug = builtin.mode == .Debug;

const usage_text =
    \\usage: {s} executable.exe\n
;

const help_text =
    \\Use proton-ge as a drop-in replacement for wine.
    \\
    \\Uses /usr/share/steam/compatibilitytools.d/proton-ge-custom/proton as a the executable.
    \\
    \\This is meant as an alternative to the runner script from proton-ge's aur pachage.
    \\The only difference is that the default mode is run.
    \\The rest is default.
    \\
    \\  -h --help        Print this help message.
;

const proton_path = "/usr/share/steam/compatibilitytools.d/proton-ge-custom/proton";

pub fn main() !void {
    if (std.os.argv.len < 2) {
        std.debug.print(usage_text, .{std.os.argv[0]});
        return error.InsufficientArguments;
    }

    if (std.mem.eql(u8, std.mem.sliceTo(std.os.argv[1], 0), "-h")) {
        std.debug.print("{s}\n\n", .{usage_text});
        std.debug.print("{s}\n", .{help_text});
        std.os.exit(0);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const XDG_DATA_HOME = try kf.getPath(alloc, .data);
    defer if (XDG_DATA_HOME) |*p| alloc.free(p.*);
    const XDG_CACHE_HOME = try kf.getPath(alloc, .cache);
    defer if (XDG_CACHE_HOME) |*p| alloc.free(p.*);

    const steam = try std.mem.concat(alloc, u8, &[_][]const u8{
        XDG_DATA_HOME orelse "~/.local/share", "/Steam",
    });
    defer alloc.free(steam);

    const pfx = try std.mem.concat(alloc, u8, &[_][]const u8{
        XDG_DATA_HOME orelse "~/.local/share", "/proton-pfx",
    });
    defer alloc.free(pfx);

    const cachepath = try std.mem.concat(alloc, u8, &[_][]const u8{
        XDG_CACHE_HOME orelse "~/.cache", "/dxvk-cache-pool",
    });
    defer alloc.free(cachepath);

    if (is_debug) {
        std.debug.print("[DEBUG]: Steam path = {s}\n", .{steam});
        std.debug.print("[DEBUG]: pfx path = {s}\n", .{pfx});
        std.debug.print("[DEBUG]: cachepath = {s}\n", .{cachepath});
    }

    var run_argv = try std.ArrayList([:0]u8).initCapacity(alloc, 1);
    defer run_argv.deinit();

    try run_argv.append(@constCast(proton_path));
    try run_argv.append(@constCast("run"));
    for (std.os.argv[1..]) |arg| {
        try run_argv.append(std.mem.sliceTo(arg, 0));
    }

    if (is_debug) {
        std.debug.print("[DEBUG]: argv =\n", .{});
        for (run_argv.items) |arg| {
            std.debug.print("             {s}\n", .{arg});
        }
    }

    // Get current environment variables,
    // use in child processes.
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    // set Default AppId
    const appid_path = try std.mem.concat(alloc, u8, &[_][]const u8{ pfx, "/0" });
    defer alloc.free(appid_path);

    try env_map.put("STEAM_COMPAT_CLIENT_INSTALL_PATH", steam);
    try env_map.put("STEAM_COMPAT_DATA_PATH", appid_path);
    try env_map.put("DXVK_STATE_CACHE_PATH", cachepath);

    if (is_debug) {
        std.debug.print("[DEBUG]: Setting env:\n", .{});
        var iter = env_map.iterator();
        while (iter.next()) |env_key| {
            std.debug.print("             {s}={s}\n", .{ env_key.key_ptr.*, env_key.value_ptr.* });
        }
    }

    var runner = std.ChildProcess.init(run_argv.items, alloc);
    runner.env_map = &env_map;
    _ = try runner.spawnAndWait();
}
