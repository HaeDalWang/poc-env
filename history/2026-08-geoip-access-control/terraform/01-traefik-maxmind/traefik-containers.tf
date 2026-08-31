# Container and volume wiring for the MaxMind database, kept apart from the
# Helm release so the release file stays readable.

locals {
  geoipupdate_security_context = {
    allowPrivilegeEscalation = false
    readOnlyRootFilesystem   = true
    runAsNonRoot             = true
    runAsUser                = 65532
    runAsGroup               = 65532

    capabilities = {
      drop = ["ALL"]
    }
  }

  geoipupdate_volume_mounts = [
    {
      name      = "geoip2"
      mountPath = "/geoip2"
    },
    {
      name      = "maxmind-license"
      mountPath = "/maxmind-license"
      readOnly  = true
    },
    {
      name      = "geoipupdate-tmp"
      mountPath = "/tmp"
    },
  ]

  # geoipupdate reads credentials from files and names the output after the
  # edition ID, which is why geoip_db_path is derived from maxmind_edition_id.
  geoipupdate_env = [
    {
      name  = "GEOIPUPDATE_ACCOUNT_ID_FILE"
      value = "/maxmind-license/account-id"
    },
    {
      name  = "GEOIPUPDATE_LICENSE_KEY_FILE"
      value = "/maxmind-license/license-key"
    },
    {
      name  = "GEOIPUPDATE_EDITION_IDS"
      value = var.maxmind_edition_id
    },
    {
      name  = "GEOIPUPDATE_DB_DIR"
      value = "/geoip2"
    },
    {
      name  = "GEOIPUPDATE_LOCK_FILE"
      value = "/geoip2/.geoipupdate.lock"
    },
    {
      name  = "GEOIPUPDATE_VERBOSE"
      value = "1"
    },
  ]

  # Runs once and exits, so Traefik never starts without a database.
  geoipupdate_bootstrap_container = {
    name            = "geoipupdate-bootstrap"
    image           = var.maxmind_geoipupdate_image
    env             = local.geoipupdate_env
    securityContext = local.geoipupdate_security_context
    volumeMounts    = local.geoipupdate_volume_mounts
  }

  # Native sidecar: an init container with restartPolicy Always keeps running
  # alongside Traefik. Present only to demonstrate that rewriting the file does
  # not change verdicts, because the plugin caches its reader process-wide.
  geoipupdate_refresh_container = {
    name          = "geoipupdate-refresh"
    image         = var.maxmind_geoipupdate_image
    restartPolicy = "Always"

    env = concat(local.geoipupdate_env, [
      {
        name  = "GEOIPUPDATE_FREQUENCY"
        value = tostring(var.db_refresh_interval_hours)
      },
    ])

    securityContext = local.geoipupdate_security_context
    volumeMounts    = local.geoipupdate_volume_mounts
  }

  # Terraform compares tuple types by length, so conditional members are filtered
  # with for-if rather than a ternary that would yield tuples of different sizes.
  traefik_init_containers = concat(
    [for container in [local.geoipupdate_bootstrap_container] : container if !var.simulate_missing_db],
    [for container in [local.geoipupdate_refresh_container] : container if !var.simulate_missing_db && var.db_refresh_interval_hours > 0],
  )

  maxmind_volume_specs = [
    {
      name = "maxmind-license"
      secret = {
        secretName  = local.maxmind_secret_name
        defaultMode = 288
      }
    },
    {
      name     = "geoipupdate-tmp"
      emptyDir = {}
    },
  ]

  traefik_additional_volumes = concat(
    [
      {
        name     = "geoip2"
        emptyDir = {}
      },
    ],
    [for volume in local.maxmind_volume_specs : volume if !var.simulate_missing_db],
  )

  traefik_additional_volume_mounts = [
    {
      name      = "geoip2"
      mountPath = "/geoip2"
      readOnly  = true
    },
  ]
}
