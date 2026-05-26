#########################################################################################################
#                                      VPC    PROVISIONING
#########################################################################################################
module "vpc" {
  source = "../eks-prod/modules/vpc"

  env                  = var.env
  vpc_name             = var.vpc_name
  cluster_name         = var.cluster_name
  azs                  = var.azs
  vpc_cidr             = var.vpc_cidr
  private_subnets_cidr = var.private_subnets_cidr
  public_subnets_cidr  = var.public_subnets_cidr
  create_for_eks       = true
}

#########################################################################################################
#                                      EKS  PROVISIONING
#########################################################################################################
module "eks" {
  source     = "../eks-prod/modules/eks"
  depends_on = [module.vpc]

  cluster_name       = var.cluster_name
  eks_version        = var.eks_version
  admin_arn          = var.admin_arn
  subnet_ids         = module.vpc.private_subnet_ids
  principal_arn      = var.principal_arn
  principal_arn_name = var.principal_arn_name
  node_groups        = var.node_groups
}

#########################################################################################################
#                                      EKS BLUEPRINT ADDONS
#########################################################################################################
module "eks_blueprints_addons" {
  source     = "aws-ia/eks-blueprints-addons/aws"
  version    = "1.16.3"
  depends_on = [module.eks]

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EBS CSI Driver with proper IAM role
  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = "arn:aws:iam::573986291693:role/AmazonEKS_EBS_CSI_DriverRole"
    }
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [
      {
        name  = "vpcId"
        value = module.vpc.vpc_id
      }
    ]
  }

  enable_kube_prometheus_stack = true
  enable_metrics_server        = true
  enable_argocd                = true

  tags = {
    Environment = var.env
  }
}
#########################################################################################################
#                                      KARPENTER
#########################################################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.0.8"

  cluster_name                    = module.eks.cluster_name
  create_pod_identity_association = true
  namespace                       = "karpenter"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}





# retrigger Sun May 24 15:52:57 WAT 2026
# retry failed addons Sun May 24 17:00:31 WAT 2026









# unlock Tue May 26 23:18:40 WAT 2026
