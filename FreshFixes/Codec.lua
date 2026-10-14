local _, FF = ...

-- !FF:<KIND>:<SCHEMA>!<base64(zlib(json))> — see FORMATS.md.
-- Everything is built into the client (C_EncodingUtil); no libraries.
local E = C_EncodingUtil
local ZLIB = Enum.CompressionMethod and Enum.CompressionMethod.Zlib

function FF.Encode(kind, schema, data)
    local json = E.SerializeJSON(data)
    local packed = E.CompressString(json, ZLIB)
    return ("!FF:%s:%d!%s"):format(kind, schema, E.EncodeBase64(packed))
end

-- Returns data, kind, schema  or  nil, errorMessage.
function FF.Decode(text, expectKind)
    if type(text) ~= "string" then
        return nil, "Nothing to import"
    end
    text = text:gsub("%s", "")
    local kind, schema, body = text:match("^!FF:(%u+):(%d+)!(.+)$")
    if not kind then
        return nil, "Not a Fresh Fixes string"
    end
    if expectKind and kind ~= expectKind then
        return nil, ("Expected a %s string, got %s"):format(expectKind, kind)
    end
    local ok, data = pcall(function()
        return E.DeserializeJSON(E.DecompressString(E.DecodeBase64(body), ZLIB))
    end)
    if not ok or type(data) ~= "table" then
        return nil, "String is corrupt or incomplete"
    end
    return data, kind, tonumber(schema)
end
