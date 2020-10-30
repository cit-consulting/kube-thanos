local t = import 'kube-thanos/thanos.libsonnet';

// THIS IS MERELY AN EXAMPLE MEANT TO SHOW HOW TO USE ALL COMPONENTS!
// Neither this example nor its manifests in examples/all/manifests/ are meant to ever be run.

local commonConfig = {
  config+:: {
    local cfg = self,
    namespace: 'thanos',
    version: 'master-2020-08-11-2ea2c2b7',
    image: 'quay.io/thanos/thanos:' + cfg.version,
    replicaLabels: ['prometheus_replica', 'rule_replica'],
    objectStorageConfig: {
      name: 'thanos-objectstorage',
      key: 'thanos.yaml',
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
  },
};

local b = t.bucket(commonConfig.config {
  replicas: 1,
});

local c = t.compact(commonConfig.config {
  replicas: 1,
  serviceMonitor: true,
  disableDownsampling: true,
  deduplicationReplicaLabels: super.replicaLabels,  // reuse same labels for deduplication
});

local re = t.receive(commonConfig.config {
  replicas: 1,
  replicationFactor: 1,
  serviceMonitor: true,
  hashringConfigMapName: 'hashring',
});


local ru =
  t.rule +
  t.rule.withVolumeClaimTemplate +
  t.rule.withServiceMonitor +
  t.rule.withRules +
  commonConfig + {
    config+:: {
      name: 'thanos-rule',
      replicas: 1,
      rulesConfig: [
        { name: 'test', key: 'test' },
      ],
    },
  };

local s =
  t.store +
  t.store.withVolumeClaimTemplate +
  t.store.withServiceMonitor +
  commonConfig + {
    config+:: {
      name: 'thanos-store',
      replicas: 1,
    },
  };

local swm =
  t.store +
  t.store.withVolumeClaimTemplate +
  t.store.withServiceMonitor +
  t.store.withIndexCacheMemcached +
  t.store.withCachingBucketMemcached +
  commonConfig + {
    config+:: {
      name: 'thanos-store',
      replicas: 1,
      memcached+: {
        // NOTICE: <MEMCACHED_SERCIVE> is a placeholder to generate examples.
        // List of memcached addresses, that will get resolved with the DNS service discovery provider.
        // For DNS service discovery reference https://thanos.io/service-discovery.md/#dns-service-discovery
        addresses: ['dnssrv+_client._tcp.<MEMCACHED_SERCIVE>.%s.svc.cluster.local' % commonConfig.config.namespace],
      },
    },
  };

local q = t.query(commonConfig.config {
  name: 'thanos-query',
  replicas: 1,
  stores: [
    'dnssrv+_grpc._tcp.%s.%s.svc.cluster.local' % [service.metadata.name, service.metadata.namespace]
    for service in [re.service, ru.service, s.service]
  ],
  externalPrefix: '',
  resources: {},
  queryTimeout: '5m',
  lookbackDelta: '15m',
  ports: {
    grpc: 10901,
    http: 9090,
  },
  serviceMonitor: true,
  logLevel: 'debug',
});

local finalRu = ru {
  config+:: {
    queriers: ['dnssrv+_http._tcp.%s.%s.svc.cluster.local' % [q.service.metadata.name, q.service.metadata.namespace]],
  },
};

local qf = t.queryFrontend(commonConfig.config {
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
});

{ ['thanos-bucket-' + name]: b[name] for name in std.objectFields(b) } +
{ ['thanos-compact-' + name]: c[name] for name in std.objectFields(c) } +
{ ['thanos-receive-' + name]: re[name] for name in std.objectFields(re) } +
{ ['thanos-rule-' + name]: finalRu[name] for name in std.objectFields(finalRu) } +
{ ['thanos-store-' + name]: s[name] for name in std.objectFields(s) } +
{ ['thanos-query-' + name]: q[name] for name in std.objectFields(q) } +
{ ['thanos-query-frontend-' + name]: qf[name] for name in std.objectFields(qf) } +
{ 'thanos-store-statefulSet-with-memcached': swm.statefulSet }
