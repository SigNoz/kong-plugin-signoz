FROM kong:3.6

USER root
RUN luarocks install --server=https://luarocks.org/manifests/signoz kong-plugin-signoz
USER kong
