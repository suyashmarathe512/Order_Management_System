public class TimezoneConverterService {
    public static String convertToLocalTimeString(DateTime utcDateTime, String countryName) {
        if (utcDateTime == null) {
            return '';
        }
        String timeZoneSidKey = 'Asia/Kolkata';
        String normalizedCountry = (countryName != null) ? countryName.trim().toUpperCase() : '';
        switch on normalizedCountry {
            when 'USA', 'UNITED STATES' {
                timeZoneSidKey = 'America/New_York'; 
            }
            when 'UK', 'UNITED KINGDOM' {
                timeZoneSidKey = 'Europe/London';
            }
            when 'JAPAN' {
                timeZoneSidKey = 'Asia/Tokyo';
            }
            when 'AUSTRALIA' {
                timeZoneSidKey = 'Australia/Sydney';
            }
            when 'CANADA' {
                timeZoneSidKey = 'America/Toronto';
            }
            when 'GERMANY' {
                timeZoneSidKey = 'Europe/Berlin';
            }
            when 'FRANCE' {
                timeZoneSidKey = 'Europe/Paris';
            }
            when else {
                timeZoneSidKey = 'Asia/Kolkata';
            }
        }
        return utcDateTime.format('MM-dd-yyyy HH:mm a z', timeZoneSidKey);
    }
}