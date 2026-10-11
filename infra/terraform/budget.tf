# Credits are consumed first, so a NET budget (IncludeCredit=true) reads $0 until the
# credit is gone - by then the card is already paying. Alert on GROSS spend instead.
resource "aws_budgets_budget" "gross" {
  name         = "${var.project}-gross-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.gross_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notify_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notify_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notify_email]
  }
}

# Last line of defence: any NET charge at all means the credit ran out
resource "aws_budgets_budget" "net_zero" {
  name         = "${var.project}-net-zero-spend"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = true
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notify_email]
  }
}
