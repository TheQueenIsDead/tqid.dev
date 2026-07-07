# resource "cloudflare_pages_project" "tqid-dev" {
#   account_id        = var.cloudflare_account_id
#   name              = "tqid-dev"
#   production_branch = "main"
#
#   source {
#     type = "github"
#     config {
#       owner                         = "TheQueenIsDead"
#       repo_name                     = "tqid.dev"
#       production_branch             = "main"
#       pr_comments_enabled           = true
#       deployments_enabled           = true
#       production_deployment_enabled = true
#       preview_deployment_setting    = "custom"
#       preview_branch_includes       = ["dev", "preview"]
#       preview_branch_excludes       = ["main", "prod"]
#     }
#   }
#
#   build_config {
#     build_command       = "exit 0"
#     destination_dir     = "www"
#     root_dir            = ""
#   }
#
#   deployment_configs {
#     production {
#       compatibility_date  = "2022-08-16"
#       compatibility_flags = ["nodejs_compat", "streams_enable_constructors"]
#     }
#   }
# }
#
# import {
#   to = cloudflare_pages_project.tqid-dev
#   id = "${var.cloudflare_account_id}/tqid-dev"
# }