# Bucket holding the zipped agent source for AgentCore Runtime direct code deployment.
resource "aws_s3_bucket" "agent_code" {
  bucket = "${var.project_name}-code-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_public_access_block" "agent_code" {
  bucket = aws_s3_bucket.agent_code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# boto3/botocore are pure Python (no compiled extensions), so a plain `pip
# install --target` on any machine produces packages that run fine on
# AgentCore Runtime's arm64 Amazon Linux environment - no cross-compilation
# needed, unlike libraries with native code (numpy, pandas, etc.).
resource "null_resource" "agent_dependencies" {
  triggers = {
    requirements_hash = filesha256("${path.module}/agent/requirements.txt")
    main_py_hash      = filesha256("${path.module}/agent/main.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      rm -rf "${path.module}/build/package"
      mkdir -p "${path.module}/build/package"
      pip install --quiet --target "${path.module}/build/package" -r "${path.module}/agent/requirements.txt"
      cp "${path.module}/agent/main.py" "${path.module}/build/package/main.py"
    EOT
  }
}

data "archive_file" "agent" {
  type        = "zip"
  source_dir  = "${path.module}/build/package"
  output_path = "${path.module}/build/deployment_package.zip"
  depends_on  = [null_resource.agent_dependencies]
}

# Keying the object by the zip's own hash means every code change uploads to a
# new key, which in turn changes agent_runtime_artifact below and triggers a
# real AgentCore Runtime update (the runtime otherwise caches the zip and
# won't notice an in-place overwrite of the same key).
resource "aws_s3_object" "agent_code" {
  bucket = aws_s3_bucket.agent_code.id
  key    = "${var.project_name}/${data.archive_file.agent.output_md5}/deployment_package.zip"
  source = data.archive_file.agent.output_path
  etag   = data.archive_file.agent.output_md5
}
