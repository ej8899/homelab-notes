# Daily AWS Cost Summary Email – Setup Instructions

This document explains how to set up a Lambda-powered daily AWS cost summary email using Cost Explorer + SES.

> Note: These steps do not include the Lambda code itself.  
> You will paste your separately-stored function code into the Lambda code editor at the appropriate step.

---

## 1. Prerequisites

### 1. Enable Cost Explorer
- Go to Billing & Cost Management → Cost Explorer.
- Enable it if it is not already.

### 2. Prepare SES
- Go to Amazon SES in the region you will use (e.g., us-east-1).
- Verify an email or domain you can send from (e.g., alerts@ejmedia.ca).
- Ensure you have a receiving email address (e.g., ernie@ejmedia.ca).

---

## 2. Create / Configure IAM Role

1. Go to IAM → Roles.
2. Create a new role for Lambda:
   - Trusted entity: AWS service  
   - Use case: Lambda  
   - Name it: lambda-daily-cost-summary-role
3. Open the created role.
4. Go to Permissions → Inline policies → Add inline policy.
5. Choose JSON tab and paste:

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}

6. Create the policy.

---

## 3. Create the Lambda Function

1. Go to Lambda → Create function.
2. Author from scratch:
   - Function name: daily-cost-summary-email-py  
   - Runtime: Python 3.x  
3. Under Permissions, choose Use existing role and select the IAM role created earlier.
4. Create the function.

---

## 4. Add Environment Variables

1. Go to Configuration → Environment variables.
2. Add:
   - SES_FROM = your verified SES sender
   - SES_TO = your inbox address
   - SES_REGION = region used for SES (e.g., us-east-1)
3. Save.

---

## 5. Paste Your Lambda Code

1. Go to Code tab.
2. Open lambda_function.py.
3. Delete the default stub.
4. Paste your stored cost summary Lambda code.
5. Deploy.

---

## 6. Manual Test

1. Go to Code → Test.
2. Create a test event.
3. Run it.
4. You should receive an email showing yesterday’s AWS cost and top services.

---

## 7. Add a Daily Schedule Trigger

1. On the Lambda function page, go to the Function overview diagram.
2. Click Add trigger.
3. Choose EventBridge (Schedule).
4. Select cron expression.
5. Enter:

cron(0 17 * * ? *)

(17:00 UTC ≈ 10:00 local time in Alberta.)

6. Add the trigger.

---

## 8. Verify Automation

1. Go to Configuration → Triggers.
2. Ensure EventBridge (Schedule) appears and is enabled.

---

## 9. Optional Enhancements

- Add month-to-date costs.
- Add warning thresholds.
- Add weekly summaries.
- Add multiple recipients.

Your automated daily AWS cost email system is now fully configured.
