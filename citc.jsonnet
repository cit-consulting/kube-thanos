local t = import 'kube-thanos/thanos.libsonnet';

// For an example with every option and component, please check all.jsonnet

local commonConfig = {
  local cfg = self,
  namespace: 'thanos',
  version: 'v0.22.0',
  image: 'quay.io/thanos/thanos:' + cfg.version,
  replicaLabels: ['prometheus_replica', 'rule_replica'],
  objectStorageConfig: {
    name: 'thanos-objectstorage',
    key: 'thanos.yaml',
  },
  resources: {
    requests: { cpu: 0.123, memory: '123Mi' },
    limits: { cpu: 0.420, memory: '420Mi' },
  },
  volumeClaimTemplate: {
    spec: {
      accessModes: ['ReadWriteOnce'],
      resources: {
        requests: {
          storage: '10Gi',
        },
      },
    },
  },
  // // This enables jaeger tracing for all components, as commonConfig is shared
  // tracing+: {
  //   type: 'JAEGER',
  //   config+: {
  //     sampler_type: 'ratelimiting',
  //     sampler_param: 2,
  //   },
  // },
};

local b = t.bucket(commonConfig {
  replicas: 1,
  label: 'cluster_name',
  refresh: '5m',
});

local c = t.compact(commonConfig {
  replicas: 1,
  serviceMonitor: true,
  disableDownsampling: true,
  deduplicationReplicaLabels: super.replicaLabels,  // reuse same labels for deduplication
});

local s = t.store(commonConfig {
  replicas: 1,
  serviceMonitor: true,
  bucketCache: {
    type: 'memcached',
    config+: {
      // NOTICE: <MEMCACHED_SERVICE> is a placeholder to generate examples.
      // List of memcached addresses, that will get resolved with the DNS service discovery provider.
      // For DNS service discovery reference https://thanos.io/service-discovery.md/#dns-service-discovery
      addresses: ['dnssrv+_client._tcp.memcached-service.%s.svc.cluster.local' % commonConfig.namespace],
    },
  },
  indexCache: {
    type: 'memcached',
    config+: {
      // NOTICE: <MEMCACHED_SERVICE> is a placeholder to generate examples.
      // List of memcached addresses, that will get resolved with the DNS service discovery provider.
      // For DNS service discovery reference https://thanos.io/service-discovery.md/#dns-service-discovery
      addresses: ['dnssrv+_client._tcp.memcached-service.%s.svc.cluster.local' % commonConfig.namespace],
    },
  },
});

local q = t.query(commonConfig {
  name: 'thanos-query',
  replicas: 1,
  serviceMonitor: true,
  externalPrefix: '',
  resources: {},
  queryTimeout: '5m',
  autoDownsampling: true,
  lookbackDelta: '15m',
  ports: {
    grpc: 10901,
    http: 9090,
  },
  logLevel: 'debug',
});

local re = t.receive(commonConfig {
  replicas: 1,
  replicationFactor: 1,
  serviceMonitor: true,
  hashringConfigMapName: 'hashring',
});

local qf = t.queryFrontend(commonConfig {
  replicas: 1,
  downstreamURL: 'http://%s.%s.svc.cluster.local.:%d' % [
    q.service.metadata.name,
    q.service.metadata.namespace,
    q.service.spec.ports[1].port,
  ],
  splitInterval: '12h',
  maxRetries: 10,
  logQueriesLongerThan: '10s',
  serviceMonitor: true,
  queryRangeCache: {
    type: 'memcached',
    config+: {
      // NOTICE: <MEMCACHED_SERVICE> is a placeholder to generate examples.
      // List of memcached addresses, that will get resolved with the DNS service discovery provider.
      // For DNS service discovery reference https://thanos.io/service-discovery.md/#dns-service-discovery
      addresses: ['dnssrv+_client._tcp.memcached-service.%s.svc.cluster.local' % commonConfig.namespace],
    },
  },
  labelsCache: {
    type: 'memcached',
    config+: {
      // NOTICE: <MEMCACHED_SERVICE> is a placeholder to generate examples.
      // List of memcached addresses, that will get resolved with the DNS service discovery provider.
      // For DNS service discovery reference https://thanos.io/service-discovery.md/#dns-service-discovery
      addresses: ['dnssrv+_client._tcp.memcached-service.%s.svc.cluster.local' % commonConfig.namespace],
    },
  },
});

local manifests_thanos_bucket = { [name]: b[name] for name in std.objectFields(b) if b[name] != null };
local manifests_thanos_compact = { [name]: c[name] for name in std.objectFields(c) if c[name] != null && name != 'serviceMonitor' };
local manifests_thanos_compact_prom = { [name]: c[name] for name in std.objectFields(c) if c[name] != null && name == 'serviceMonitor' };
local manifests_thanos_store = { [name]: s[name] for name in std.objectFields(s) if s[name] != null && name != 'serviceMonitor' };
local manifests_thanos_store_prom = { [name]: s[name] for name in std.objectFields(s) if s[name] != null && name == 'serviceMonitor' };
local manifests_thanos_query = { [name]: q[name] for name in std.objectFields(q) if q[name] != null && name != 'serviceMonitor' };
local manifests_thanos_query_prom = { [name]: q[name] for name in std.objectFields(q) if q[name] != null && name == 'serviceMonitor' };
local manifests_thanos_receive = { [name]: re[name] for name in std.objectFields(re) if re[name] != null && name != 'serviceMonitor' };
local manifests_thanos_receive_prom = { [name]: re[name] for name in std.objectFields(re) if re[name] != null && name == 'serviceMonitor' };
local manifests_thanos_queryfront = { [name]: qf[name] for name in std.objectFields(qf) if qf[name] != null && name != 'serviceMonitor' };
local manifests_thanos_queryfront_prom = { [name]: qf[name] for name in std.objectFields(qf) if qf[name] != null && name == 'serviceMonitor' };

local manifests =
  { ['thanos-bucket/deploy/' + name]: b[name] for name in std.objectFields(b) if b[name] != null} +
  { ['thanos-compact/deploy/' + name]: c[name] for name in std.objectFields(c) if c[name] != null  && name != 'serviceMonitor' } +
  { ['thanos-compact/prometheus/' + name]: c[name] for name in std.objectFields(c) if c[name] != null  && name == 'serviceMonitor' } +
  { ['thanos-store/deploy/' + name]: s[name] for name in std.objectFields(s) if s[name] != null && name != 'serviceMonitor' } +
  { ['thanos-store/prometheus/' + name]: s[name] for name in std.objectFields(s) if s[name] != null && name == 'serviceMonitor' } +
  { ['thanos-query/deploy/' + name]: q[name] for name in std.objectFields(q) if q[name] != null && name != 'serviceMonitor' } +
  { ['thanos-query/prometheus/' + name]: q[name] for name in std.objectFields(q) if q[name] != null && name == 'serviceMonitor' } +
  { ['thanos-queryfront/deploy/' + name]: qf[name] for name in std.objectFields(qf) if qf[name] != null && name != 'serviceMonitor' } +
  { ['thanos-queryfront/prometheus/' + name]: qf[name] for name in std.objectFields(qf) if qf[name] != null && name == 'serviceMonitor' } +
  { ['thanos-receive/deploy/' + name]: re[name] for name in std.objectFields(re) if re[name] != null && name != 'serviceMonitor' } +
  { ['thanos-receive/prometheus/' + name]: re[name] for name in std.objectFields(re) if re[name] != null && name == 'serviceMonitor' };

local kustomizationResourceFileFolder(name) = '' + name + '.yaml';

local kustomization_thanos_bucket = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_bucket))
};

local kustomization_thanos_compact = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_compact))
};
local kustomization_thanos_compact_prom = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_compact_prom))
};

local kustomization_thanos_store = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_store))
};
local kustomization_thanos_store_prom = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_store_prom))
};

local kustomization_thanos_query = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_query))
};
local kustomization_thanos_query_prom = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_query_prom))
};

local kustomization_thanos_queryfront = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_queryfront))
};
local kustomization_thanos_queryfront_prom = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_queryfront_prom))
};

local kustomization_thanos_receive = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_receive))
};
local kustomization_thanos_receive_prom = {
  apiVersion: 'kustomize.config.k8s.io/v1beta1',
  kind: 'Kustomization',
  resources: std.map(kustomizationResourceFileFolder, std.objectFields(manifests_thanos_receive_prom))
};

manifests {
  'thanos-bucket/deploy/kustomization': kustomization_thanos_bucket,
  'thanos-compact/deploy/kustomization': kustomization_thanos_compact,
  'thanos-compact/prometheus/kustomization': kustomization_thanos_compact_prom,
  'thanos-query/deploy/kustomization': kustomization_thanos_query,
  'thanos-query/prometheus/kustomization': kustomization_thanos_query_prom,
  'thanos-queryfront/deploy/kustomization': kustomization_thanos_queryfront,
  'thanos-queryfront/prometheus/kustomization': kustomization_thanos_queryfront_prom,
  'thanos-store/deploy/kustomization': kustomization_thanos_store,
  'thanos-store/prometheus/kustomization': kustomization_thanos_store_prom,
  'thanos-receive/deploy/kustomization': kustomization_thanos_receive,
  'thanos-receive/prometheus/kustomization': kustomization_thanos_receive_prom
}
