local history = {};

function history.copy(value)
    if (type(value) ~= 'table') then return value; end
    local result = {};
    for key, inner in pairs(value) do result[key] = history.copy(inner); end
    return result;
end

function history.replace(target, source)
    for key in pairs(target) do target[key] = nil; end
    for key, value in pairs(source) do target[key] = history.copy(value); end
end

function history.equal(a, b)
    if (type(a) ~= type(b)) then return false; end
    if (type(a) ~= 'table') then return a == b; end
    for key, value in pairs(a) do if (not history.equal(value, b[key])) then return false; end end
    for key in pairs(b) do if (a[key] == nil) then return false; end end
    return true;
end

function history.layout_equal(a, b)
    for key, value in pairs(a) do
        if (key ~= 'window' and key ~= 'preview' and key ~= 'account' and not history.equal(value, b[key])) then return false; end
    end
    for key in pairs(b) do
        if (key ~= 'window' and key ~= 'preview' and key ~= 'account' and a[key] == nil) then return false; end
    end
    return true;
end

function history.new()
    local self = { entries = {} };
    function self:push(before)
        self.entries[#self.entries + 1] = history.copy(before);
        if (#self.entries > 8) then table.remove(self.entries, 1); end
    end
    function self:undo(target)
        local previous = table.remove(self.entries);
        if (previous == nil) then return false; end
        local window, preview, account = target.window, target.preview, target.account;
        history.replace(target, previous);
        target.window, target.preview, target.account = window, preview, account;
        return true;
    end
    function self:clear() self.entries = {}; end
    return self;
end

return history;
