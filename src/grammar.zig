const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Buffer = std.Buffer;
const File = std.os.File;

pub const Rule = struct {
    name: Buffer,
    symbols: ArrayList(Buffer),

    pub fn init(allocator: *Allocator, name: []const u8) !Rule {
        return Rule{
            .name = try Buffer.init(allocator, name),
            .symbols = ArrayList(Buffer).init(allocator),
        };
    }

    pub fn append(self: *Rule, symbol: []const u8) !void {
        try self.symbols.append(try Buffer.init(self.symbols.allocator, symbol));
    }
};

pub const RuleSet = struct {
    const RuleMap = HashMap([]const u8, Rule, mem.hash_slice_u8, mem.eql_slice_u8);

    const ErrorSet = error {
        RuleDoesNotExist,
    };

    arena: ArenaAllocator,
    map: RuleMap,

    pub fn init(allocator: *Allocator) RuleSet {
        var arena = ArenaAllocator.init(allocator);
        return RuleSet{
            .arena = arena,
            .map = RuleMap.init(&arena.allocator),
        };
    }

    pub fn deinit(self: *RuleSet) void {
        self.arena.deinit();
    }

    pub fn put(self: *RuleSet, name: []const u8) !*Rule {
        var rule = try Rule.init(&self.arena.allocator, name);
        std.debug.warn("put: {}\n", rule.name.toSliceConst());
        _ = try self.map.put(rule.name.toSliceConst(), rule);
        var entry = ??self.map.get(name);
        return &entry.value;
    }

    pub fn get(self: *RuleSet, name: []const u8) !*Rule {
        var rule_entry = self.map.get(name);
        if (rule_entry == null) {
            return RuleSet.ErrorSet.RuleDoesNotExist;
        }
        return &(??rule_entry).value;
    }
};

test "init" {
    var rule_set = RuleSet.init(std.debug.global_allocator);
    defer rule_set.deinit();

    var rule = try rule_set.put("S");
    try rule.append("a");
    try rule.append("b");
}
