//! Ymir: The hypervisor.
//!

const std = @import("std");
const log = std.log.scoped(.main);
const surtr = @import("surtr");

const ymir = @import("ymir");
const kbd = @import("keyboard.zig");
const idefs = @import("interrupts.zig");
const serial = ymir.serial;
const klog = ymir.klog;
const arch = ymir.arch;

pub const panic = @import("panic.zig").panic_fn;
pub const std_options = klog.default_log_options;

/// Size in 4KiB pages of the kernel stack.
const kstack_size = arch.page_size * 0x50;
/// Kernel stack.
/// The first page is used as a guard page.
/// TODO: make the guard page read-only.
var kstack: [kstack_size + arch.page_size]u8 align(arch.page_size) = [_]u8{0} ** (kstack_size + arch.page_size);

/// Kernel entry point called by surtr.
/// The function switches stack from the surtr stack to the kernel stack.
export fn kernelEntry() callconv(.Naked) noreturn {
    asm volatile (
        \\movq %[new_stack], %%rsp
        \\call kernelTrampoline
        :
        : [new_stack] "r" (@intFromPtr(&kstack) + kstack_size + arch.page_size),
    );
}

/// Trampoline function to call the kernel main function.
/// The role of this function is to make main function return errors.
export fn kernelTrampoline(boot_info: surtr.BootInfo) callconv(.Win64) noreturn {
    kernelMain(boot_info) catch |err| {
        log.err("Kernel aborted with error: {}", .{err});
        @panic("Exiting...");
    };

    unreachable;
}

/// Kernel main function.
fn kernelMain(boot_info: surtr.BootInfo) !void {
    // Initialize the serial console and logger.
    const sr = serial.init();
    klog.init(sr);
    log.info("Booting Ymir...", .{});

    // Validate the boot info.
    validateBootInfo(boot_info) catch |err| {
        log.err("Invalid boot info: {}", .{err});
        return error.InvalidBootInfo;
    };

    // Initialize GDT.
    // It switches GDT from the one prepared by surtr to the ymir GDT.
    arch.gdt.init();
    log.info("Initialized GDT.", .{});

    // Initialize IDT.
    // From this moment, interrupts are enabled.
    arch.intr.init();
    log.info("Initialized IDT.", .{});

    // Initialize PIC.
    arch.pic.init();
    log.info("Initialized PIC.", .{});

    // Enable PIT.
    arch.pic.unsetMask(.Timer);
    arch.intr.registerHandler(idefs.pic_timer, blobTimerHandler);
    log.info("Enabled PIT.", .{});

    // Init keyboard.
    kbd.init(.{ .serial = sr }); // TODO: make this configurable
    log.info("Initialized keyboard.", .{});

    // EOL
    log.info("Reached EOL.", .{});
    while (true)
        arch.halt();
}

fn validateBootInfo(boot_info: surtr.BootInfo) !void {
    if (boot_info.magic != surtr.surtr_magic) {
        return error.InvalidMagic;
    }
}

// TODO: temporary
fn blobTimerHandler(_: *arch.intr.Context) void {
    arch.pic.notifyEoi(.Timer);
}
