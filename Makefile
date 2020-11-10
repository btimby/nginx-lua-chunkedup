.PHONY: build
build:
	docker build . -t chunkedup

.PHONY: run
run: build
	docker run -p 80:80 \
		-v ${PWD}/docker/nginx/conf.d:/etc/nginx/conf.d:ro \
		-v ${PWD}/lua/nginx_lua_chunkedup.lua:/usr/local/openresty/lualib/nginx_lua_chunkedup.lua:ro \
		-ti chunkedup

.PHONY: post
post:
	curl -i -X POST -F 'file=@fixtures/hello.txt' http://localhost/upload/?foo=bar

.PHONY: put
put:
	curl -i -X PUT -H "Transfer-Encoding: chunked" -H 'Cookie: foo=bar' -H 'Content-Type: text/plain' -H 'X-File-Name: foobar.txt' \
		 --data-binary @fixtures/hello.txt http://localhost/upload/?foo=bar

.PHONY: patch
patch:
	curl -i -X PATCH -H "Transfer-Encoding: chunked" -H "Content-Type: text/plain" -H "X-File-Name: foobar.txt" \
		-H "Range: bytes=10-" --data-binary @fixtures/hello.txt http://localhost/upload/?foo=bar

.PHONY: check
check:
	luacheck --globals ngx -- lua/nginx_lua_chunkedup.lua 

# Aliases
.PHONY: POST
POST: post

.PHONY: PUT
PUT: put

.PHONY: PATCH
PATCH: patch

.PHONY: lint
lint: check
