const std = @import("std");

pub const Production = struct {
    allocator: *std.mem.Allocator,
    id: usize,
    symbols: [][]const u8,

    pub fn init(allocator: *std.mem.Allocator, id: usize, symbols: [][]const u8) Production {
        return Production{
            .allocator = allocator,
            .id = id,
            .symbols = symbols,
        };
    }

    pub fn deinit(self: *Production) void {
        self.allocator.free(self.symbols);
    }
};

pub const Rule = struct {
    allocator: *std.mem.Allocator,
    name: []const u8,
    productions: []Production,

    pub fn init(allocator: *std.mem.Allocator, name: []const u8, productions: []Production) Rule {
        return Rule{
            .allocator = allocator,
            .name = name,
            .productions = productions,
        };
    }

    pub fn deinit(self: *Rule) void {
        self.allocator.free(self.productions);
    }
};

pub const RuleSet = struct {
    const RuleMap = std.HashMap([]const u8, Rule, std.mem.hash_slice_u8, std.mem.eql_slice_u8);

    const ErrorSet = error {
        RuleDoesNotExist,
    };

    start_symbol: []const u8,
    map: RuleMap,

    pub fn init(allocator: *std.mem.Allocator) RuleSet {
        return RuleSet{
            .start_symbol = "",
            .map = RuleMap.init(allocator),
        };
    }

    pub fn deinit(self: *RuleSet) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value.deinit();
        }
        self.map.deinit();
    }

    pub fn put(self: *RuleSet, rule: Rule) !void {
        if (self.map.contains(rule.name)) {
            return;
        }
        if (self.start_symbol.len == 0) {
            self.start_symbol = rule.name;
        }
        const old_entry = try self.map.put(rule.name, rule);
        std.debug.assert(old_entry == null);
    }

    pub fn get(self: *const RuleSet, name: []const u8) !Rule {
        var rule_entry = self.map.get(name);
        if (rule_entry == null) {
            return RuleSet.ErrorSet.RuleDoesNotExist;
        }
        return rule_entry.?.value;
    }
};
