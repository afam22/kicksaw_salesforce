@isTest
public class LeadApiClientMock implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;
    private Boolean throwException;

    // Constructor allows us to inject the exact scenario we want to test
    public LeadApiClientMock(Integer statusCode, String responseBody, Boolean throwException) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.throwException = throwException;
    }

    public HTTPResponse respond(HTTPRequest req) {
        // 1. Handle Exception Scenarios (e.g., connection timeouts)
        if (this.throwException) {
            CalloutException e = (CalloutException)CalloutException.class.newInstance();
            e.setMessage('Simulated callout exception');
            throw e;
        }

        // 2. Handle Standard HTTP Responses
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(this.responseBody);
        res.setStatusCode(this.statusCode);
        
        return res;
    }
}