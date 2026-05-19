###############################################################################
# ArgoCD repo secret — connects ArgoCD to your manifests repo
###############################################################################
resource "kubernetes_secret" "argo-repo" {
  metadata {
    name      = "argo-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url     = var.repo_url
    project = var.repo_project
    type    = "git"
  }

  depends_on = [module.eks_blueprints_addons]
}

###############################################################################
# Namespace for expense tracker
###############################################################################
resource "kubernetes_namespace" "expense_tracker" {
  metadata {
    name = var.namespace
  }

  depends_on = [module.eks]
}

###############################################################################
# MongoDB secret — connection details for your app
###############################################################################
resource "kubernetes_secret" "mongodb_secret" {
  metadata {
    name      = "mongodb-secret"
    namespace = var.namespace
  }

  data = {
    MONGO_ROOT_USERNAME = var.mongo_username
    MONGO_ROOT_PASSWORD = var.mongo_password
    MONGO_URI           = "mongodb://${var.mongo_username}:${var.mongo_password}@mongodb-svc:27017/${var.mongo_db_name}?authSource=admin"
  }

  depends_on = [kubernetes_namespace.expense_tracker]
}

###############################################################################
# Karpenter Helm
###############################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.us-east-1
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart            = "karpenter"
  version          = "1.6.0"
  wait             = false
  create_namespace = true

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

###############################################################################
# Karpenter NodePool and EC2NodeClass
###############################################################################
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
  YAML

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "node_class" {
  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: ${module.karpenter.node_iam_role_arn}
  amiSelectorTerms:
    - alias: "al2023@latest"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${module.eks.cluster_name}"
  YAML

  depends_on = [helm_release.karpenter]
}