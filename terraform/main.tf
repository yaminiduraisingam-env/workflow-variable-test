# ══════════════════════════════════════════════════════════════════════════════
# TEST v2: env0 Workflow Template — Sub-Environment Variable Scoping
#
# PURPOSE:
#   Test two approaches to scoping variables to specific sub-environments
#   within an env0 workflow template, based on Onyx research:
#
#   APPROACH A — sub_environment_configuration block on env0_environment
#                (suggested working solution per Onyx/Slack history)
#
#   APPROACH B — sub_environment_alias on env0_configuration_variable
#                (the original reported gap — expected to FAIL)
#
# WORKFLOW STRUCTURE (see env0.workflow.yml):
#   vpc  →  app   (app depends on vpc)
#
# VARIABLES BEING TESTED:
#   VPC_CIDR     → should only go to 'vpc' sub-environment
#   DB_PASSWORD  → should only go to 'app' sub-environment
#   AWS_REGION   → shared across both (template-level, always worked)
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Project ────────────────────────────────────────────────────────────────

resource "env0_project" "test" {
  name        = var.project_name
  description = "Test project for workflow sub-environment variable scoping"
}


# ── 2. Workflow Template ──────────────────────────────────────────────────────

resource "env0_template" "workflow" {
  name        = "${var.project_name}-template"
  description = "Workflow template — sub-environment variable scope test"
  type        = "workflow"
  repository  = var.repo_url
  path        = ""      # env0.workflow.yml is at the repo root
  revision    = "main"

  project_ids = [env0_project.test.id]
}


# ── 3. Shared template-level variable ✅ (always worked) ─────────────────────
# Scoped to the whole workflow template — both sub-environments inherit this.

resource "env0_configuration_variable" "shared_region" {
  name        = "AWS_DEFAULT_REGION"
  value       = "us-east-1"
  template_id = env0_template.workflow.id
}


# ══════════════════════════════════════════════════════════════════════════════
# APPROACH A: sub_environment_configuration block on env0_environment
# ══════════════════════════════════════════════════════════════════════════════
# Per Onyx research, this is the supported way to scope variables to specific
# sub-environments. Each sub_environment_configuration block targets one
# sub-environment by its alias (matching the key in env0.workflow.yml).

resource "env0_environment" "workflow_approach_a" {
  name                       = "${var.project_name}-approach-a"
  project_id                 = env0_project.test.id
  template_id                = env0_template.workflow.id
  approve_plan_automatically = true
  force_destroy              = true

  # Variable scoped ONLY to the 'vpc' sub-environment
  sub_environment_configuration {
    alias = "vpc"

    configuration {
      name  = "VPC_CIDR"
      value = "10.0.0.0/16"
    }
  }

  # Variable scoped ONLY to the 'app' sub-environment
  sub_environment_configuration {
    alias = "app"

    configuration {
      name  = "DB_PASSWORD"
      value = "super-secret-password"
    }
  }

  depends_on = [env0_configuration_variable.shared_region]
}


# ══════════════════════════════════════════════════════════════════════════════
# APPROACH B: sub_environment_alias on env0_configuration_variable
# ══════════════════════════════════════════════════════════════════════════════
# This is the original reported gap — scoping a standalone configuration
# variable resource to a specific sub-environment at the TEMPLATE level
# (not the environment level).
#
# EXPECTED RESULT: FAIL at plan with:
#   Error: Unsupported argument
#   An argument named "sub_environment_alias" is not expected here.
#
# Comment this block out to let Approach A run cleanly and prove it works.

#resource "env0_configuration_variable" "vpc_cidr_scoped" {
  #name                  = "VPC_CIDR_SCOPED"
  #value                 = "10.0.0.0/16"
  #template_id           = env0_template.workflow.id
  #sub_environment_alias = "vpc"   # ← expected to cause plan failure
#}
