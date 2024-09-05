//! This module exposes x86_64-specific functions.

const std = @import("std");
const log = std.log.scoped(.arch);

pub const gdt = @import("gdt.zig");
pub const intr = @import("interrupt.zig");
pub const page = @import("page.zig");
pub const pic = @import("pic.zig");
pub const serial = @import("serial.zig");
pub const apic = @import("apic.zig");

const cpuid = @import("cpuid.zig");
const am = @import("asm.zig");

/// Pause a CPU for a short period of time.
pub fn relax() void {
    am.relax();
}

/// Disable interrupts.
/// Note that exceptions and NMI are not ignored.
pub inline fn disableIntr() void {
    am.cli();
}

/// Enable interrupts.
pub inline fn enableIntr() void {
    am.sti();
}

/// Halt the current CPU.
pub inline fn halt() void {
    am.hlt();
}

/// Pause the CPU for a wait loop.
pub inline fn pause() void {
    asm volatile ("pause");
}

/// Port I/O In instruction.
pub inline fn in(T: type, port: u16) T {
    return switch (T) {
        u8 => am.inb(port),
        u16 => am.inw(port),
        u32 => am.inl(port),
        else => @compileError("Unsupported type for asm in()"),
    };
}

/// Enable CPUID instruction.
pub inline fn enableCpuid() void {
    var eflags = am.readEflags();
    if (!eflags.id) {
        eflags.id = true;
        _ = am.writeEflags(eflags);
    }
}

pub fn getCpuVendorId() [12]u8 {
    var ret: [12]u8 = undefined;
    const regs = am.cpuid(cpuid.functions.vendor_id);

    for (0..4) |i| {
        const b: usize = (regs.ebx >> @truncate(i * 8));
        ret[0 + i] = @as(u8, @truncate(b));
    }
    for (0..4) |i| {
        const b: usize = (regs.edx >> @truncate(i * 8));
        ret[4 + i] = @as(u8, @truncate(b));
    }
    for (0..4) |i| {
        const b: usize = (regs.ecx >> @truncate(i * 8));
        ret[8 + i] = @as(u8, @truncate(b));
    }
    return ret;
}

/// Get the feature information from CPUID.
pub fn getFeatureInformation() cpuid.CpuidInformation {
    const eflags = am.readEflags();
    if (!eflags.id) @panic("CPUID is not enabled");

    const regs = am.cpuid(cpuid.functions.feature_information);
    return cpuid.CpuidInformation{
        .ecx = @bitCast(regs.ecx),
        .edx = @bitCast(regs.edx),
    };
}

/// Enable supported XSAVE features.
pub fn enableXstateFeature() void {
    // Enable XSAVE in CR4, which is necessary to access XCR0.
    var cr4 = am.readCr4();
    cr4.osxsave = true;
    am.loadCr4(cr4);

    // Enable supported XSAVE features.
    const ext_info = am.cpuidEcx(0xD, 0); // Processor extended state enumeration
    const max_features = ((@as(u64, ext_info.edx) & 0xFFFF_FFFF) << 32) + ext_info.eax;
    am.xsetbv(0, max_features); // XCR0 enabled mask
}

test {
    const testing = @import("std").testing;
    testing.refAllDeclsRecursive(@This());
}
