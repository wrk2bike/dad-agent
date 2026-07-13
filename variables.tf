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
  description = "Custom User-Agent header the agent sends to icanhazdadjoke.com, per their API etiquette request. Include an app name and contact info/URL."
  type        = string
  default     = "Bedrock AgentCore Dad Joke Agent (contact: seankelleypegg@gmail.com)"
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
