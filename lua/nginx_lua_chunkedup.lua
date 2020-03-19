local lfs = require('lfs')
local posix = require('posix')
local http_utils = require('nginx_upload.http_utils')

local UPSTREAM = ngx.var.upstream
local HEADERS = ngx.req.get_headers()

-- By default use the file name from request path.
local FILENAME = ngx.var.path
if (HEADERS['X-File-Name'] ~= nil)
then
    -- However, if an X-File-Name header is present use that.
    FILENAME = HEADERS['X-File-Name']
end

local gen_boundary = function()
    local t = {}
    for i=1,17 do t[i] = string.char(math.random(97, 122)) end
    return table.concat(t)
end

local boundary = gen_boundary()
local content_type = HEADERS['Content-Type']
local temp = ngx.req.get_body_file()

local fd, ntmp = posix.mkstemp(temp .. '_XXXXXX')
posix.close(fd)
-- Documentation explicitly states not to do this, however, ngx.req.read_body()
-- and 'lua_need_request_body on' both clean up the file even when
-- 'client_body_in_file_only on' which is contrary to nginx documentation. In
-- any case, this is the only way to prevent the file from being cleaned up.
os.rename(temp, ntmp)

local parts = {file={{}}}

parts.file[1]['content_type'] = content_type
parts.file[1]['filename'] = FILENAME
parts.file[1]['filepath'] = ntmp
parts.file[1]['size'] = lfs.attributes(ntmp).size

ngx.req.set_header('Transfer-Encoding', nil)
ngx.req.set_header('Content-Type', 'multipart/form-data; boundary=' .. boundary)

local body = http_utils.form_multipart_body(parts, boundary)
local r = ngx.location.capture(UPSTREAM, {method=ngx.HTTP_POST, body=body})
ngx.status = r.status
ngx.print(r.body)
