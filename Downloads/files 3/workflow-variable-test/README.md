<h3 align="left">
  <img width="600" height="128" alt="image" src="https://raw.githubusercontent.com/artemis-env0/Packages/refs/heads/main/Images/Logo%20Pack/01%20Main%20Logo/Digital/SVG/envzero_logomark_fullcolor_rgb.svg" />
</h3>

---

# Workflow Sub-Environment Variable Scoping — Test Repository

This repository is a self-contained reproduction test for a limitation in the **env0 Terraform provider** related to scoping configuration variables to specific sub-environments within a workflow template.

It was created by the env0 team in response to a client request, and serves as both a **bug reproduction** and a **workaround validation** project.

---

## Table of Contents

- [Background](#background)
- [The Problem](#the-problem)
- [What This Repo Tests](#what-this-repo-tests)
- [Repo Structure](#repo-structure)
- [Prerequisites](#prerequisites)
- [Setup Instructions](#setup-instructions)
- [Running the Tests](#running-the-tests)
  - [Phase 1 — Confirm the Gap (Approach B)](#phase-1--confirm-the-gap-approach-b)
  - [Phase 2 — Validate the Workaround (Approach A)](#phase-2--validate-the-workaround-approach-a)
- [Understanding the Results](#understanding-the-results)
- [Why the Gap Still Matters](#why-the-gap-still-matters)
- [Variable Reference](#variable-reference)
- [Fix Required in the Provider](#fix-required-in-the-provider)

---

## Background

env0 workflows allow you to deploy multiple related Terraform environments in a single orchestrated run. A workflow template references an `env0.workflow.yml` file which defines **sub-environments** and their dependencies.

```
vpc ──→ app
```

In this example, `vpc` deploys first. Once it succeeds, `app` deploys.

Each sub-environment is its own Terraform stack with its own `variables.tf`. The challenge arises when you need to pass **different values for the same variable** to different sub-environments — for example, `VPC_CIDR` should only go to `vpc`, and `DB_PASSWORD` should only go to `app`.

---

## The Problem

The env0 Terraform provider's `env0_configuration_variable` resource **does not support** scoping variables to a specific sub-environment within a workflow template.

The `sub_environment_alias` argument exists on the **data source** (read-only), but is **missing from the resource** (create/manage):

```hcl
# ✅ This works — reading a sub-environment scoped variable
data "env0_configuration_variable" "example" {
  name                  = "VPC_CIDR"
  template_id           = "some-template-id"
  sub_environment_alias = "vpc"
}

# ❌ This fails — creating a sub-environment scoped variable
resource "env0_configuration_variable" "example" {
  name                  = "VPC_CIDR"
  value                 = "10.0.0.0/16"
  template_id           = "some-template-id"
  sub_environment_alias = "vpc"   # Error: Unsupported argument
}
```

This means there is **no way to codify sub-environment scoped variables at the template level** using the provider today.

---

## What This Repo Tests

Two approaches are tested side by side:

| | Approach A | Approach B |
|---|---|---|
| **Method** | `sub_environment_configuration` block inside `env0_environment` | `sub_environment_alias` on `env0_configuration_variable` |
| **Scoped at** | Environment level | Template level |
| **Currently supported** | ✅ Yes | ❌ No — provider gap |
| **Applies to** | One specific environment | All environments created from the template |
| **Use case** | Per-environment variable overrides | Baking sub-env scoped defaults into the template |

---

## Repo Structure

```
workflow-variable-test/
│
├── env0.workflow.yml              # Workflow definition
│                                  # Declares two sub-environments: 'vpc' and 'app'
│                                  # 'app' has a dependency on 'vpc'
│
├── terraform/
│   ├── provider.tf                # env0 provider configuration
│   ├── variables.tf               # Input variable declarations
│   └── main.tf                    # All resources under test
│                                  # Contains both Approach A and Approach B
│
└── README.md                      # This file
```

---

## Prerequisites

Before running this test you will need:

- A GitHub account to host this repository
- An **env0 account** with at minimum a Standard plan (Workflows are an Enterprise feature — confirm your plan supports them)
- An **env0 API Key and Secret** generated from Organization Settings → API Keys
- A GitHub VCS integration already set up in your env0 organization

---

## Setup Instructions

### Step 1 — Push this repo to GitHub

Create a new GitHub repository (public or private) and push all files from this folder to the `main` branch, preserving the directory structure exactly as shown above.

> ⚠️ The `env0.workflow.yml` **must be at the root** of the repository. The `terraform/` directory must sit alongside it, not inside a subfolder.

### Step 2 — Create a Terraform Template in env0

1. In env0, navigate to **Templates** → **+ Create New Template**
2. Set the following:
   - **Template Name:** `workflow-variable-scope-test` (or any name you prefer)
   - **Template Type:** `Terraform`
   - **Repository:** Your new GitHub repo
   - **Path:** `terraform`
   - **Terraform Version:** `1.5.7`
   - **Revision:** `main`
3. Save the template
4. Associate it with a Project (create a new one if needed)

### Step 3 — Set Variables on the Template

Navigate to the template's **Variables** tab and add the following:

| Variable Name | Value | Sensitive | Notes |
|---|---|---|---|
| `TF_VAR_env0_api_key` | Your env0 API key | ✅ Yes | Passed into Terraform as provider credential |
| `TF_VAR_env0_api_secret` | Your env0 API secret | ✅ Yes | Passed into Terraform as provider credential |
| `TF_VAR_repo_url` | `https://github.com/YOUR_ORG/YOUR_REPO` | No | Full HTTPS URL of this GitHub repo |
| `TF_VAR_project_name` | `workflow-variable-scope-test` | No | Optional — overrides the default project name |

> ⚠️ Never put API keys in plain text in your `.tf` files or commit them to version control. Always set sensitive values as env0 variables marked as sensitive.

### Step 4 — Create an Environment

1. From your project, click **+ New Environment**
2. Select the template you created in Step 2
3. Give the environment a name
4. Click **Deploy**

---

## Running the Tests

### Phase 1 — Confirm the Gap (Approach B)

**Run the repo as-is, with no changes.**

Both Approach A and Approach B blocks are active in `main.tf`. Terraform will attempt to plan all resources and immediately fail when it reaches the `env0_configuration_variable` resource with `sub_environment_alias`.

**Expected output in env0 Plan logs:**

```
╷
│ Error: Unsupported argument
│
│   on main.tf line 94, in resource "env0_configuration_variable" "vpc_cidr_scoped":
│   94:   sub_environment_alias = "vpc"
│
│ An argument named "sub_environment_alias" is not expected here.
╵
```

No infrastructure will be created. The run fails at the Plan stage before any Apply.

This confirms the provider gap is real and reproducible.

---

### Phase 2 — Validate the Workaround (Approach A)

Comment out the entire Approach B block at the bottom of `terraform/main.tf`:

```hcl
# resource "env0_configuration_variable" "vpc_cidr_scoped" {
#   name                  = "VPC_CIDR_SCOPED"
#   value                 = "10.0.0.0/16"
#   template_id           = env0_template.workflow.id
#   sub_environment_alias = "vpc"   # ← causes failure
# }
```

Commit and push the change, then redeploy the environment in env0.

**Expected outcome:**

- ✅ Plan succeeds
- ✅ Project is created
- ✅ Workflow template is created
- ✅ `AWS_DEFAULT_REGION` is set at the template level (shared by both sub-environments)
- ✅ `VPC_CIDR = 10.0.0.0/16` is scoped **only** to the `vpc` sub-environment
- ✅ `DB_PASSWORD = super-secret-password` is scoped **only** to the `app` sub-environment
- ✅ Workflow environment is created and deployed

You can verify the variable scoping worked correctly by:
1. Opening the deployed environment in env0
2. Navigating to the workflow view
3. Clicking into each sub-environment and checking its Variables tab
4. Confirming `VPC_CIDR` only appears in `vpc` and `DB_PASSWORD` only appears in `app`

---

## Understanding the Results

### Why Phase 1 fails

The `sub_environment_alias` argument does not exist in the Terraform schema for the `env0_configuration_variable` **resource**. It only exists on the **data source**. When Terraform parses the configuration, it rejects any argument not declared in the schema — hence the "Unsupported argument" error.

### Why Phase 2 works

The `sub_environment_configuration` block is a supported argument on the `env0_environment` resource. It accepts an `alias` (matching the sub-environment key in `env0.workflow.yml`) and a nested `configuration` block for variables. This allows variables to be scoped to a specific sub-environment — but the scoping lives on the **environment resource**, not the **template resource**.

---

## Why the Gap Still Matters

Even though Approach A works, it is a **partial workaround**, not a full solution, for the following reason:

**Approach A (environment-level):** You must declare `sub_environment_configuration` blocks every time you create a new `env0_environment` from the workflow template. If your team creates 10 environments from the same template, those scoped variable declarations must be repeated in 10 places. This violates DRY (Don't Repeat Yourself) principles and makes maintenance harder.

**Approach B (template-level, if it worked):** You would declare the scoped variables once on the template. Every environment created from that template would automatically inherit the correct variable values for each sub-environment — no repetition required.

The missing feature is therefore not just a syntax gap — it has a real impact on teams managing multiple environments from a shared workflow template.

---

## Variable Reference

| Variable | Scope | Sub-Env | Value | Purpose |
|---|---|---|---|---|
| `AWS_DEFAULT_REGION` | Template | Both | `us-east-1` | Shared region — inherited by all sub-environments |
| `VPC_CIDR` | Environment | `vpc` only | `10.0.0.0/16` | Network CIDR — only relevant to the VPC layer |
| `DB_PASSWORD` | Environment | `app` only | `super-secret-password` | DB credential — only relevant to the App layer |
| `VPC_CIDR_SCOPED` | Template ❌ | `vpc` only | `10.0.0.0/16` | Attempted template-scoped variable — **causes plan failure** |

---

## Fix Required in the Provider

To fully resolve this, the `env0_configuration_variable` resource in [`terraform-provider-env0`](https://github.com/env0/terraform-provider-env0) needs the following changes:

**`client/configuration_variable.go`** — Add field to the API struct:
```go
SubEnvironmentAlias string `json:"subEnvironmentAlias,omitempty"`
```

**`env0/resource_configuration_variable.go`** — Add to the Terraform schema:
```go
"sub_environment_alias": {
  Type:        schema.TypeString,
  Optional:    true,
  ForceNew:    true,
  Description: "The alias of the sub-environment in a workflow template. Requires template_id to also be set.",
},
```

**CRUD functions** — Wire the field to/from Terraform state on Create and Read.

The data source already has this implemented — the resource just needs to mirror it.

---

*Test repo created by the env0 team. For questions or to report provider issues, open an issue on [github.com/env0/terraform-provider-env0](https://github.com/env0/terraform-provider-env0).*
