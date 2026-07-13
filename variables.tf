variable "aws_region" {
  description = "AWS region to deploy into. Must be a region where Bedrock AgentCore is available (e.g. us-east-1, us-west-2)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources created by this configuration."
  type        = string
  default     = "dad-joke-agent"
}

variable "dad_joke_user_agent" {
  description = <<-EOT
    Custom User-Agent header the agent sends to icanhazdadjoke.com, per their
    API etiquette request. No default on purpose - set your own app
    name/contact info (e.g. your email or a repo URL) in a .tfvars file
    rather than committing it here. Example:
    dad_joke_user_agent = "My Dad Joke Agent (contact: me@example.com)"
  EOT
  type        = string

  validation {
    condition     = length(trimspace(var.dad_joke_user_agent)) > 0
    error_message = "Set dad_joke_user_agent in a .tfvars file (see variables.tf) - it must identify your app to icanhazdadjoke.com."
  }
}

variable "idle_runtime_session_timeout" {
  description = "Seconds a session can be idle before AgentCore Runtime ends it."
  type        = number
  default     = 300
}

variable "max_lifetime" {
  description = "Maximum seconds a single runtime session may live."
  type        = number
  default     = 1800
}

variable "bedrock_model_id" {
  description = <<-EOT
    Bedrock model (or cross-region inference profile) ID the agent uses to
    decide when/what to search for. Requires model access to be enabled for
    this model in the Bedrock console for your account/region first -
    Terraform cannot grant that. Check the exact ID in the Bedrock console's
    model catalog for your region.
  EOT
  type        = string
  default     = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
}
