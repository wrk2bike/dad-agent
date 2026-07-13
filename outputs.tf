output "agent_runtime_arn" {
  description = "ARN of the deployed AgentCore Runtime."
  value       = aws_bedrockagentcore_agent_runtime.dad_joke.agent_runtime_arn
}

output "invoke_url" {
  description = "URL to POST invocations to (send as Authorization: Bearer <token>)."
  value       = "https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/${urlencode(aws_bedrockagentcore_agent_runtime.dad_joke.agent_runtime_arn)}/invocations?qualifier=DEFAULT"
}

output "token_url" {
  description = "OAuth2 token endpoint to exchange the client ID/secret for a bearer token."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "cognito_client_id" {
  description = "Cognito app client ID (used as the OAuth client_id)."
  value       = aws_cognito_user_pool_client.this.id
}

output "cognito_client_secret" {
  description = "Cognito app client secret (used as the OAuth client_secret)."
  value       = aws_cognito_user_pool_client.this.client_secret
  sensitive   = true
}

output "cognito_scope" {
  description = "OAuth scope to request when fetching a token."
  value       = "${aws_cognito_resource_server.this.identifier}/invoke"
}

output "get_token_command" {
  description = "Example command to generate a bearer token."
  value       = <<-EOT
    curl -s -u "${aws_cognito_user_pool_client.this.id}:$(terraform output -raw cognito_client_secret)" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials&scope=${aws_cognito_resource_server.this.identifier}/invoke" \
      "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token" | jq -r .access_token
  EOT
}
