FROM debian:11-slim as build

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
RUN dotnet_version='6.0.13' \
    && dotnet_sha512='af52e1df5e48a1b7465f8137048e9ec292104526c65e415055e5f4630a13f1d4974ae831a143dd4f17e2a813502d90e2c0aef37c6b1eb7a23d01af7ffca5400a' \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz \
    && echo "$dotnet_sha512  dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /dotnet \
    && tar -ozxf dotnet.tar.gz -C /dotnet \
    && rm dotnet.tar.gz

# Retrieve ASP.NET Core
RUN aspnet_version='6.0.13' \
    && aspnetcore_sha512='96239951972a04021b1953581c88a3e1e64553d05278fb92729c62827f38eeecd533845d6b0d3e9ba97e9d19701b9ee8e5c02d1ee54b8c14efe54c08c45c15a0' \
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
    DOTNET_VERSION=6.0.13 \
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
    ASPNET_VERSION=6.0.13
COPY --from=build ["/aspnet", "/usr/share/dotnet"]
