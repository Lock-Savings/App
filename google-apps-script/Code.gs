function doPost(e) {
  const properties = PropertiesService.getScriptProperties();
  const expectedSecret = properties.getProperty("WEBHOOK_SECRET");

  if (
    !expectedSecret ||
    !e ||
    !e.parameter ||
    e.parameter.key !== expectedSecret
  ) {
    return jsonResponse({ ok: false, error: "Unauthorized." });
  }

  let payload;
  try {
    payload = JSON.parse(e.postData.contents);
  } catch (error) {
    return jsonResponse({ ok: false, error: "Invalid webhook payload." });
  }

  if (
    payload.type !== "INSERT" ||
    payload.schema !== "public" ||
    payload.table !== "withdrawal_requests"
  ) {
    return jsonResponse({ ok: true, ignored: true });
  }

  const request = payload.record;
  const amount = Number(request && request.amount);
  if (
    !request ||
    request.status !== "pending" ||
    !Number.isInteger(amount) ||
    amount < 1 ||
    !["full", "partial"].includes(request.request_type)
  ) {
    return jsonResponse({ ok: false, error: "Invalid withdrawal request." });
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    const cache = CacheService.getScriptCache();
    const cacheKey = "withdrawal-email-" + request.id;
    if (cache.get(cacheKey)) {
      return jsonResponse({ ok: true, duplicate: true });
    }

    const recipient =
      properties.getProperty("ADMIN_EMAIL") || "vanywinner@gmail.com";
    const requestType = request.request_type === "full" ? "Full" : "Partial";
    const requestedAt = request.created_at || new Date().toISOString();
    const body = [
      "A new Lock Cash withdrawal request was submitted.",
      "",
      "Request ID: " + request.id,
      "User ID: " + request.user_id,
      "Type: " + requestType,
      "Amount: KES " + amount.toLocaleString("en-KE"),
      "Submitted: " + requestedAt,
      "Status: Pending",
      "",
      "Review the request at https://lock-savings.github.io/App/admin.html",
      "Approval is available after 72 hours. M-Pesa payout is handled manually.",
    ].join("\n");

    MailApp.sendEmail({
      to: recipient,
      subject: "Lock Cash withdrawal request #" + request.id,
      body: body,
      name: "Lock Cash",
    });

    cache.put(cacheKey, "sent", 21600);
    return jsonResponse({ ok: true });
  } finally {
    lock.releaseLock();
  }
}

function jsonResponse(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(
    ContentService.MimeType.JSON,
  );
}
