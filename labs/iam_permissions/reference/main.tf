# ----------------------------------------------------------------------------------------------------------------------
# IAM users/roles
# ----------------------------------------------------------------------------------------------------------------------

data "aws_iam_role" "s3_uploaders" {
  for_each = toset(var.s3_uploader_roles)
  name     = each.value
}

data "aws_iam_user" "s3_uploaders" {
  for_each  = toset(var.s3_uploader_users)
  user_name = each.value
}

# ----------------------------------------------------------------------------------------------------------------------
# S3
# ----------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket_prefix = var.resource_prefix
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.s3_bucket.json
}

data "aws_iam_policy_document" "s3_bucket" {

  statement {
    sid    = "AllowUserUploads"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = concat(
        [for role in data.aws_iam_role.s3_uploaders : role["arn"]],
        [for user in data.aws_iam_user.s3_uploaders : user["arn"]]
      )
    }
    actions   = ["s3:PutObject*"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid    = "AllowLambdaDeleteFromS3"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }

    actions   = ["s3:DeleteObject*"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

}

# ----------------------------------------------------------------------------------------------------------------------
# EventBridge
# ----------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "this" {
  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "this" {
  name        = "${var.resource_prefix}-bucket-uploads"
  description = "Capture uploads to bucket named `${aws_s3_bucket.this.id}`"

  event_pattern = jsonencode({
    source      = ["aws.s3"],
    detail-type = ["Object Created"],
    detail = {
      bucket = {
        name = [aws_s3_bucket.this.id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "example" {
  arn  = aws_lambda_function.this.arn
  rule = aws_cloudwatch_event_rule.this.id
}

# ----------------------------------------------------------------------------------------------------------------------
# Lambda
# ----------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name               = "${var.resource_prefix}-lambda-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_by_lambda.json
  inline_policy {
    name   = "base-permissions"
    policy = data.aws_iam_policy_document.lambda_permissions.json
  }
}

data "aws_iam_policy_document" "assume_by_lambda" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_permissions" {

  statement {
    sid       = "AllowLambdaDeleteFromS3"
    effect    = "Allow"
    actions   = ["s3:DeleteObject*"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "AllowCloudWatchLogging"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.function_log_group.arn}:*"]
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "assets/aws/lambda/bucket_uploads"
  output_path = "assets/aws/lambda/bucket_uploads/lambda_function_payload.zip"
}

resource "aws_lambda_permission" "eventbridge_invocation" {
  statement_id  = "AllowExecutionFromEventbridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.resource_prefix}-bucket-uploads"
  role             = aws_iam_role.lambda.arn
  source_code_hash = filebase64sha256(data.archive_file.lambda.output_path)
  filename         = data.archive_file.lambda.output_path
  runtime          = "python3.9"
  handler          = "main.lambda_handler"
}

resource "aws_cloudwatch_log_group" "function_log_group" {
  name              = "/aws/lambda/${var.resource_prefix}-bucket-uploads"
  retention_in_days = 1
  lifecycle {
    prevent_destroy = false
  }
}
