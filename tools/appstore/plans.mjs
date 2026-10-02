// What Glyf sells (2026-10-02, Arpit: "make it 2 and like whole nos only not
// 1.99 etc / lets keep 2$ and 5$ plans and the yearly ones with discounts").
// The card copy matches app/lib/profile/paywall_sheet.dart.
export const BUNDLE_ID = 'com.arpit.glyf';
export const GROUP = { referenceName: 'Glyf Pro', displayName: 'Glyf Pro' };
export const NOTIFICATIONS_URL = 'https://api.tryglyf.com/billing/apple/notifications';
const where = 'Where to find it: open Glyf, sign in, then Profile tab → Upgrade on the plan card (the same sheet opens when the day\'s free runs are used up); Monthly and Yearly switch at the top. The runs are spent in the Glyf keyboard (hold the space bar, or tap the g key). Purchases are checked on our server against Apple\'s signed transactions; Restore purchases is on the same sheet.';
const plus = 'Glyf Plus raises the daily AI allowance from 20 runs to 150, with 300 suggestions and 400 translations a day. ' + where;
const max = 'Glyf Max raises the daily AI allowance from 20 runs to 400, with 600 suggestions and 1,000 translations a day, and new features before they reach other plans. ' + where;
// Max on level 1 (the higher), Plus on level 2: moving up is immediate,
// moving down waits for the renewal. "shot" is App Review's screenshot of the
// paywall (debug build, --glyf-store-preview), Monthly or Yearly selected.
export const PLANS = [
  { productId: 'com.arpit.glyf.max.monthly', name: 'Max Monthly', period: 'ONE_MONTH', level: 1, usd: 5,
    display: 'Glyf Max', description: '400 AI runs a day and the most translations', reviewNote: max, shot: 'glyf-paywall-monthly.png' },
  { productId: 'com.arpit.glyf.max.yearly', name: 'Max Yearly', period: 'ONE_YEAR', level: 1, usd: 50,
    display: 'Glyf Max', description: '400 AI runs a day and the most translations', reviewNote: max, shot: 'glyf-paywall-yearly.png' },
  { productId: 'com.arpit.glyf.plus.monthly', name: 'Plus Monthly', period: 'ONE_MONTH', level: 2, usd: 2,
    display: 'Glyf Plus', description: '150 AI runs a day and more translations', reviewNote: plus, shot: 'glyf-paywall-monthly.png' },
  { productId: 'com.arpit.glyf.plus.yearly', name: 'Plus Yearly', period: 'ONE_YEAR', level: 2, usd: 20,
    display: 'Glyf Plus', description: '150 AI runs a day and more translations', reviewNote: plus, shot: 'glyf-paywall-yearly.png' },
];
/** "com.arpit.glyf.plus.monthly" → "plus.monthly" */
export const keyOf = (productId) => productId.split('.').slice(-2).join('.');
