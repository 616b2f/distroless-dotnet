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

# microsoft docs to debian dependencies
#https://docs.microsoft.com/en-us/dotnet/core/install/linux-debian#dependencies
# docs for self contained dependencies
#https://github.com/dotnet/core/blob/main/Documentation/self-contained-linux-apps.md
# distroless PR to drop dotnet (there are also important infos)
#https://github.com/GoogleContainerTools/distroless/pull/711/files

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
RUN dotnet_version='6.0.10' \
    && dotnet_sha512='8a074c93845416f69f035f2d0e16251dd2bd5abcdfcb7863afd59a5ddc78fa03aede8f79b42c7ca857fc19c8dea53d43da4e4a311f35f6f2eaf9fd64afc8f9e4' \
    && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Runtime/$dotnet_version/dotnet-runtime-$dotnet_version-linux-x64.tar.gz \
    && echo "$dotnet_sha512  dotnet.tar.gz" | sha512sum -c - \
    && mkdir -p /dotnet \
    && tar -ozxf dotnet.tar.gz -C /dotnet \
    && rm dotnet.tar.gz

# Retrieve ASP.NET Core
RUN aspnet_version='6.0.10' \
    && aspnetcore_sha512='85fd0e7e8bcf371fe3234b46089382fae7418930daec8c5232347c08ebd44542924eaf628264335473467066512df36c3213949e56f0d0dae4cf387f2c5c6d0c' \
    && curl -SL --output aspnetcore.tar.gz https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/$aspnet_version/aspnetcore-runtime-$aspnet_version-linux-x64.tar.gz \
    && echo "$aspnetcore_sha512  aspnetcore.tar.gz" | sha512sum -c - \
    && mkdir -p /aspnet \
    && tar -ozxf aspnetcore.tar.gz -C /aspnet \
    && rm aspnetcore.tar.gz

FROM gcr.io/distroless/cc-debian10 as runtime-deps
COPY --from=build ["/dpkg/", "/"]

FROM runtime-deps as runtime
ENV \
    # .NET runtime version
    DOTNET_VERSION=6.0.10 \
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
    ASPNET_VERSION=6.0.10
COPY --from=build ["/aspnet", "/usr/share/dotnet"]
