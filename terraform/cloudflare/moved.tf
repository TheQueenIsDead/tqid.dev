# v5 renamed cloudflare_record. The provider moves the state across on the first plan.
# Safe to delete once that has been applied.
moved {
  from = cloudflare_record.http_app
  to   = cloudflare_dns_record.http_app
}
