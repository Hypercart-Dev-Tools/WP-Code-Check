// Test file for JavaScript pattern detection
// This should trigger the api-key-exposure pattern

// Hardcoded API key (should be detected)
const API_KEY = "sk_live_1234567890abcdef1234567890abcdef";

// NEXT_PUBLIC secret (should be detected)
const secret = process.env.NEXT_PUBLIC_API_SECRET_KEY;

// Safe public URL (should NOT be detected)
const publicUrl = process.env.NEXT_PUBLIC_WORDPRESS_URL;

// Another hardcoded secret (should be detected)
const TOKEN = "ghp_1234567890abcdefghijklmnopqrstuvwxyz";

console.log("Testing JavaScript pattern detection");

