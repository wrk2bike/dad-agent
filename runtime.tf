resource "aws_bedrockagentcore_agent_runtime" "dad_joke" {
  agent_runtime_name = replace(var.project_name, "-", "_")
  role_arn           = aws_iam_role.agent_runtime.arn
  description        = "Fetches dad jokes from icanhazdadjoke.com"

  agent_runtime_artifact {
    code_configuration {
      runtime     = "PYTHON_3_13"
      entry_point = ["main.py"]

      code {
        s3 {
          bucket = aws_s3_bucket.agent_code.id
          prefix = aws_s3_object.agent_code.key
        }
      }
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  # Public but not anonymous: only bearer tokens issued by our Cognito user
  # pool for this specific app client are accepted.
  authorizer_configuration {
    custom_jwt_authorizer {
      discovery_url   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}/.well-known/openid-configuration"
      allowed_clients = [aws_cognito_user_pool_client.this.id]
    }
  }

  lifecycle_configuration {
    idle_runtime_session_timeout = var.idle_runtime_session_timeout
    max_lifetime                 = var.max_lifetime
  }

  environment_variables = {
    DAD_JOKE_USER_AGENT = var.dad_joke_user_agent
  }
}
