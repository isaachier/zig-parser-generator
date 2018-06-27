const std = @import("std");

pub const Production = struct {
    allocator: *std.mem.Allocator,
    id: usize,
    name: []const u8,
    symbols: [][]const u8,

    /// Initialize a production.
    /// allocator - Allocator used to free symbols slice upon deinit.
    /// id - Unique ID of this production.
    /// name - Pointer to name of rule (string held not owned).
    /// symbols - Symbols of production. Production takes ownership of slice from caller.
    pub fn init(
        allocator: *std.mem.Allocator,
        id: usize,
        name: []const u8,
        symbols: [][]const u8,
    ) Production {
        return Production{
            .allocator = allocator,
            .id = id,
            .name = name,
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
    prods: []Production,

    /// Initialize a rule.
    /// name - Name of rule. Rule takes ownership of slice from caller.
    pub fn init(allocator: *std.mem.Allocator, name: []const u8, prods: []Production) Rule {
        std.debug.assert(name.len > 0);
        return Rule{
            .allocator = allocator,
            .name = name,
            .prods = prods,
        };
    }

    pub fn deinit(self: *Rule) void {
        if (self.name.len > 0) {
            self.allocator.free(self.name);
        }
        self.allocator.free(self.prods);
    }

    fn resetName(self: *Rule) void {
        self.name = "";
    }
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub const RuleSet = struct {
    const RuleMap = std.HashMap([]const u8, Range, std.mem.hash_slice_u8, std.mem.eql_slice_u8);
    const ProdList = std.ArrayList(Production);

    const ErrorSet = error{RuleDoesNotExist};

    start_symbol: []const u8,
    rule_map: RuleMap,
    prod_list: ProdList,

    pub fn init(allocator: *std.mem.Allocator) RuleSet {
        return RuleSet{
            .start_symbol = "",
            .rule_map = RuleMap.init(allocator),
            .prod_list = ProdList.init(allocator),
        };
    }

    pub fn deinit(self: *RuleSet) void {
        var rule_it = self.rule_map.iterator();
        while (rule_it.next()) |entry| {
            self.rule_map.allocator.free(entry.key);
        }
        self.rule_map.deinit();

        // start_symbol is not freed because it is just a pointer to an existing rule map entry key,
        // which were all freed above.

        for (self.prod_list.toSlice()) |_, i| {
            self.prod_list.at(i).deinit();
        }
        self.prod_list.deinit();
    }

    pub fn put(self: *RuleSet, rule: *Rule) !void {
        if (self.rule_map.contains(rule.name)) {
            return;
        }
        const range = Range{ .start = self.prod_list.len, .end = self.prod_list.len + rule.prods.len };
        try self.prod_list.appendSlice(rule.prods);
        const old_entry = try self.rule_map.put(rule.name, range);
        std.debug.assert(old_entry == null);
        if (self.start_symbol.len == 0) {
            self.start_symbol = rule.name;
        }
        rule.resetName();
    }

    pub fn get(self: *const RuleSet, name: []const u8) ![]const Production {
        var rule_entry = self.rule_map.get(name);
        if (rule_entry == null) {
            return RuleSet.ErrorSet.RuleDoesNotExist;
        }
        const range = rule_entry.?.value;
        return self.prod_list.toSliceConst()[range.start..range.end];
    }
};
