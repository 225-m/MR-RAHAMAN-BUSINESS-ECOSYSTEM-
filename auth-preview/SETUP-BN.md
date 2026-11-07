# MR RAHAMAN Business Ecosystem — Authentication Preview

এই প্যাকেজটি শুধু `MR RAHAMAN Business Ecosystem` Supabase project (`pojhrvmuamdejlutxpng`)-এর জন্য। এটি Muhaimin Dairy-এর সঙ্গে কোনোভাবেই যুক্ত নয়।

## এই সংস্করণে থাকা ফিচার
- Email + password signup
- Email confirmation link flow
- Email + password login
- Password recovery email এবং reset
- Logged-in অবস্থায় password change
- Password show/hide
- Phone Auth / SMS OTP UI ও flow সম্পূর্ণ বাদ
- Email verification-এর পর `current_access_context_v1` RPC দিয়ে Platform Owner অথবা `dashboard.read`-সহ সক্রিয় Organization Membership যাচাইয়ের client gate
- RPC অনুপস্থিত/ব্যর্থ হলে deny-by-default: Dashboard বন্ধ থাকে
- এই RPC-এর SQL এখন `supabase/drafts/`-এ আছে; Production-এ প্রয়োগ করা হয়নি

## গুরুত্বপূর্ণ সীমাবদ্ধতা
1. Supabase project URL এবং browser-safe Publishable Key বসানো হয়েছে। কোনো `service_role` বা secret key নেই।
2. Email confirmation ও redirect কাজ করতে Supabase Dashboard → Authentication → URL Configuration-এ deployed site URL / redirect URL যোগ করতে হবে।
3. SMS OTP বাস্তবে পাঠাতে Supabase Dashboard → Authentication → Providers → Phone-এ Phone Auth enable এবং সমর্থিত SMS provider credentials configure করতে হবে। Provider credentials ছাড়া UI OTP পাঠাতে পারবে না।
4. Public signup চালুর আগে CAPTCHA / abuse protection এবং rate limits যাচাই করা উচিত।
5. বর্তমান database-এ Platform Owner bootstrap এবং approval workflow সম্পূর্ণ নয়। তাই verified user-কে business dashboard-এ প্রবেশাধিকার দেওয়া হয় না।
6. এটি Authentication Preview; production-ready platform নয়।

## পরীক্ষা
- Static source scan: Phone OTP UI, handlers, and phone verification conditions absent
- Database authorization RPC: source drafted, not deployed; end-to-end check NOT YET RUN
- Email confirmation / login / recovery: browser end-to-end NOT YET VERIFIED
- Duplicate HTML IDs and JavaScript syntax: require automated re-check before deployment
- Supabase JS CDN: pinned to 2.118.0

## Deploy করার আগে
- GitHub-এর `feature/authentication-v1` branch তৈরি হয়েছে। এই Preview ফাইলগুলো ওই branch-এ commit করা হবে; `main` branch অপরিবর্তিত থাকবে।
- Supabase URL Configuration-এ deployed origin allowlist করতে হবে।
- Email confirmation এবং SMS provider settings Dashboard-এ যাচাই করতে হবে।
- বাস্তব email/phone দিয়ে user-এর সম্মতিতে signup ও OTP পরীক্ষা করতে হবে।
- Owner bootstrap এবং authorization gate আলাদাভাবে review ও approve না হওয়া পর্যন্ত business dashboard চালু করা যাবে না।

## GitHub Pages Preview প্রকাশের প্রস্তুতি
1. GitHub Repository → Settings → Pages খুলুন।
2. Build and deployment-এর Source হিসেবে **GitHub Actions** নির্বাচন করুন।
3. Actions → **Deploy Authentication Preview** খুলুন।
4. Run workflow নির্বাচন করে branch হিসেবে `feature/authentication-v1` দিন।
5. Deployment সফল হলে Actions-এর deployment environment-এ প্রকাশিত URL পাওয়া যাবে।

এই workflow শুধু `feature/authentication-v1` branch থেকে manual dispatch-এ চলে। এটি `main` branch-এ deploy বা merge করে না।

## বাস্তব Authentication পরীক্ষার শর্ত
- প্রকাশিত HTTPS URL Supabase Authentication → URL Configuration-এর Redirect URLs-এ যোগ করতে হবে। বিদ্যমান Site URL অকারণে পরিবর্তন করবেন না।
- Email confirmation চালু এবং redirect URL allowlisted থাকতে হবে।
- Phone Auth চালু এবং একটি SMS provider সঠিকভাবে configured থাকতে হবে।
- বাস্তব পরীক্ষার জন্য আলাদা test email/phone ব্যবহার করুন; production owner account-এর phone পরিবর্তন করে পরীক্ষা করবেন না।
- Password, OTP বা recovery code কখনো chat-এ পাঠাবেন না।


Deployment workflow feature branch-এর push-এ চলে, তবে repository variable `ENABLE_AUTH_PREVIEW_DEPLOY=true` না থাকলে job deploy করবে না। এটি `main` branch-এ merge বা deploy করে না।


## Automated static checks
GitHub Actions-এর `Authentication Preview Checks` workflow push/PR-এ JavaScript syntax, HTML ID, email-only authentication, database access gate এবং browser secret scan চালায়। Workflow result না পাওয়া পর্যন্ত CI PASS দাবি করা যাবে না।
