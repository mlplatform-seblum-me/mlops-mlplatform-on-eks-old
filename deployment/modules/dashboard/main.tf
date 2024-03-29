
resource "helm_release" "dashboard" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart = "${path.module}/helm/"
  values = [yamlencode({
    deployment = {
      image     = "seblum/vuejs-ml-dashboard:latest"
      name      = var.name
      namespace = var.namespace
    },
    ingress = {
      host = var.domain_name
      path = var.domain_suffix
    }
  })]
}



