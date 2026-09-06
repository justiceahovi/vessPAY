# VessPay — Beginner-Friendly Free Hosting Guide (Zero Code Setup)

> **Goal:** Host the complete VessPay system on 100% free services (**$0/month**) in under 15 minutes, with no complex server knowledge required.

---

## The Big Picture (In Plain English)

Think of VessPay like a store:
1. **Supabase (The Database)**: The digital filing cabinet. It stores who signed up, their passwords, and their wallet balances.
2. **Railway (The Backend Server)**: The engine running 24/7 in the cloud. When a user taps "Pay", this server talks to the WeWire payment network to deliver Ghana Mobile Money.
3. **Vercel (The Frontend / Website)**: The storefront. The website users visit in their web browser.
4. **WeWire Africa (Payment Rails)**: The partner that actually moves money to MTN, Telecel, or Ghanaian banks.

```
[ User in Browser or Phone ]
           │
           ▼
 [ Vercel: Website / App ]
           │
           ▼
 [ Railway: Backend Server ] ────► [ Supabase: Database ]
           │
           ▼
 [ WeWire Africa: Mobile Money ]
```

---

## What You Need Before Starting

- [ ] A free [GitHub](https://github.com) account (with your VessPay code uploaded to a repository).
- [ ] A web browser.
- [ ] 15 minutes.
- *(No credit card required for any of these free tiers!)*

---

## Step 1: Create Your Free Database (Supabase)
⏱️ **Time: 3 minutes**

1. Go to **[supabase.com](https://supabase.com)** and click **"Start your project"** (Sign in with your GitHub account).
2. Click the green button: **"New Project"**.
3. Fill in the simple form:
   - **Organization**: Choose your default personal organization.
   - **Name**: Type `vesspay-db`
   - **Database Password**: Type a strong password you won't forget (e.g. `VessPaySecure2026!`). **Write this down!**
   - **Region**: Pick whichever location is closest to you (e.g. *Central EU - Frankfurt* or *East US*).
   - **Pricing Plan**: Leave on **Free ($0/month)**.
4. Click **"Create new project"**. Wait about 60 seconds for Supabase to finish building it.
5. Get your connection link:
   - In the left sidebar, click the **Project Settings** icon (the small gear ⚙️ at the very bottom).
   - Click on **"Database"**.
   - Scroll down to the section called **"Connection parameters"** or **"Connection string"**.
   - Click the **"URI"** tab.
   - Change Mode from *Transaction* to **Session** (or use Port 5432).
   - Click the **Copy** button. The link will look like this:
     ```
     postgresql://postgres.[PROJECT-NAME]:[YOUR-PASSWORD]@aws-0-[REGION].pooler.supabase.com:5432/postgres
     ```
   - Replace `[YOUR-PASSWORD]` with the password you created in step 3.
   - **Save this link in a Notepad!** You will paste it into Railway in Step 2.

> 🎉 **Milestone 1 Complete:** Your free cloud database is live!

---

## Step 2: Deploy Your Backend Server (Railway)
⏱️ **Time: 4 minutes**

Railway will run your backend code 24/7. When it starts up, it will automatically connect to Supabase and create all your tables for you.

1. Go to **[railway.app](https://railway.app)** and click **"Login"** (choose **Sign in with GitHub**).
2. Click **"+ New Project"**.
3. Select **"Deploy from GitHub repo"**.
4. Choose your **`vessPAY`** repository from the list.
5. Railway will create a box on your screen representing your app. Click on that box.
6. Click the **"Settings"** tab:
   - Scroll to **"Root Directory"**.
   - Click **"Edit"**, type: `apps/backend`
   - Click **"Save"**.
7. Click the **"Variables"** tab (this is where we tell your server how to talk to Supabase and WeWire):
   - Click **"+ New Variable"** (or **"Raw Editor"**) and paste the following values:

| Variable Name | What to paste in the Value box |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | `3000` |
| `DATABASE_URL` | *Paste your Supabase link from Step 1* |
| `JWT_SECRET` | `vesspay_super_secret_jwt_key_2026_change_me` *(or any long random string)* |
| `JWT_EXPIRES_IN` | `7d` |
| `WEWIRE_API_KEY` | *Your WeWire sandbox key (starts with `sk_test_...`)* |
| `WEWIRE_BASE_URL` | `https://stage-capi.wewireafrica.com` |
| `WEWIRE_WEBHOOK_SECRET` | `whsec_vesspay_demo_secret_2026` |
| `PAYMENT_FEE_PERCENT` | `0.01` |

8. Click the **"Settings"** tab again:
   - Scroll down to the **"Networking"** section.
   - Under **Public Networking**, click **"Generate Domain"**.
   - Railway will instantly give you a free public web address that looks like:
     👉 `https://vesspay-production-xxxx.up.railway.app`
   - **Copy this URL!** This is the public address of your API.

9. **Test that your server is working:**
   - Open a new tab in your web browser and paste:
     `https://YOUR-RAILWAY-URL/api/health`
   - If you see:
     ```json
     {"status":"ok"}
     ```
     **Congratulations! Your backend server and database are running live!**

> 🎉 **Milestone 2 Complete:** Your backend API is running online with free automatic SSL (HTTPS)!

---

## Step 3: Tell WeWire Where to Send Webhooks
⏱️ **Time: 1 minute**

When a recipient receives Mobile Money in Ghana, WeWire sends a notification to your server so your app updates from "Processing" to "Completed".

1. Log into your **[WeWire Developer Sandbox](https://wewireafrica.com)** dashboard.
2. In the menu, go to **Settings** → **Webhooks**.
3. In the **Webhook URL** field, paste:
   ```
   https://YOUR-RAILWAY-URL/api/webhooks/wewire
   ```
   *(Replace `YOUR-RAILWAY-URL` with the domain from Step 2)*.
4. Click **Save**.

> 🎉 **Milestone 3 Complete:** Your server will now receive real-time payment updates!

---

## Step 4: Host Your Website & Web App on Vercel
⏱️ **Time: 3 minutes**

### Part A: Marketing Landing Page
* Your marketing landing page is already live on Vercel at **`https://vesspay.vercel.app`**.
* Whenever you push changes to your GitHub repo, Vercel updates the landing page automatically.

### Part B: The Interactive Web App (Flutter Web)
If you want people to open the VessPay wallet app directly in their web browser (Chrome/Safari):

1. Open your computer terminal (PowerShell or VS Code terminal).
2. Go to the mobile app folder:
   ```bash
   cd c:\vessPay\vessPAY\apps\mobile
   ```
3. Build the web app, pointing it to your live Railway server:
   ```bash
   flutter build web --release --dart-define=API_BASE_URL=https://YOUR-RAILWAY-URL
   ```
   *(Replace `YOUR-RAILWAY-URL` with your actual Railway URL from Step 2)*.
4. Once it finishes (about 30 seconds), go into the web output folder:
   ```bash
   cd build/web
   ```
5. Deploy to Vercel with one command:
   ```bash
   npx vercel --prod
   ```
   - Press `Enter` to confirm the defaults.
   - Vercel will give you a live free URL like: `https://vesspay-app.vercel.app`!

> 🎉 **Milestone 4 Complete:** Users can now open VessPay in any browser!

---

## Step 5: Install the Mobile App on Your Phone (Android)
⏱️ **Time: 2 minutes**

To install the actual mobile app onto an Android phone:

1. In your terminal, run:
   ```bash
   cd c:\vessPay\vessPAY\apps\mobile
   flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-RAILWAY-URL
   ```
2. Once complete, your installer file is ready at:
   `c:\vessPay\vessPAY\apps\mobile\build\app\outputs\flutter-apk\app-release.apk`
3. Send this file to your phone (via Google Drive, WhatsApp, or email) and tap it to install.

---

## How to Verify Everything Works (The 2-Minute Test)

Follow these 4 simple checks to make sure your entire system is running smoothly:

1. **Check 1: Server Health**
   - Visit: `https://YOUR-RAILWAY-URL/api/health`
   - Result: `{"status":"ok"}`
2. **Check 2: Live Currency Rates**
   - Visit: `https://YOUR-RAILWAY-URL/api/rates?from=USD&to=GHS`
   - Result: Shows the live Ghana Cedi exchange rate (e.g., `11.58`).
3. **Check 3: Sandbox Checkout**
   - Visit: `https://YOUR-RAILWAY-URL/checkout/demo-test?amount=50`
   - Result: You will see the dark-mode WeWire Sandbox Virtual Account checkout page!
4. **Check 4: App Login**
   - Open your Vercel web app or the Android app on your phone.
   - Click **Sign Up**, choose **Ghana**, and enter your details.
   - You will land right on the Home Dashboard with your active USD wallet!

---

## Common Questions & Easy Fixes

#### *Q: Railway says "Deployment failed"?*
* Click on the deployment in Railway to see the logs.
* Make sure you set the **Root Directory** to `apps/backend` in the Settings tab.
* Make sure your `DATABASE_URL` is pasted correctly without extra spaces.

#### *Q: Does Supabase delete my database?*
* No. On the free tier, if nobody makes a payment or logs in for a week, Supabase "pauses" the database to save energy.
* To unpause, you simply log in to Supabase and click **"Restore project"** (takes 10 seconds).

#### *Q: What if I run out of free Railway credits?*
* You can deploy the exact same backend on **[render.com](https://render.com)** for free! On Render, create a "Web Service", pick `apps/backend`, and paste the same environment variables. It never runs out of credits on the free tier.
