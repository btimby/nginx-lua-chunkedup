local lfs = require('lfs')
local posix = require('posix')
local http_utils = require('nginx_upload.http_utils')

-- Determines what method to use for subrequest.
local METHOD_MAP = {}
METHOD_MAP['POST'] = ngx.HTTP_POST
METHOD_MAP['PUT'] = ngx.HTTP_PUT
METHOD_MAP['PATCH'] = ngx.HTTP_PATCH
local method = ngx.req.get_method()

-- Fetch params.
local UPSTREAM = ngx.var.upstream

if (UPSTREAM == nil) then
    ngx.log(ngx.ERR, 'upstream missing. Please set var in nginx.conf')
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

-- By default use the file name from request path.
local filename = ngx.var.path
local content_type = 'application/octet-stream'
local headers = ngx.req.get_headers()

if (headers['X-File-Name'] ~= nil)
then
    -- However, if an X-File-Name header is present use that.
    filename = headers['X-File-Name']
end
if (headers['Content-Type'] ~= nil)
then
    content_type = headers['Content-Type']
end

if (filename == nil) then
    ngx.log(ngx.ERR, 'No file name provided, use X-File-Name or uri path')
    ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local gen_boundary = function()
    local t = {}
    for i=1,17 do t[i] = string.char(math.random(97, 122)) end
    return table.concat(t)
end

local temp = ngx.req.get_body_file()
local size = lfs.attributes(temp).size

local fd, ntmp = posix.mkstemp(temp .. '_XXXXXX')
posix.close(fd)
-- Documentation explicitly states not to do this, however, ngx.req.read_body()
-- and 'lua_need_request_body on' both clean up the file even when
-- 'client_body_in_file_only on' which is contrary to nginx documentation. In
-- any case, this is the only way to prevent the file from being cleaned up.
os.rename(temp, ntmp)

-- Build form for POSTing to upstream.
local parts = {file={{}}}
local boundary = gen_boundary()

parts.file[1]['content_type'] = content_type
parts.file[1]['filename'] = filename
parts.file[1]['filepath'] = ntmp
parts.file[1]['size'] = size

ngx.req.set_header('Transfer-Encoding', nil)
ngx.req.set_header('Content-Type', 'multipart/form-data; boundary=' .. boundary)

-- Determine subrequest method based on request method.
method = METHOD_MAP[method]
local body = http_utils.form_multipart_body(parts, boundary)
local r = ngx.location.capture(UPSTREAM, {method=method, body=body})

-- Pass along the status
ngx.status = r.status
-- Pass along headers
for k, v in pairs(r.header) do
    ngx.header[k] = v
end

-- If status is not 2XX, remove the temp file.
if math.floor(ngx.status / 100) ~= 2 then
    os.remove(ntmp)
    ngx.log(ngx.ERR, 'returning status "', ngx.status, '"')
    ngx.exit(ngx.status)
else
    ngx.print(r.body)
    return ngx.OK
end
