FROM debian:10-slim as build

# libgssapi-krb5-2 \
# liblttng-ust0 \
# libunwind8 \
# libuuid1 \
# zlib1g \
# curl \
# libcomerr2 \
# libidn2-0 \
# libk5crypto3 \
# libkrb5-3 \
# libldap-2.4-2 \
# libldap-common \
# libsasl2-2 \
# libsasl2-modules-db \
# libnghttp2-14 \
# libpsl5 \
# librtmp1 \
# libssh2-1 \
# libkeyutils1 \
# libkrb5support0 \
# libgnutls30 \
# libgmp10 \
# libhogweed4 \
# libidn11 \
# libnettle6 \
# libp11-kit0 \
# libffi6 \
# libtasn1-6 \
# libdb5.3 \
# libgcrypt20 \
# libgpg-error0 \
# libacl1 \
# libattr1 \
# libselinux1 \
# libpcre3 \
# libbz2-1.0 \
# liblzma5 \
# libcurl4 \
# libssl1.1 \
# libicu63 \
# libunistring2 \

RUN cd /tmp && \
		apt-get update && \
		apt-get install -y --no-install-recommends \
				# install only deps 
				curl \
				ca-certificates \
				openssl \
				&& \
		apt-get download \
				# ca-certificates \
				\
				# .NET Core dependencies
				libc6 \
				libgcc1 \
				libgssapi-krb5-2 \
				libicu63 \
				libssl1.1 \
				libstdc++6 \
				zlib1g \
				&& \
		mkdir -p /dpkg/var/lib/dpkg/status.d/ && \
		for deb in *.deb; do \
				package_name=$(dpkg-deb -I ${deb} | awk '/^ Package: .*$/ {print $2}'); \ 
				echo "Process: ${package_name}"; \
				dpkg --ctrl-tarfile $deb | tar -Oxf - ./control > /dpkg/var/lib/dpkg/status.d/${package_name}; \
				dpkg --extract $deb /dpkg || exit 10; \
		done 

# remove not needed files extracted from deb packages like man pages and docs etc.
RUN find /dpkg/ -type d -empty -delete && \
		rm -r /dpkg/usr/share/doc/
    
# Retrieve .NET runtime
RUN curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Runtime/6.0.0/dotnet-runtime-6.0.0-linux-x64.tar.gz \
    && dotnet_sha512='7cc8d93f9495b516e1b33bf82af3af605f1300bcfeabdd065d448cc126bd97ab4da5ec5e95b7775ee70ab4baf899ff43671f5c6f647523fb41cda3d96f334ae5' \
    && echo "$dotnet_sha512  dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /dotnet \
    && tar -ozxf dotnet.tar.gz -C /dotnet \
    && rm dotnet.tar.gz

# Retrieve ASP.NET Core
RUN curl -SL --output aspnetcore.tar.gz https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/6.0.0/aspnetcore-runtime-6.0.0-linux-x64.tar.gz \
    && aspnetcore_sha512='6a1ae878efdc9f654e1914b0753b710c3780b646ac160fb5a68850b2fd1101675dc71e015dbbea6b4fcf1edac0822d3f7d470e9ed533dd81d0cfbcbbb1745c6c' \
    && echo "$aspnetcore_sha512  aspnetcore.tar.gz" | sha512sum -c - \
    && mkdir -p /aspnet \
    && tar -ozxf aspnetcore.tar.gz -C /aspnet \
    && rm aspnetcore.tar.gz

FROM gcr.io/distroless/cc-debian10 as runtime-deps
COPY --from=build ["/dpkg/", "/"]

FROM runtime-deps as runtime
ENV \
    # .NET runtime version
		DOTNET_VERSION=6.0.0 \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Set the default console formatter to JSON
    Logging__Console__FormatterName=Json
COPY --from=build ["/dotnet", "/usr/share/dotnet"]

FROM runtime as aspnet
ENV \
    # Configure web servers to bind to port 8080 (to be able to run as nonroot)
    ASPNETCORE_URLS=http://+:8080 \
    # ASP.NET Core version
    ASPNET_VERSION=6.0.0
COPY --from=build ["/aspnet", "/usr/share/dotnet"]
