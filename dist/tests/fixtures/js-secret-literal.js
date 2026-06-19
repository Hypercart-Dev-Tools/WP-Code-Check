// Fixture: js-secret-literal — committed credential literals in JS.
// Positives (+) must be flagged; negatives (-) must be filtered out.

// (+) hardcoded password literal (>=8 chars, '=' form)
const dbPassword = 'Wholesale#2024!';

// (+) hardcoded api key literal (':' object-property form)
const config = {
  apiKey: 'sk_live_9c8b7a6d5e4f3g2h',
};

// (-) environment read — value is injected, not a quoted literal
const password = process.env.WP_DB_PASSWORD;

// (-) placeholder value — matches keyword shape, dropped by placeholder filter
const apiKey = 'your_api_key_here';

// (-) example value — dropped by placeholder filter
const secret = 'example-secret-value';