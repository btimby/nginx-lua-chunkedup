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
local BACKEND_URL = ngx.var.backend_url
local UPLOAD_STORE = ngx.var.upload_store or '/tmp'

if (BACKEND_URL == nil) then
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

ngx.status = 200
ngx.send_headers()
ngx.flush(true)

-- Once we open the socket, we have no further opportunity to control headers.
local size = 0
local sock, err = ngx.req.socket(true)
if not sock then
    ngx.log(ngx.ERR, 'Could not read request: ' .. err)
    ngx.exit(500)
end

local fd, ntmp = posix.mkstemp(UPLOAD_STORE .. '/chunkedup_XXXXXX')

-- We are now responsible for cleaning up ntmp...
local function cleanup()
    os.remove(ntmp)
    ngx.log(ngx.ERR, 'client went away, cleaning up')
    ngx.exit(499)
end
ngx.on_abort(cleanup)

while (true) do
    local data, typ, err

    -- Read chunk size
    data, typ, err  = sock:receive('*l')
    if not data then
        -- Error
        ngx.log(ngx.ERR, 'Error receiving: ' .. err)
        ngx.exit(500)
    end

    -- Chunk sizes are in hex (base 16)
    local chunk_size = tonumber(data, 16)
    ngx.log(ngx.INFO, 'Chunk size: ' .. data)

    if chunk_size == 0 then
        -- Success!
        break
    end

    size = size + chunk_size

    -- Read chunk
    data, typ, err = sock:receive(chunk_size)
    if not data then
        ngx.log(ngx.ERR, 'Error receiving:' .. err)
        ngx.exit(500)
    end
    posix.write(fd, data)

    -- Read trailing \r\n
    data, _, _ = sock:receive(2)
    if not data == '\r\n' then
        ngx.log(ngx.ERR, 'Data corruption: ' .. data)
        ngx.exit(500)
    end
end

posix.close(fd)

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
local r = ngx.location.capture(BACKEND_URL, {
    method=method, body=body, args=ngx.req.get_uri_args()
})

-- If status is not 2XX, remove the temp file.
if math.floor(r.status / 100) ~= 2 then
    os.remove(ntmp)
    ngx.log(ngx.ERR, 'returning status "', r.status, '"')
end

-- Output is chunked
sock:send(string.format('%x', #r.body) .. '\r\n')
sock:send(r.body .. '\r\n')
sock:send('0\r\n')
sock:send('\r\n')

ngx.exit(r.status)
