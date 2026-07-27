# ============================================================
# Tag every instance deployed this run with the Hammerspace
# cluster ID, so the cloud console groups the cluster's
# instances. Port of the aws_tag_cluster_id Ansible role,
# cloud-neutral: the actual tagging command is supplied by the
# calling root (aws ec2 create-tags / az tag update / ...).
#
# Cluster ID = the 'cntl' (PdClusterView) object's uoid.uuid -
# the same identifier the product's license server uses.
#
# The cluster ID only exists after the cluster boots, so this is
# a post-apply step (local-exec) rather than a native tag
# resource. Requires curl, python3 and the cloud CLI used in
# tag_command.
# ============================================================

resource "terraform_data" "tag" {
  triggers_replace = [join(",", sort(var.triggers)), var.tag_command]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = file("${path.module}/scripts/wait_and_tag.sh")

    environment = {
      HS_ENDPOINT     = var.endpoint
      HS_USER         = var.hsuser
      HS_PASSWORD     = var.password
      HS_WAIT_RETRIES = var.wait_retries
      HS_RETRIES      = var.retries
      HS_DELAY        = var.delay
      TAG_COMMAND     = var.tag_command
    }
  }
}
