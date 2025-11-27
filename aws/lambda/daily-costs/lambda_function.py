import os
import json
import boto3
import datetime
from decimal import Decimal
import logging


logger = logging.getLogger()
logger.setLevel(logging.INFO)


# Cost Explorer lives in us-east-1
ce_client = boto3.client("ce", region_name="us-east-1")


def get_ses_client():
    ses_region = os.environ.get("SES_REGION", "us-east-1")
    return boto3.client("ses", region_name=ses_region)

def fetch_ses_send_counts():
    """
    Use SES get_send_statistics() to compute:
      - total DeliveryAttempts in last 24h
      - total DeliveryAttempts month-to-date

    Note: SES only keeps about 2 weeks of datapoints, so month-to-date
    will be partial if the month is longer than the available history.
    """
    ses_client = get_ses_client()
    resp = ses_client.get_send_statistics()

    data_points = resp.get("SendDataPoints", [])

    now_utc = datetime.datetime.now(datetime.timezone.utc)
    last_24h_start = now_utc - datetime.timedelta(days=1)

    # Start of month in UTC
    month_start = now_utc.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    last_24h_total = 0
    month_to_date_total = 0

    for dp in data_points:
        ts = dp.get("Timestamp")
        attempts = dp.get("DeliveryAttempts", 0) or 0

        if not isinstance(ts, datetime.datetime):
            continue

        # Last 24 hours
        if ts >= last_24h_start:
            last_24h_total += attempts

        # Month-to-date
        if ts >= month_start:
            month_to_date_total += attempts

    return {
        "last_24h": int(last_24h_total),
        "month_to_date": int(month_to_date_total),
    }


def fetch_month_to_date_cost():
    """
    Fetch month-to-date total cost from Cost Explorer.

    Uses Granularity=MONTHLY with a TimePeriod covering this month,
    then reads the UnblendedCost Total amount.
    """
    today = datetime.date.today()
    start_of_month = today.replace(day=1)

    start = start_of_month.strftime("%Y-%m-%d")
    # Cost Explorer End is exclusive; add 1 day to include today
    end_date = today + datetime.timedelta(days=1)
    end = end_date.strftime("%Y-%m-%d")

    response = ce_client.get_cost_and_usage(
        TimePeriod={
            "Start": start,
            "End": end
        },
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"]
    )

    results = response.get("ResultsByTime", [])
    if not results:
        return 0.0

    month_data = results[0]
    total_str = month_data.get("Total", {}).get("UnblendedCost", {}).get("Amount", "0")
    try:
        total = float(total_str)
    except (ValueError, TypeError):
        total = 0.0

    return total


def get_yesterday_datestr():
    """Return (start, end) date strings for 'yesterday' in Cost Explorer format."""
    today = datetime.date.today()
    yesterday = today - datetime.timedelta(days=1)
    start = yesterday.strftime("%Y-%m-%d")
    end = today.strftime("%Y-%m-%d")
    return start, end

def fetch_yesterdays_cost():
    """Fetch yesterday's total and per-service costs from Cost Explorer."""
    start, end = get_yesterday_datestr()

    response = ce_client.get_cost_and_usage(
        TimePeriod={
            "Start": start,
            "End": end
        },
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[
            {"Type": "DIMENSION", "Key": "SERVICE"}
        ]
    )

    results = response.get("ResultsByTime", [])
    if not results:
        return {
            "start": start,
            "end": end,
            "total": 0.0,
            "services": []
        }

    day_data = results[0]  # one day because Granularity=DAILY & 1-day range

    # Total cost for the day
    total_str = day_data.get("Total", {}).get("UnblendedCost", {}).get("Amount", "0")
    total = float(total_str)

    # Costs by service
    services_raw = day_data.get("Groups", [])
    services = []
    for g in services_raw:
        service_name = g.get("Keys", ["Unknown"])[0]
        amount_str = g.get("Metrics", {}).get("UnblendedCost", {}).get("Amount", "0")
        try:
            amount = float(amount_str)
        except (ValueError, TypeError):
            amount = 0.0
        services.append({"service": service_name, "amount": amount})

    # Sort services by amount descending
    services.sort(key=lambda x: x["amount"], reverse=True)

    return {
        "start": start,
        "end": end,
        "total": total,
        "services": services
    }

def format_email_bodies(cost_data, mtd_cost, ses_counts):
    start = cost_data["start"]
    total = cost_data["total"]
    services = cost_data["services"]

    ses_24h = ses_counts.get("last_24h", 0)
    ses_mtd = ses_counts.get("month_to_date", 0)

    # Top 3 services
    top_services = services[:3]

    # ---------- Plain text version ----------
    text_lines = []
    text_lines.append("AWS Daily Cost Summary")
    text_lines.append(f"Date: {start} (UTC billing day)")
    text_lines.append("")
    text_lines.append(f"Yesterday's total cost: ${total:.2f}")
    text_lines.append(f"Month-to-date cost:   ${mtd_cost:.2f}")
    text_lines.append("")
    text_lines.append(f"SES sends (last 24h):     {ses_24h}")
    text_lines.append(f"SES sends (month-to-date): {ses_mtd}")
    text_lines.append("")

    if top_services:
        text_lines.append(f"Top {len(top_services)} services (yesterday):")
        for s in top_services:
            text_lines.append(f"- {s['service']}: ${s['amount']:.2f}")
    else:
        text_lines.append("No per-service data available.")

    text_lines.append("")
    text_lines.append("This email was generated automatically by your AWS Lambda daily cost summary job.")
    text_body = "\n".join(text_lines)

    # ---------- HTML version ----------
    html_rows = ""
    for s in top_services:
        html_rows += f"""
            <tr>
                <td style="padding: 4px 8px; border-bottom: 1px solid #dddddd;">{s['service']}</td>
                <td style="padding: 4px 8px; border-bottom: 1px solid #dddddd; text-align: right;">${s['amount']:.2f}</td>
            </tr>
        """

    if not html_rows:
        html_rows = """
            <tr>
                <td colspan="2" style="padding: 8px; text-align: center; color: #666666;">
                    No per-service data available for this day.
                </td>
            </tr>
        """

    html_body = f"""
    <html>
    <head>
      <meta charset="UTF-8" />
      <title>AWS Daily Cost Summary</title>
    </head>
    <body style="font-family: Arial, sans-serif; font-size: 14px; color: #222;">
      <h2 style="color: #1f2933; margin-bottom: 4px;">AWS Daily Cost Summary</h2>
      <p style="margin-top: 0; color: #555;">
        Date: <strong>{start}</strong> (UTC billing day)
      </p>

      <p style="font-size: 15px; margin-bottom: 4px;">
        Yesterday's total cost:
        <strong style="font-size: 17px; color: #0b7285;">
          ${total:.2f}
        </strong>
      </p>
      <p style="font-size: 15px; margin-top: 0;">
        Month-to-date cost:
        <strong style="font-size: 16px; color: #0b7285;">
          ${mtd_cost:.2f}
        </strong>
      </p>

      <h3 style="margin-top: 18px; margin-bottom: 8px;">SES Activity</h3>
      <ul style="margin-top: 4px; margin-bottom: 12px;">
        <li>SES sends (last 24h): <strong>{ses_24h}</strong></li>
        <li>SES sends (month-to-date): <strong>{ses_mtd}</strong></li>
      </ul>

      <h3 style="margin-top: 18px; margin-bottom: 8px;">Top Services (Yesterday)</h3>
      <table style="border-collapse: collapse; min-width: 280px;">
        <thead>
          <tr>
            <th style="text-align: left; padding: 4px 8px; border-bottom: 2px solid #444444;">Service</th>
            <th style="text-align: right; padding: 4px 8px; border-bottom: 2px solid #444444;">Cost (USD)</th>
          </tr>
        </thead>
        <tbody>
          {html_rows}
        </tbody>
      </table>

      <p style="margin-top: 16px; color: #777; font-size: 12px;">
        This email was generated automatically by your AWS Lambda daily cost summary job.
      </p>
    </body>
    </html>
    """

    return text_body, html_body



def send_email_via_ses(subject, text_body, html_body):
    ses_region = os.environ.get("SES_REGION", "us-east-1")
    ses_from = os.environ.get("SES_FROM")
    ses_to = os.environ.get("SES_TO")

    if not ses_from or not ses_to:
        raise ValueError("SES_FROM and SES_TO environment variables must be set")

    ses_client = boto3.client("ses", region_name=ses_region)

    response = ses_client.send_email(
        Source=ses_from,
        Destination={
            "ToAddresses": [ses_to]
        },
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {
                "Text": {
                    "Data": text_body,
                    "Charset": "UTF-8"
                },
                "Html": {
                    "Data": html_body,
                    "Charset": "UTF-8"
                }
            }
        }
    )
    return response


def lambda_handler(event, context):
    # 1) Fetch yesterday's cost breakdown
    cost_data = fetch_yesterdays_cost()

    # 2) Fetch month-to-date total cost
    mtd_cost = fetch_month_to_date_cost()

    # 3) Fetch SES send counts (last 24h + month-to-date)
    ses_counts = fetch_ses_send_counts()

    # 4) Build subject + bodies
    subject = f"AWS Cost Summary for {cost_data['start']}"
    text_body, html_body = format_email_bodies(cost_data, mtd_cost, ses_counts)

    # 5) Send via SES (HTML + text)
    send_response = send_email_via_ses(subject, text_body, html_body)

    return {
        "status": "ok",
        "sent_to": os.environ.get("SES_TO"),
        "cost_total_yesterday": cost_data["total"],
        "cost_month_to_date": mtd_cost,
        "ses_sends_last_24h": ses_counts.get("last_24h", 0),
        "ses_sends_month_to_date": ses_counts.get("month_to_date", 0),
        "ses_message_id": send_response.get("MessageId")
    }


