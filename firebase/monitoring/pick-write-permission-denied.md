# Permission-denied pick writes

Not applied. These commands are the production signal for a Firestore rules denial on a client write. Do not run them from a rules deploy, a Cloud Functions deploy, or CI.

This is a Cloud Logging metric, not a client Crashlytics event. A non-fatal in `PickService` would need an iOS change and an App Store release before it could see production, and it would miss the admin portal and any build still on the old client. Audit logs see every client as soon as Data Access write logs are on.

## What shows up

Firestore security-rules denials are Data Access audit events with `protoPayload.status.code=7` (`PERMISSION_DENIED`). The iOS and web clients write through `google.firestore.v1.Firestore.Write` or `Commit`. Cloud Functions use the Admin SDK, which bypasses rules, so a function write never appears here.

`DATA_WRITE` for `firestore.googleapis.com` is off by default. Turning it on stores every Firestore write, not only denials. On a Saturday that includes every pick save and every score update. Confirm the logging bill before leaving it on.

`Commit` and `Write` audit entries use the database as `resourceName` (`projects/pickems-fb/databases/(default)`). The document path is not guaranteed to be in the entry, and request bodies are often omitted. The metric below therefore counts every Firestore write denial, not only `/picks/`. A spike during kickoff is the incident this rules change is about. After the first real denial, open the log entry and, if a stable path field is present, add it to the filter (for example `protoPayload.authorizationInfo.resource=~"/picks/"`).

## 1. Enable Data Access write logs

Merge this into the project IAM policy. Keep every existing `auditConfigs` entry.

```bash
gcloud projects get-iam-policy pickems-fb --format=json > /tmp/pickems-iam.json
```

Add:

```json
{
  "service": "firestore.googleapis.com",
  "auditLogConfigs": [
    { "logType": "DATA_WRITE" }
  ]
}
```

```bash
gcloud projects set-iam-policy pickems-fb /tmp/pickems-iam.json
```

## 2. Log-based counter

```bash
gcloud logging metrics create firestore_write_permission_denied \
  --project=pickems-fb \
  --description="Firestore DATA_WRITE rules denials (status code 7). Includes every denied write until a sample log shows a stable picks path." \
  --log-filter='logName="projects/pickems-fb/logs/cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="firestore.googleapis.com" AND protoPayload.status.code=7 AND protoPayload.methodName=("google.firestore.v1.Firestore.Write" OR "google.firestore.v1.Firestore.Commit" OR "google.firestore.v1.Firestore.BatchWrite" OR "google.firestore.v1.Firestore.CreateDocument" OR "google.firestore.v1.Firestore.UpdateDocument")'
```

If successful `DATA_WRITE` volume is too expensive, exclude entries that are not denials. Excluded entries are not stored. Confirm in Metrics Explorer that a real code-7 entry still increments `logging.googleapis.com/user/firestore_write_permission_denied` after the exclusion exists:

```bash
gcloud logging exclusions create firestore-data-write-success \
  --project=pickems-fb \
  --description="Drop successful Firestore data-write audit logs; keep permission denials." \
  --filter='logName="projects/pickems-fb/logs/cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="firestore.googleapis.com" AND protoPayload.methodName=("google.firestore.v1.Firestore.Write" OR "google.firestore.v1.Firestore.Commit" OR "google.firestore.v1.Firestore.BatchWrite" OR "google.firestore.v1.Firestore.CreateDocument" OR "google.firestore.v1.Firestore.UpdateDocument") AND NOT protoPayload.status.code=7'
```

## 3. Alert

Create a notification channel in Cloud Monitoring first, then substitute its id. The threshold is 5 denials in 5 minutes so a single expected denial (a non-member write, a locked game) does not page. A Saturday burst of pick saves failing closed will clear it.

`alert-policy.json`:

```json
{
  "displayName": "Firestore write permission denied",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "At least 5 rules denials in 5 minutes",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/firestore_write_permission_denied\" resource.type=\"audited_resource\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "0s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "notificationChannels": ["projects/pickems-fb/notificationChannels/REPLACE_WITH_CHANNEL_ID"],
  "documentation": {
    "content": "Firestore rejected client writes (rules status code 7). Check whether pick saves are failing closed, including an expression-limit or document-access-limit denial. Functions bypass rules and will not appear here.",
    "mimeType": "text/markdown"
  },
  "alertStrategy": {
    "autoClose": "604800s"
  }
}
```

```bash
gcloud monitoring policies create --project=pickems-fb --policy-from-file=alert-policy.json
```

If the condition shows no series, the metric's monitored resource may be `global` rather than `audited_resource`. Read one series in Metrics Explorer and match `resource.type` to that.
