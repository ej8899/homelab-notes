# SES Bounce / Complaint → Lambda → Webhook Pipeline

## Why we set this up

Sending emails to addresses that **bounce** or **complain (spam)** is bad for:

- **Deliverability** – mailbox providers (Gmail, Outlook, etc.) start to distrust your domain/IP.
- **Reputation** – SES tracks your bounce and complaint rates; high numbers can get you throttled or suspended.
- **User experience** – people who clearly don’t want your emails shouldn’t keep getting them.

This pipeline gives us a **central, automatic way** to track those problem addresses:

> When SES detects a bounce or complaint, it pushes an event that ends up in our own system, where we can log it and later mark those addresses as **“do not email”** in our send logic.

High-level flow:

**SES → SNS topic → Lambda → Webhook (PHP) → JSON log / future DB**

---

## Overall Architecture

1. **Amazon SES**
   - Sends outbound emails.
   - When delivery fails (bounce) or user reports spam (complaint), SES generates an event.
   - SES is configured to send those events to an **SNS topic**.

2. **Amazon SNS Topic**
   - Receives SES bounce/complaint notifications.
   - Forwards each notification to **Lambda** via an SNS subscription.

3. **AWS Lambda (SES Feedback Handler)**
   - Triggered by SNS.
   - Unwraps the SNS message to access the SES event.
   - Normalizes the data (email, type, timestamp, subject, message ID, etc.).
   - POSTs that normalized JSON to a **webhook endpoint** on our server.

4. **Webhook (PHP Endpoint on our server)**
   - Receives POSTed JSON from Lambda.
   - Validates a shared secret header.
   - Appends the event to a local JSON log file (and later, to MySQL).
   - This log becomes the basis for a **suppression / “do not email”** list.

---

## Webhook Destination (PHP endpoint)

### Purpose

- Serve as the **entry point on our own infrastructure** for SES feedback events.
- Accept simple JSON describing:
  - which email address bounced or complained,
  - what type of event it was (`bounce` or `complaint`),
  - when it happened,
  - basic context like subject and SES message ID.

### Behavior

- Exposed as an HTTPS URL on our host (e.g. `https://ejmedia.ca/hooks/ses-feedback.php`).
- Accepts **HTTP POST** requests with:
  - `Content-Type: application/json`
  - A custom header like `X-Webhook-Secret` containing a shared secret.
- Validates the secret for basic security.
- Saves each received event into a JSON file in the same directory:
  - e.g. `webhook-ses-feedback.json`
- Each event is appended as one more entry in an array, with an additional local “received at” timestamp.
- Future enhancement: also write to a MySQL table and tie into a more formal suppression system.

### Example event shape (conceptual)

The webhook receives normalized JSON like:

- `email` – the recipient that bounced/complained  
- `type` – `"bounce"` or `"complaint"`  
- `timestamp` – when SES says it happened  
- `subject` – subject line of the original email  
- `ses_message_id` – SES message ID (for cross-referencing our own logs)  
- `source` – the From address SES used  
- `provider` – `"ses"` (for future multi-source support)

---

## Lambda Function Setup (SES Feedback Handler)

### Purpose

- Act as the **translator** between SES/SNS events and our webhook.
- Normalize SES’s somewhat complex event JSON into a simpler, flat JSON payload for PHP.
- Handle both **bounces** and **complaints** in one place.

### Environment Variables

The Lambda function is configured with:

- `WEBHOOK_URL`  
  - The HTTPS URL of our webhook (e.g. `https://ejmedia.ca/hooks/ses-feedback.php`).
- `WEBHOOK_SECRET`  
  - Shared secret string that must match what the webhook expects.

These are used to build an authenticated POST to the webhook.

### Invocation & Logic (conceptual)

When SNS triggers the Lambda:

1. Lambda receives an SNS event containing one or more **records**.
2. For each record:
   - Extract the raw SES message JSON from `Sns.Message`.
   - Parse it to get the SES event object.
3. For each SES event:
   - Determine if it’s a **bounce** or **complaint**.
   - Extract:
     - recipient email
     - event type
     - SES timestamp
     - message subject
     - SES message ID
     - source (From address)
   - Assemble a normalized JSON payload with those fields.
4. Send an HTTP POST to `WEBHOOK_URL`:
   - JSON body with the normalized event.
   - Header `X-Webhook-Secret` set to `WEBHOOK_SECRET`.
5. Log a small summary of what was processed, including any HTTP errors (for debugging in CloudWatch).

This function doesn’t store anything itself; its job is to **bridge AWS world → our PHP world**.

---

## SNS Setup (SES Feedback Topic)

### Purpose

- Act as the **event bus** between SES and Lambda.
- Allows SES to publish bounce/complaint notifications, and Lambda to subscribe.

### Steps (conceptual)

1. In **Amazon SNS**, create a **Standard topic** (e.g. `ses-feedback-topic`).
2. Subscribe the **Lambda function** to this topic as a target:
   - In SNS: add a subscription with protocol = “AWS Lambda”.
   - Choose the SES feedback Lambda.
3. Confirm that SNS is allowed to invoke the Lambda:
   - AWS typically adds the necessary permission automatically when you create the subscription.

From this point on, any message SES publishes to this topic will automatically cause **Lambda to run once per notification**.

---

## SES Setup (Connecting Bounces & Complaints to SNS)

### Purpose

- Tell SES where to send **bounce** and **complaint** events for a specific sending identity.

### Steps (conceptual)

1. In **SES**, open the **Verified Identity** you send from:
   - Either your domain (e.g. `ejmedia.ca`)
   - Or a specific From email (e.g. `alerts@ejmedia.ca`)
2. Locate the **Feedback notifications** section for that identity.
3. For both:
   - **Bounce notifications**
   - **Complaint notifications**
   …configure SES to publish these events to the SNS topic you created earlier (`ses-feedback-topic`).
4. Save the configuration.

Now the flow is:

> SES sees a bounce/complaint → publishes to `ses-feedback-topic` → SNS triggers Lambda → Lambda calls our webhook.

---

## How this will be used later

With the basic pipeline in place, future steps on our side will include:

- Extending the webhook to:
  - Log events into a database table.
  - Flag email addresses as **“do not email”** in our internal systems.
- Updating our existing SES sending logic (in PHP) to:
  - Check for local suppression before sending.
  - Respect complaint/bounce flags and avoid re-sending to bad addresses.

All of this builds toward better **deliverability**, cleaner **email hygiene**, and a consistent way for our various EJMedia / XP4Cyber tools to stay out of spam trouble with as little manual effort as possible.
