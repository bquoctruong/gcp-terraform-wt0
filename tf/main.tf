provider "google" {
  project = var.project_id
}

# https://registry.terraform.io/modules/GoogleCloudPlatform/lb-http/google/latest/submodules/serverless_negs
module "lb-http" {
  source  = "GoogleCloudPlatform/lb-http/google//modules/serverless_negs"
  version = "~> 11.1.0"
  name    = "tf-cr-lb"
  project = var.project_id

  ssl                             = var.ssl
  managed_ssl_certificate_domains = [var.domain]
  https_redirect                  = var.ssl

  backends = {
    default = {
      description = null
      groups = [
        {
          group = google_compute_region_network_endpoint_group.sneg-${{ vars.SERVICE }}.id
        },
        {
          group = google_compute_region_network_endpoint_group.sneg-${{ vars.SERVICE }}.id
        }

      ]
      enable_cdn              = false
      security_policy         = null
      custom_request_headers  = null
      custom_response_headers = null

      iap_config = {
        enable               = false
        oauth2_client_id     = ""
        oauth2_client_secret = ""
      }
      log_config = {
        enable      = false
        sample_rate = null
      }
    }
  }
}

resource "google_compute_region_network_endpoint_group" "sneg-${{ vars.SERVICE }}" {
#  provider              = google-beta
  name                  = "${{ vars.SERVICE }}-sneg0"
  network_endpoint_type = "SERVERLESS"
  region                = var.region_us
  cloud_run {
#    service = ${{ vars.SERVICE }}
    service = google_cloud_run_service.${{ vars.SERVICE }}.name
   }
}

#data "google_cloud_run_locations" "available" {
#}

resource "google_cloud_run_service" "${{ vars.SERVICE }}" {
  name     = "${{ vars.SERVICE }}"
  location = var.region_us
  project  = var.project_id

#  location = data.google_cloud_run_locations.available.locations[1]

  template {
    spec {
      containers {
        image = "${{ vars.GAR_LOCATION }}-docker.pkg.dev/${{ vars.PROJECT_ID }}/${{ vars.SERVICE }}-0/${{ vars.SERVICE }}"
        ports {
            container_port = 5000
        }

      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauthus" {
  location    = google_cloud_run_service.${{ vars.SERVICE }}.location
  project     = google_cloud_run_service.${{ vars.SERVICE }}.project
  service     = google_cloud_run_service.${{ vars.SERVICE }}.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "kidsflix-frontend-global"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
}

resource "google_compute_target_http_proxy" "default" {
  name        = "lb-kidsflix-httpproxy"
  description = "a description"
  url_map     = google_compute_url_map.default.id
}

resource "google_compute_url_map" "default" {
  name            = "lb-kidsflix-global"
  description     = "a description"
  default_service = google_compute_backend_service.default.id

  host_rule {
	hosts        = [var.website]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.default.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.default.id
    }
  }
}

resource "google_compute_backend_service" "${{ vars.SERVICE }}-backend-service-lb0" {
  name        = "${{ vars.SERVICE }}-backend-service-lb0"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  health_checks = [google_compute_http_health_check.default.id]
}

resource "google_compute_http_health_check" "default" {
  name               = "check-backend"
  request_path       = "/"
  check_interval_sec = 1
  timeout_sec        = 1
}
