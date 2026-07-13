# Cognito is used purely as a token issuer here (machine-to-machine
# client-credentials grant) so callers can generate a bearer token to invoke
# the agent. There's no hosted UI, no end users, and no passwords to manage.
resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-pool"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_resource_server" "this" {
  identifier   = "dad-joke-agent"
  name         = "Dad Joke Agent"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "invoke"
    scope_description = "Permission to invoke the dad joke agent"
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.this.identifier}/invoke"]
  supported_identity_providers         = ["COGNITO"]
}
