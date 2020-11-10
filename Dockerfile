FROM openresty/openresty:centos

RUN yum install -y gcc git && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN opm get openresty/lua-resty-upload
RUN luarocks install luafilesystem
RUN luarocks install luaposix
RUN luarocks install lpeg
RUN luarocks install lua-resty-httpipe

RUN curl -o /tmp/nginx-lua-upload-module.zip -L \
    https://github.com/btimby/nginx-lua-upload-module/archive/master.zip && \
    unzip -j -d /usr/local/openresty/lualib/nginx_upload/ \
    /tmp/nginx-lua-upload-module.zip \
    nginx-lua-upload-module-master/nginx_upload/* && \
    rm -f /tmp/nginx-lua-upload-module.zip

COPY lua/nginx_lua_chunkedup.lua /usr/local/openresty/lualib/

EXPOSE 80:80
