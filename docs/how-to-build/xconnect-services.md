# Adding a Service-IP to Your Container

This guide shows how to declare a TCP service on a provider container and consume it by name from another container, exercising the [xconnect service-IP layer](../overview/xconnect-services.md).

## Provider — declare what you offer

Add a `services.json` to your container recipe's `SRC_URI` and install it at `/services.json` in the rootfs:

```json
{
  "#spec": "service-manifest-xconnect@2",
  "services": [
    {"name": "my-api", "type": "tcp", "port": 8080}
  ]
}
```

Recipe boilerplate (mirroring `pv-example-svc-tcp-provider_1.0.bb`):

```bitbake
SRC_URI += "file://${PN}.services.json"

install_scripts() {
    install -m 0644 ${WORKDIR}/${PN}.services.json ${IMAGE_ROOTFS}/services.json
}
ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "
```

The provider container then just listens on its own bound port (`0.0.0.0:8080` or its IPAM-allocated IP). It does not need to know about the ClusterIP — the service-IP layer wires up packet forwarding in front of it.

## Consumer — declare what you require

Add `args.json` with the matching service name:

```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "my-api", "type": "tcp"}
  ]
}
```

Inside the consumer, connect by hostname. xconnect injects the entry into `/etc/hosts`:

```sh
curl http://my-api.pv.local:8080/health
```

That's the entire interface. No env var to read, no socket path to know, no port discovery — just a stable name. A reboot or backend container restart does not change the resolved IP.

## What happens at runtime

1. Pantavisor starts the provider; IPAM allocates its backend IP.
2. xconnect reconciles the service graph from pv-ctrl, computes the deterministic ClusterIP from the service name, adds it as `/32` on the `pv-services` bridge, installs an nft DNAT rule (`cluster_ip:port → backend_ip:port`).
3. Pantavisor starts the consumer; xconnect injects `<cluster_ip>\t<service>.pv.local` into the consumer's `/etc/hosts`.
4. Consumer connects to the hostname → resolves to ClusterIP → kernel forwards via DNAT to the provider's IPAM IP. Zero userspace bytes for TCP→TCP.

## Configuring the ClusterIP range

Default range is `198.18.0.0/15`. Override per-device via `pantavisor.config`:

```
xconnect.services.cidr=10.55.0.0/16
```

Equivalent env or kernel cmdline knob: `PV_XCONNECT_SERVICES_CIDR=10.55.0.0/16`. Pantavisor exports the configured value into the `pv-xconnect` daemon environment on spawn.

## Verifying

From the host (or inside the appengine container):

```sh
# Bridge + ClusterIP /32
ip addr show pv-services

# nft DNAT rule for the service
nft list table inet pvx_services

# Graph emission
curl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq '.[] | select(.name=="my-api")'

# Inside consumer container
getent hosts my-api.pv.local
```

See [docs/testing/testplans/testplan-xconnect-services.md](../testing/testplans/testplan-xconnect-services.md) for the full TC matrix.

## See also

- [Service-IP layer overview](../overview/xconnect-services.md) — architecture, two-tier dispatch, ClusterIP allocation
- [pantavisor-development.md](pantavisor-development.md) — workspace overlay flow when iterating on `pv-xconnect` itself
- [pv-example-svc-tcp-provider](../../recipes-containers/pv-examples/pv-example-svc-tcp-provider_1.0.bb) and [pv-example-svc-tcp-consumer](../../recipes-containers/pv-examples/pv-example-svc-tcp-consumer_1.0.bb) — minimal worked example
