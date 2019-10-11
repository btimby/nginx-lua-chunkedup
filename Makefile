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
	curl -X POST -F 'file=@fixtures/hello.txt' http://localhost/upload/

.PHONY: put
put:
	curl -X PUT -H "Transfer-Encoding: chunked" -H 'Content-Type: text-plain' \
		 -d @fixtures/hello.txt http://localhost/upload/foobar.txt

.PHONY: check
check:
	luacheck --globals ngx -- lua/nginx_lua_chunkedup.lua 
