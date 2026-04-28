variable "env0_api_key" {
  description = "env0 API key — set as a sensitive variable in env0, not in plain text"
  type        = string
  sensitive   = true
}

variable "env0_api_secret" {
  description = "env0 API secret — set as a sensitive variable in env0, not in plain text"
  type        = string
  sensitive   = true
}

variable "repo_url" {
  description = "Full HTTPS URL of this GitHub repository (e.g. https://github.com/your-org/workflow-variable-test)"
  type        = string
}

variable "project_name" {
  description = "Name of the env0 project to create for this test"
  type        = string
  default     = "workflow-variable-scope-test"
}
