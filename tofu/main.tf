provider "docker" {
  host = var.docker_host
}

resource "terraform_data" "k3d_cluster" {
  input = {
    name  = var.k3d_cluster_name
    image = "rancher/k3s:${var.k3s_version}"
  }

  provisioner "local-exec" {
    command = "k3d cluster create ${self.input.name} --image ${self.input.image} --servers 1 --agents 0 -p '8080:80@loadbalancer'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.input.name}"
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = true
}

resource "docker_container" "postgres" {
  name  = "postgres-infra-takehome"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=app",
  ]

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  restart = "unless-stopped"
}

resource "docker_volume" "postgres_data" {
  name = "postgres-infra-takehome-data"
}

provider "postgresql" {
  host     = "localhost"
  port     = var.postgres_port
  username = "postgres"
  password = var.postgres_password
  sslmode  = "disable"
}

resource "terraform_data" "postgres_ready" {
  triggers_replace = docker_container.postgres.id

  provisioner "local-exec" {
    command = "until docker exec ${docker_container.postgres.name} pg_isready -U postgres; do sleep 2; done"
  }
}

resource "postgresql_database" "postgrest" {
  name       = "postgrest"
  depends_on = [terraform_data.postgres_ready]
}

resource "random_password" "postgrest_superuser" {
  length           = 24
  special          = true
  override_special = "-_~"
}

resource "postgresql_role" "postgrest_superuser" {
  name       = "postgrest_admin"
  login      = true
  superuser  = true
  password   = random_password.postgrest_superuser.result
  depends_on = [postgresql_database.postgrest]
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-${var.k3d_cluster_name}"
}

resource "kubernetes_namespace" "postgrest" {
  metadata {
    name = "postgrest"
  }

  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_secret" "postgrest" {
  metadata {
    name      = "postgrest-config"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  data = {
    PG_DB_URI       = "postgres://postgrest_admin:${random_password.postgrest_superuser.result}@host.k3d.internal:${var.postgres_port}/postgrest"
    PG_DB_SCHEMA    = "public"
    PG_DB_ANON_ROLE = "postgrest_admin"
  }
}
