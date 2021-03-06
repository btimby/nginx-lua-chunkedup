# nginx-lua-chunkedup

This is a sketch of how to handle uploads using nginx while supporting `transfer-encoding: chunked`.

## The problem

`nginx-lua-upload-module` allows upload handling to be done by nginx, where the uploaded files are written to disk and temporary paths are passed to the backend. This performs well as the transfer is entirely handled by nginx. However, if you require `transfer-encoding: chunked`, this scheme will not work as the method that `resty-lua-upload` uses to read the request stream does not support it.

## The solution

If you are able to support uploading using PUT and forego multipart/form-data encoding (no fields, thus upload file name etc. must come from headers or URL) then chunkedup can handle the upload by
parsing the `transfer-encoding: chunked` request and emulating `nginx-lua-upload-module`.

This sketch accomplishes this by using lua to separate POST and PUT requests to the upload URI. These are handled separately. POST requests are handled by `nginx-lua-upload-module` (and `resty-lua-upload`) and a POST request is forwarded to the backend application including the temporary file name.

PUT requests are handled by an add-on that simulates `nginx-lua-upload-module` by forwarding a similar POST request to the backend. The temp file in this case is generated by parsing the `transfer-encoding: chunked` request body and writing chunks. Since the request is a PUT request, this file contains the uploaded file (no additional fields are present as with `multipart/form-data`). In this way the backend can handle either type of upload and clients that require streaming uploads via `transfer-encoding: chunked` can be satisfied.

## Running

```bash
$ make run
```

Will start a docker container. To test uploading, use:

```bash
$ make post
$ make put
```

Which will use curl to send the correct requests for uploading. Nginx is configured to echo the POST request that would otherwise be sent to the backend, in this way curl displays the request and response.
