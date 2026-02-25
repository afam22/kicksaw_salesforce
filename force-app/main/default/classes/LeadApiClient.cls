public with sharing class LeadApiClient {
    private static final String ENDPOINT = 'callout:Postman_Lead_API/lead';

    public class Response {
        public Boolean success;
        public String externalId;
        public String errorMessage;
        public Integer statusCode;
        public String rawResponse;
    }
    
    public static Response sendLead(Lead lead) {
        Response response = new Response();
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(ENDPOINT);
        req.setHeader('Content-Type', 'application/json');

        Map<String, Object> body = new Map<String, Object>{
            'FirstName'  => lead.FirstName,
            'LastName'   => lead.LastName,
            'Company'    => lead.Company,
            'Email'      => lead.Email,
            'LeadSource' => lead.LeadSource,
            'Status'     => lead.Status
        };
        req.setBody(JSON.serialize(body));

        HttpResponse httpRes;
        try {
            httpRes = new Http().send(req);
        } catch (System.CalloutException ex) {
            response.success = false;
            response.errorMessage = 'Callout failed: ' + ex.getMessage();
            return response;
        }

        response.statusCode = httpRes.getStatusCode();
        response.rawResponse = httpRes.getBody();

        // Attempt to parse JSON for both success + error bodies (robust)
        Map<String, Object> parsed;
        try {
            Object obj = JSON.deserializeUntyped(httpRes.getBody());
            if (obj instanceof Map<String, Object>) {
                parsed = (Map<String, Object>) obj;
            } else {
                parsed = new Map<String, Object>();
            }
        } catch (Exception e) {
            parsed = new Map<String, Object>();
        }

        String statusVal = safeString(parsed.get('status'));
        if (response.statusCode >= 200 && response.statusCode < 300 && statusVal == 'success') {
            response.success = true;

            // externalId may come back as String or Number (e.g., 728192), so stringify safely
            response.externalId = safeString(parsed.get('externalId'));
            return response;
        }

        response.success = false;

        // "message" if present; else handle common error envelope patterns
        String msg = safeString(parsed.get('message'));
        if (String.isBlank(msg)) {
            // Some APIs return: {"error": {"message": "...", "name": "..."}}
            Object errObj = parsed.get('error');
            if (errObj instanceof Map<String, Object>) {
                Map<String, Object> err = (Map<String, Object>) errObj;
                msg = safeString(err.get('message'));
                if (String.isBlank(msg)) {
                    msg = safeString(err.get('header'));
                }
                if (String.isBlank(msg)) {
                    msg = safeString(err.get('name'));
                }
            }
        }

        if (String.isBlank(msg)) {
            msg = 'HTTP ' + response.statusCode + ': ' + httpRes.getStatus();
        }
        response.errorMessage = msg;

        return response;
    }

    /**
     * Safely converts any JSON value to String.
     * Handles String/Integer/Long/Decimal/Boolean, etc. without cast exceptions.
     */
    private static String safeString(Object val) {
        if (val == null) {
            return null;
        }
        try {
            return String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }
}