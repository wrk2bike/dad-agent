# Dad Joke Agent on Amazon Bedrock AgentCore

Terraform that deploys a small LLM-backed agent to Amazon Bedrock AgentCore Runtime.
A Claude model (via Bedrock's Converse API) decides whether/what to search for, calls
a single tool that fetches a joke from [icanhazdadjoke.com](https://icanhazdadjoke.com/api),
and phrases the reply.

## Architecture

- **Agent code** ([agent/main.py](agent/main.py)) — implements the AgentCore HTTP
  contract (`POST /invocations`, `GET /ping` on port 8080). Calls `bedrock-runtime`
  `converse` directly (no agent framework) with one tool, `get_dad_joke`; the model
  decides when to call it and what search term (if any) to pass.
- **S3** — holds the zipped agent code (including a vendored `boto3`) for direct code
  deployment (no Docker/ECR needed). `boto3`/`botocore` are pure Python, so a plain
  `pip install --target` build works fine for AgentCore's arm64 runtime — no
  cross-compilation needed, unlike libraries with native extensions.
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
- `pip` on the machine running `terraform apply` (used by a `local-exec` provisioner to
  vendor `boto3` into the deployment zip — see [s3.tf](s3.tf)).
- AWS credentials with permission to create IAM roles, S3 buckets, Cognito resources,
  and Bedrock AgentCore runtimes.
- A region where Bedrock AgentCore is available (default here is `us-east-1`).
- **Model access enabled** for the model in `var.bedrock_model_id` (default: Claude 3.5
  Haiku, `us.anthropic.claude-3-5-haiku-20241022-v1:0`, a cross-region inference
  profile) in the Bedrock console → Model access, for your account and region. This is
  a one-time manual step — Terraform has no resource for it. If you pick a different
  model, check its exact ID in the console's model catalog.

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
  -d '{"prompt": "Tell me a dad joke"}'

# Let the model pick a topic from free text
curl -s -X POST "$(terraform output -raw invoke_url)" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: $(uuidgen)$(uuidgen)" \
  -d '{"prompt": "Got any jokes about chickens?"}'
```

Note: `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` must be at least 33 characters —
`uuidgen` twice concatenated is a quick way to get there.

Tokens expire after 60 minutes (Cognito default); re-run `get_token_command` to fetch
a new one.

## Updating the agent code

Edit [agent/main.py](agent/main.py) or [agent/requirements.txt](agent/requirements.txt)
and re-run `terraform apply` — this re-runs the `pip install` build step and re-zips.
The zip is keyed by its own content hash in S3, so a change naturally produces a new S3
key and a real `UpdateAgentRuntime` call — no manual cache-busting needed.

## Cleanup

```sh
terraform destroy
```
