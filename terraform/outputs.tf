output "cloud_run_service_url" {
  description = "URL of the deployed n8n Cloud Run service."
  value       = google_cloud_run_v2_service.n8n.uri
}

output "custom_domain_url" {
  description = "Custom domain URL (if configured)."
  value       = var.custom_domain != "" ? "https://${var.custom_domain}" : "No custom domain configured"
}

output "dns_records_required" {
  description = "DNS records to configure for custom domain."
  value = var.custom_domain != "" ? {
    type  = "CNAME"
    name  = var.custom_domain
    value = "ghs.googlehosted.com"
    note  = "Add this CNAME record to your DNS provider and verify domain ownership in Google Search Console"
  } : null
} 
