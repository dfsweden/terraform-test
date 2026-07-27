# ============================================================
# Wait for the Hammerspace management API (:8443) to answer 200.
# Terraform port of the Ansible "Wait for the ... management API"
# uri-with-retries tasks (default 120 x 10s = 20 minutes).
#
# Requires the endpoint's 8443 port to be reachable from the
# machine running terraform (same as the Ansible control host).
# ============================================================

resource "terraform_data" "wait" {
  triggers_replace = [var.endpoint]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = file("${path.module}/scripts/wait_for_api.sh")

    environment = {
      HS_ENDPOINT = var.endpoint
      HS_USER     = var.hsuser
      HS_PASSWORD = var.password
      HS_RETRIES  = var.retries
      HS_DELAY    = var.delay
    }
  }
}
