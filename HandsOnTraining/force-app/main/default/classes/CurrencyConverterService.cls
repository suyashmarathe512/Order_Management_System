public with sharing class CurrencyConverterService {
    private static final String API_KEY = '70ecc110b512b33c30ea96a3';
    public static final Map<String, String> COUNTRY_TO_CURRENCY = new Map<String, String>{
        'INDIA' => 'INR',
        'USA' => 'USD',
        'UNITED STATES' => 'USD',
        'UNITED KINGDOM' => 'GBP',
        'JAPAN' => 'JPY',
        'CANADA' => 'CAD',
        'AUSTRALIA' => 'AUD',
        'GERMANY' => 'EUR',
        'FRANCE' => 'EUR'
    };
    public class CurrencyException extends Exception {}
    // Convert by country (server-side API)
    public static Decimal convertByCountry(Decimal amount, String baseCurrency, String country) {
        String targetCurrency = COUNTRY_TO_CURRENCY.get(country == null ? '' : country.trim().toUpperCase());
        if (targetCurrency == null) {
            throw new CurrencyException('No currency mapping for country: ' + country);
        }
        return convert(amount, baseCurrency, targetCurrency);
    }
    // Expose an Aura/LWC-invocable method to call from client
    @AuraEnabled(cacheable=true)
    public static Decimal convertByCountryAura(Decimal amount, String baseCurrency, String country) {
        return convertByCountry(amount, baseCurrency, country);
    }
    public static Decimal convert(Decimal amount, String fromCurrency, String toCurrency) {
        // Endpoint format:
        String endpoint = 'https://v6.exchangerate-api.com/v6/' + API_KEY + '/latest/' + fromCurrency;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(15000);
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() != 200) {
            throw new CurrencyException('Callout failed: ' + res.getStatus());
        }
        Map<String, Object> json = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (!json.containsKey('conversion_rates')) {
            throw new CurrencyException('Invalid response from ExchangeRate API.');
        }
        Map<String, Object> rates = (Map<String, Object>) json.get('conversion_rates');
        if (!rates.containsKey(toCurrency)) {
            throw new CurrencyException('Target currency not available: ' + toCurrency);
        }
        Decimal rate = Decimal.valueOf(String.valueOf(rates.get(toCurrency)));
        return amount * rate;
    }
}
