# ── Package Lambda code automatically ────────────────────────────────────────
# Zips lambda_function.py at plan time — no manual zip step needed.
# The zip is rebuilt only when the source file changes (tracked by content hash).

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "ec2_scheduler" {
  function_name    = "ec2-scheduler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  role             = aws_iam_role.lambda.arn

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}

# ── EventBridge schedule group ────────────────────────────────────────────────
# Groups all EC2 scheduler rules together for easy management in the console.

resource "aws_scheduler_schedule_group" "ec2" {
  name = "ec2-scheduler"

  tags = {
    ManagedBy = "terraform"
  }
}

# ── Start schedules (one per entry in var.schedules) ─────────────────────────

resource "aws_scheduler_schedule" "start" {
  for_each = var.schedules

  name       = "${each.key}-start"
  group_name = aws_scheduler_schedule_group.ec2.name

  schedule_expression          = each.value.start_cron
  schedule_expression_timezone = each.value.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.ec2_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      action        = "start"
      schedule_name = each.key
    })
  }
}

# ── Stop schedules (one per entry in var.schedules) ──────────────────────────

resource "aws_scheduler_schedule" "stop" {
  for_each = var.schedules

  name       = "${each.key}-stop"
  group_name = aws_scheduler_schedule_group.ec2.name

  schedule_expression          = each.value.stop_cron
  schedule_expression_timezone = each.value.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.ec2_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      action        = "stop"
      schedule_name = each.key
    })
  }
}
