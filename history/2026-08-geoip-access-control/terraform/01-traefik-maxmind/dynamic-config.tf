# Traefik dynamic configuration served through the chart's file provider.
#
# Four routers share one backend so that a response code alone identifies which
# path a request took:
#
#   sms-protected  geoip2 + country gate   the policy under test
#   sms-observe    geoip2 only             reads back the verdict without blocking
#   sms-baseline   no middleware           same host, out-of-scope path
#   control        no middleware           different host, proves policy isolation
#
# sms-observe exists because a 403 on its own cannot distinguish "the source was
# correctly judged foreign" from "the plugin never saw the real address and
# stamped XX". The observe route returns 200 and echoes X-GeoIP2-IPAddress and
# X-GeoIP2-Country, which is the primary evidence for verdict V1.

locals {
  geoip_middleware_name   = "geoip2-country"
  country_middleware_name = "require-country"

  traefik_dynamic_config = {
    http = {
      routers = {
        sms-protected = {
          entryPoints = local.entrypoints
          rule        = local.protected_rule
          priority    = 100
          middlewares = [local.geoip_middleware_name, local.country_middleware_name]
          service     = "echo"
        }

        sms-observe = {
          entryPoints = local.entrypoints
          rule        = local.observe_rule
          priority    = 90
          middlewares = [local.geoip_middleware_name]
          service     = "echo"
        }

        sms-baseline = {
          entryPoints = local.entrypoints
          rule        = local.baseline_rule
          priority    = 10
          service     = "echo"
        }

        control = {
          entryPoints = local.entrypoints
          rule        = local.control_rule
          priority    = 10
          service     = "echo"
        }
      }

      middlewares = {
        (local.geoip_middleware_name) = {
          plugin = {
            geoip2 = {
              # Verified against traefik-plugins/traefikgeoip2 v0.22.0 types.go:
              # only dbPath and preferXForwardedForHeader exist, the injected
              # headers are X-GeoIP2-Country/Region/City/IPAddress, and an
              # unreadable database yields country XX rather than an error.
              dbPath                    = local.geoip_db_path
              preferXForwardedForHeader = false
            }
          }
        }

        (local.country_middleware_name) = {
          plugin = {
            checkheadersplugin = {
              headers = [
                {
                  name      = "X-GeoIP2-Country"
                  matchtype = "one"
                  values    = var.allowed_country_codes
                  required  = true
                }
              ]
            }
          }
        }
      }

      services = {
        echo = {
          loadBalancer = {
            servers = [
              {
                url = local.echo_url
              }
            ]
          }
        }
      }
    }
  }
}
