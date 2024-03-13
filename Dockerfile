FROM debian:11-slim as build
# debian 11 = bullseye

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

# microsoft docs to debian dependencies
# https://docs.microsoft.com/en-us/dotnet/core/install/linux-debian#dependencies
# docs for self contained dependencies
# https://github.com/dotnet/core/blob/main/Documentation/self-contained-linux-apps.md
# distroless PR to drop dotnet (there are also important infos)
# https://github.com/GoogleContainerTools/distroless/pull/711/files

# more infos to how extract for the CVE scan relevant parts from deb packages
# see https://github.com/GoogleContainerTools/distroless/issues/863
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
        libgcc-s1 \
        libgssapi-krb5-2 \
        libicu67 \
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
RUN dotnet_version='6.0.28' \
    && dotnet_sha512='5e9039c6c83bed02280e6455ee9ec59c9509055ed15d20fb628eca1147c6c3b227579fbffe5d890879b8e62312facf25089b81f4c461797a1a701a220b51d698' \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz \
    && echo "$dotnet_sha512  dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /dotnet \
    && tar -ozxf dotnet.tar.gz -C /dotnet \
    && rm dotnet.tar.gz

# Retrieve ASP.NET Core
RUN aspnet_version='6.0.28' \
    && aspnetcore_sha512='52675b81e026b4b673aedb2d9ee99a79ccb47eab090a059ef9b95615befc034ef7fbe674b01ae813870f73dcdbcfa32906969860a464aa5d356c004b6bfb201b' \
    && curl -SL --output aspnetcore.tar.gz https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/$aspnet_version/aspnetcore-runtime-$aspnet_version-linux-x64.tar.gz \
    && echo "$aspnetcore_sha512  aspnetcore.tar.gz" | sha512sum -c - \
    && mkdir -p /aspnet \
    && tar -ozxf aspnetcore.tar.gz -C /aspnet \
    && rm aspnetcore.tar.gz

FROM gcr.io/distroless/cc-debian11 as runtime-deps
COPY --from=build ["/dpkg/", "/"]

FROM runtime-deps as runtime
ENV \
    # .NET runtime version
    DOTNET_VERSION=6.0.28 \
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
    ASPNET_VERSION=6.0.28
COPY --from=build ["/aspnet", "/usr/share/dotnet"]
