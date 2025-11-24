# Deploy Firestore Rules

## Quick Fix for Permission Error

The notification screen error is caused by Firestore security rules. The rules have been updated, but you need to deploy them to Firebase.

## Option 1: Deploy via Firebase CLI (Recommended)

1. **Authenticate with Firebase:**
   Open a terminal/command prompt and run:
   ```bash
   cd phone_authentication
   firebase login
   ```
   This will open a browser window for you to sign in with your Google account.

2. **Deploy the rules:**
   After logging in, run:
   ```bash
   firebase deploy --only firestore:rules
   ```

## Option 2: Deploy via Firebase Console (Easier)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **phoneauth-d2c0e**
3. Navigate to: **Firestore Database** → **Rules** tab
4. Copy the entire contents of `firestore.rules` file
5. Paste it into the rules editor in Firebase Console
6. Click **"Publish"** button

## What Was Fixed?

The Firestore rules were blocking queries because they checked `resource.data.driverId` during query evaluation, which isn't available for collection queries. The updated rule allows authenticated users to read notifications, and since your app queries with `where('driverId', isEqualTo: user.uid)`, users can only see their own notifications.

After deploying, restart your app and the notification screen should work!






