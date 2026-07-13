# Dad Joke Agent on Amazon Bedrock AgentCore

Terraform that deploys a minimal custom agent to Amazon Bedrock AgentCore Runtime.
The agent calls [icanhazdadjoke.com](https://icanhazdadjoke.com/api) and returns a
dad joke (optionally searched by a `term`). No LLM/foundation model is involved —
it's a plain HTTP tool hosted on AgentCore Runtime.

## Architecture

- **Agent code** ([agent/main.py](agent/main.py)) — stdlib-only Python implementing the
  AgentCore HTTP contract (`POST /invocations`, `GET /ping` on port 8080). No
  dependencies means no arm64 cross-compilation to worry about for direct code deploy.
- **S3** — holds the zipped agent code for direct code deployment (no Docker/ECR needed).
- **`aws_bedrockagentcore_agent_runtime`** — the runtime itself, `network_mode = PUBLIC`
  (reachable over the internet) with `code_configuration` (direct zip deploy, not a
  container image).
- **Cognito** — issues bearer tokens via the OAuth2 **client_credentials** grant
  (machine-to-machine, no end users/passwords). The runtime's `authorizer_configuration`
  only accepts JWTs issued by this user pool for this app client, so the agent is public
  but not anonymous.
- **IAM role** — the execution role AgentCore assumes to run the container; scoped to
  logging, tracing, metrics, and read access to the code bundle in S3.

## Requirements

- Terraform >= 1.7
- AWS provider >= 6.22.0 (first version with `code_configuration` support for
  `aws_bedrockagentcore_agent_runtime`) — run `terraform init -upgrade` if you have an
  older provider cached.
- AWS credentials with permission to create IAM roles, S3 buckets, Cognito resources,
  and Bedrock AgentCore runtimes.
- A region where Bedrock AgentCore is available (default here is `us-east-1`).

## Deploy

```sh
terraform init
terraform apply
```

## Get a token and invoke the agent

```sh
# Fetch a bearer token (client_credentials grant)
TOKEN=$(terraform output -raw get_token_command | bash)

# Random joke
curl -s -X POST "$(terraform output -raw invoke_url)" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: $(uuidgen)$(uuidgen)" \
  -d '{}'

# Joke matching a term
curl -s -X POST "$(terraform output -raw invoke_url)" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: $(uuidgen)$(uuidgen)" \
  -d '{"term": "chicken"}'
```

Note: `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` must be at least 33 characters —
`uuidgen` twice concatenated is a quick way to get there.

Tokens expire after 60 minutes (Cognito default); re-run `get_token_command` to fetch
a new one.

## Updating the agent code

Edit [agent/main.py](agent/main.py) and re-run `terraform apply`. The zip is keyed by
its own content hash in S3, so a code change naturally produces a new S3 key and a real
`UpdateAgentRuntime` call — no manual cache-busting needed.

## Cleanup

```sh
terraform destroy
```
