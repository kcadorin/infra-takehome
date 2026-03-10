output "cluster_name" {
  description = "Name of the k3d cluster"
  value       = var.k3d_cluster_name
}

output "postgres_host" {
  description = "PostgreSQL connection host"
  value       = "localhost"
}

output "postgres_port" {
  description = "PostgreSQL connection port"
  value       = var.postgres_port
}

output "postgrest_db_connection_string" {
  description = "Connection string to connect to the postgrest database"
  value       = "postgres://postgrest_admin:${random_password.postgrest_superuser.result}@host.k3d.internal:${var.postgres_port}/postgrest"
  sensitive   = true
}
