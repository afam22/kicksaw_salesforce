# Lead Integration Architecture: Design Notes & README

## Overview
This codebase provides a robust, scalable, and secure integration for synchronizing Salesforce `Lead` records with an external system via a REST API. It uses an asynchronous, event-driven architecture triggered by Lead creation and specific field updates, supported by a fault-tolerant custom logging framework.

## Architectural Flow
1. **DML Event**: A `Lead` is inserted or updated.
2. **Trigger Handler**: `LeadTriggerHandler` evaluates the record. It prevents recursive loops and filters out updates that do not require a sync (e.g., if relevant outbound fields did not change).
3. **Service Layer**: `LeadSyncService` receives the filtered Lead IDs and enqueues the asynchronous job.
4. **Queueable Execution**: `LeadSyncQueueable` processes the IDs in safe batches (chunks). It queries the Leads, maps the data, and initiates the HTTP callout.
5. **Callout Execution**: `LeadApiClient` handles the actual HTTP POST request using secure Named Credentials and processes the JSON response.
6. **DML & Logging**: The Queueable updates successful Leads with their new `External_Reference_Id__c`. If an API failure, Callout Exception, or DML error occurs, it passes the context to the `IntegrationLogger`, which safely persists the errors to the `Integration_Log__c` custom object. If records remain to be processed, the Queueable chains itself.

---

## Key Design Decisions

* **Security via Named Credentials**: Hardcoded endpoints and API keys have been completely removed from the Apex code. Authentication is managed natively by Salesforce using External Credentials and Named Credentials, ensuring API keys are securely encrypted and injected at runtime.
* **Bulkification & Governor Limit Safety**: The integration is built to handle large data volumes (like Data Loader inserts). The `LeadSyncQueueable` implements a chunking pattern (`CHUNK_SIZE = 50`) to process subsets of records and safely chain itself, avoiding the `Callout limit` (100 per transaction) and `CPU timeout` limits.
* **Recursion Prevention**: The `LeadTriggerHandler` uses a static `processed` Set to ensure that updates originating from the integration itself (such as writing back the `External_Reference_Id__c`) do not trigger an infinite loop of callouts.
* **Intelligent Filtering**: Callouts are expensive. The handler compares `Trigger.oldMap` and `Trigger.new` to ensure callouts only fire when specific, mapped fields (FirstName, LastName, Company, Email, LeadSource, Status) are modified.
* **Secure Error Logging & Fault Tolerance**: Failures do not crash the transaction. The `IntegrationLogger` safely persists errors to a custom object. It strictly enforces Salesforce security guidelines by checking Object-level (CRUD) permissions (`isCreateable`) and utilizing `Security.stripInaccessible` for Field-Level Security (FLS). If database insertion fails or the user lacks permission, it gracefully falls back to `System.debug`.

---

## Component Breakdown

| Component           | Type           | Responsibility                                                                                                                |
| :---                | :---           | :---                                                                                                                          |
| `LeadTrigger`       | Trigger        | Captures `after insert` and `after update` contexts.                                                                          |
| `LeadTriggerHandler`| Apex Class     | Contains the logic to evaluate if a Lead should be synced. Manages the recursion guard.                                     |
| `LeadSyncService`   | Apex Class     | Orchestrator for enqueueing the async job. Defines the `CHUNK_SIZE`.                                                          |
| `LeadSyncQueueable` | Queueable Apex | Handles chunking, querying, delegating callouts, updating the database, and chaining remaining records.                       |
| `LeadApiClient`     | Apex Class     | The HTTP framework. Constructs the request using the `callout:` syntax and parses standard/error JSON responses.              |
| `IntegrationLogger` | Apex Class     | Handles secure, fault-tolerant persistence of integration errors to a custom logging object, respecting CRUD and FLS limits.  |
| `LeadApiClientTest` | Test Class     | Provides high code coverage by testing bulk trigger execution, update logic filtering, and various mocked HTTP scenarios.     |
| `LeadApiClientMock` | HttpCalloutMock| A dynamic stunt double for external HTTP traffic during unit tests. |
---

## Salesforce Configuration Requirements

For this code to function in any Salesforce environment, the following metadata must be configured:

### 1. Custom Object (Logging)
Create a Custom Object named **Integration Log** (`Integration_Log__c`) to store error output, with the following Custom Fields:
* `Integration_Name__c` (Text)
* `Record_Id__c` (Text, 18 chars)
* `Message__c` (Text / Long Text Area)
* `Status_Code__c` (Number)
* `Raw_Response__c` (Long Text Area)
* `Occurred_At__c` (Date/Time)

### 2. External Credential
* Must contain a Principal with an Authentication Parameter storing the raw API Key.
* Must map a Custom Header (`x-api-key`) to the Authentication Parameter using the formula syntax: `{!$Credential.Your_Ext_Cred_Name.Your_Param_Name}`.

### 3. Named Credential
* **URL**: Set to the base URL of the mock server.
* **Allow Formulas in HTTP Header**: Must be **Checked** so Salesforce evaluates the API key formula.
* **Generate Authorization Header**: Must be **Unchecked** to prevent conflicts with the custom `x-api-key` header.

### 4. Permissions
* The integration user (or any user triggering the Lead sync) must have a Permission Set granting **External Credential Principal Access** to the credential created above.
* Users must be granted **Create** access to the `Integration_Log__c` object and its relevant fields for the logger to successfully persist database records.



# Salesforce DX Project: Next Steps

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
