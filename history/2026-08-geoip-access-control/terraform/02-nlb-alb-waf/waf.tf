resource "aws_wafv2_web_acl" "this" {
  name        = "${local.name}-web-acl"
  description = "PoC controls for the exact SMS WSDL request"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "NonKRSource"
    priority = 10

    action {
      dynamic "count" {
        for_each = lower(var.waf_mode) == "count" ? [1] : []
        content {}
      }

      dynamic "block" {
        for_each = lower(var.waf_mode) == "block" ? [1] : []
        content {}
      }
    }

    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "EXACTLY"
            search_string         = "/SMS.asmx"

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          byte_match_statement {
            field_to_match {
              query_string {}
            }
            positional_constraint = "EXACTLY"
            search_string         = "WSDL"

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        statement {
          not_statement {
            statement {
              geo_match_statement {
                country_codes = ["KR"]
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}_non_kr"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "KnownAnonymousSources"
    priority = 20

    override_action {
      dynamic "count" {
        for_each = lower(var.waf_mode) == "count" ? [1] : []
        content {}
      }

      dynamic "none" {
        for_each = lower(var.waf_mode) == "block" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "EXACTLY"
                search_string         = "/SMS.asmx"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                field_to_match {
                  query_string {}
                }
                positional_constraint = "EXACTLY"
                search_string         = "WSDL"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}_anonymous"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "AWSIpReputation"
    priority = 30

    override_action {
      dynamic "count" {
        for_each = lower(var.waf_mode) == "count" ? [1] : []
        content {}
      }

      dynamic "none" {
        for_each = lower(var.waf_mode) == "block" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "EXACTLY"
                search_string         = "/SMS.asmx"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }

            statement {
              byte_match_statement {
                field_to_match {
                  query_string {}
                }
                positional_constraint = "EXACTLY"
                search_string         = "WSDL"

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}_ip_reputation"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.metric_prefix}_web_acl"
    sampled_requests_enabled   = false
  }

  tags = {
    Name = "${local.name}-web-acl"
  }
}

resource "aws_wafv2_web_acl_association" "inspection" {
  resource_arn = aws_lb.inspection.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name = "aws-waf-logs-${local.name}"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  redacted_fields {
    query_string {}
  }
}
