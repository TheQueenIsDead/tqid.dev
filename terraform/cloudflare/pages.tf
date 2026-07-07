resource "cloudflare_pages_project" "tqid-dev" {
  account_id = var.cloudflare_account_id
  name = "tqid-dev"
  production_branch = "main"
  build_config = {
    build_caching = true
    build_command = "npm run build"
    destination_dir = "www"
    root_dir = "www"
  }
  deployment_configs = {
    production = {
      always_use_latest_compatibility_date = false
      build_image_major_version = 3
      compatibility_date = "2025-01-01"
      compatibility_flags = ["url_standard"]
      fail_open = true
      limits = {
        cpu_ms = 100
      }
      placement = {
        mode = "smart"
      }
      usage_model = "standard"
    }
  }
  source = {
    config = {
      deployments_enabled = true
      owner = "TheQueenIsDead"
      owner_id = "12345678"
      path_excludes = ["string"]
      path_includes = ["string"]
      pr_comments_enabled = true
      preview_branch_excludes = ["string"]
      preview_branch_includes = ["string"]
      preview_deployment_setting = "all"
      production_branch = "main"
      production_deployments_enabled = true
      repo_id = "12345678"
      repo_name = "my-repo"
    }
    type = "github"
  }
}

import {
  to = cloudflare_pages_project.tqid-dev
  id = "${var.cloudflare_account_id}/tqid-dev"
}