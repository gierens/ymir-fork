//! This module provides a logging to the serial console.

const std = @import("std");
const stdlog = std.log;
const io = std.io;
const option = @import("option");

const ymir = @import("ymir");
const Serial = ymir.serial.Serial;

/// Instance of the initialized serial console.
var serial: Serial = undefined;

/// Skeleton for the error type.
/// Not used but required by std.io.Writer interface.
const LogError = error{};

const Writer = std.io.Writer(
    void,
    LogError,
    write,
);

/// Log options.
/// Can be configured by compile-time options. See build.zig.
pub const default_log_options = std.Options{
    .log_level = switch (option.log_level) {
        .debug => .debug,
        .info => .info,
        .warn => .warn,
        .err => .err,
    },
    .logFn = log,
};

/// Initialize the logger with the given serial console.
/// You MUST call this function before using the logger.
pub fn init(s: Serial) void {
    serial = s;
}

fn write(_: void, bytes: []const u8) LogError!usize {
    serial.writeString(bytes);
    return bytes.len;
}

fn log(
    comptime level: stdlog.Level,
    comptime scope: @Type(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const level_str = comptime switch (level) {
        .debug => "[DEBUG]",
        .info => "[INFO ]",
        .warn => "[WARN ]",
        .err => "[ERROR]",
    };

    const scope_str = if (@tagName(scope).len <= 7) b: {
        break :b std.fmt.comptimePrint("{s: <7} | ", .{@tagName(scope)});
    } else b: {
        break :b std.fmt.comptimePrint("{s: <7}-| ", .{@tagName(scope)[0..7]});
    };

    std.fmt.format(
        Writer{ .context = {} },
        level_str ++ " " ++ scope_str ++ fmt ++ "\n",
        args,
    ) catch {};
}
