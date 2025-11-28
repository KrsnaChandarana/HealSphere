# Testing Guide - How to Login and Check the App

## Prerequisites

1. **Firebase Setup**
   - Ensure Firebase Realtime Database is configured
   - Security rules are applied (see your rules)
   - Database URL: `https://healsphere-ffe5e-default-rtdb.firebaseio.com/`

2. **Run the App**
   ```bash
   flutter run
   ```

## Step 1: Set Up Test Data in Firebase

### Option A: Manual Setup via Firebase Console

1. Go to Firebase Console → Realtime Database
2. Navigate to your database
3. Add the following structure manually or import from `FIREBASE_DATA_EXAMPLES.json`

### Option B: Quick Test Data Setup

You can manually add these test records:

#### 1. Create Test Users (via App Registration)

**Clinician User:**
- Email: `doctor@test.com`
- Password: `test123456`
- Role: `clinician`
- Name: `Dr. Sarah Johnson`

**Patient User:**
- Email: `patient@test.com`
- Password: `test123456`
- Role: `patient`
- Name: `Jane Doe`

**Caregiver User:**
- Email: `caregiver@test.com`
- Password: `test123456`
- Role: `caregiver`
- Name: `John Doe`

#### 2. Add Awareness Content (via Firebase Console)

Go to Firebase Console → Realtime Database → Add:

```json
{
  "awareness": {
    "carousel": {
      "news1": {
        "id": "news1",
        "title": "Breakthrough in Cancer Treatment",
        "description": "Scientists discover new treatment methods.",
        "link": "https://example.com/news1",
        "imageUrl": "",
        "timestamp": 1704067200000
      }
    },
    "education": {
      "edu1": {
        "id": "edu1",
        "title": "Breast Cancer",
        "short": "Most common cancer in women",
        "details": "Symptoms: Lumps, changes in breast shape. Treatment: Surgery, chemotherapy. Prevention: Regular screenings.",
        "moreLink": "https://www.who.int/health-topics/cancer"
      }
    },
    "feed": {
      "article1": {
        "id": "article1",
        "title": "Latest Research on Cancer",
        "description": "Recent studies show promising results.",
        "link": "https://example.com/article1",
        "imageUrl": "",
        "timestamp": 1704326400000
      }
    }
  }
}
```

## Step 2: Testing Login Flow

### Test 1: Register New Users

1. **Launch the app**
   - App starts at Splash Screen
   - After 2 seconds, goes to Login Screen (if not logged in)

2. **Register a Clinician:**
   - Tap "Don't have an account? Register"
   - Fill in:
     - Name: `Dr. Sarah Johnson`
     - Email: `doctor@test.com`
     - Password: `test123456`
     - Select Role: `Clinician`
   - Tap "Create account"
   - Should automatically navigate to Clinician Dashboard

3. **Register a Patient:**
   - Logout from clinician
   - Register new user:
     - Name: `Jane Doe`
     - Email: `patient@test.com`
     - Password: `test123456`
     - Select Role: `Patient`
   - Should navigate to Patient Dashboard

4. **Register a Caregiver:**
   - Logout from patient
   - Register new user:
     - Name: `John Doe`
     - Email: `caregiver@test.com`
     - Password: `test123456`
     - Select Role: `Caregiver`
   - Should navigate to Caregiver Dashboard

### Test 2: Login with Existing Users

1. **From Login Screen:**
   - Enter email: `doctor@test.com`
   - Enter password: `test123456`
   - Select role: `Clinician`
   - Tap "Login"
   - Should navigate to Clinician Dashboard

2. **Test Patient Login:**
   - Logout
   - Login with: `patient@test.com` / `test123456` / Role: `Patient`
   - Should see Patient Dashboard

3. **Test Caregiver Login:**
   - Logout
   - Login with: `caregiver@test.com` / `test123456` / Role: `Caregiver`
   - Should see Caregiver Dashboard

## Step 3: What to Check After Login

### ✅ Clinician Dashboard Checks

1. **Patient List:**
   - Should show list of patients (if any exist)
   - If empty, shows "No patients found. Tap + to add a patient."

2. **Add Patient:**
   - Tap the `+` floating button
   - Fill form:
     - Name: `Test Patient`
     - Age: `45`
     - Gender: `Female`
     - Diagnosis: `Breast Cancer Stage 2`
   - Tap "Add Patient"
   - Should see success message
   - Patient should appear in list

3. **Patient Detail:**
   - Tap on a patient card
   - Should see patient details
   - Can add chemo entries
   - Can create appointments
   - Can register caregiver

4. **Follow-ups:**
   - Tap notification bell icon
   - Should show follow-ups screen
   - If patient sends follow-up, it appears here

5. **Chat:**
   - Tap "Chat" button on patient card
   - Should open chat screen
   - Can send messages

### ✅ Patient Dashboard Checks

1. **My Schedule:**
   - Should show upcoming appointments/chemo
   - Use arrows to navigate
   - Shows medicines if any

2. **Logs:**
   - Tap "Log" button
   - Fill daily log:
     - Eating: `Good`
     - Sleep: `7 hours`
     - Feeling: `Happy`
     - Activities: Select some
   - Tap "Save"
   - Should see log appear in list

3. **My Journey:**
   - Should show doctor's notes (if any)
   - Shows progress summary
   - Shows chemo chart with completion status
   - Lists all chemo sessions

4. **Connections:**
   - Should show Doctor and Caregiver (if linked)
   - Can tap "Chat" to message
   - Can tap "Call" icon (if phone number exists)

5. **Follow-up:**
   - Tap notification icon in app bar
   - Enter message
   - Tap "Send"
   - Should show success message
   - Clinician should see it in follow-ups

### ✅ Caregiver Dashboard Checks

1. **Patient Overview:**
   - Should show linked patient's info
   - Shows diagnosis date
   - Has "Chat with Patient" button

2. **Patient Activities:**
   - Shows chemo schedule
   - Shows appointments (upcoming and past)
   - Shows activity log
   - Can add new activities

3. **Chat:**
   - Can chat with patient
   - Can chat with clinician (if linked)

### ✅ General Awareness Screen Checks

1. **Before Login:**
   - Can access from login screen
   - Should see carousel of news
   - Should see education section
   - Should see research feed
   - Cannot bookmark (prompts to login)

2. **After Login:**
   - Can bookmark items
   - Bookmarks saved to `/bookmarks/{uid}`
   - Can tap "Read More" to open links

## Step 4: Link Patient to User Account

**Important:** For patient dashboard to work, you need to link the patient record to the user account.

### Method 1: Via Clinician Dashboard

1. Login as clinician
2. Add a patient (this creates patient record)
3. Note the patient ID from Firebase
4. In Firebase Console, update:
   - `/users/{patientUserId}/linkedPatientId` = `{patientRecordId}`
   - `/patients/{patientRecordId}/patientUserUid` = `{patientUserId}`

### Method 2: Manual Firebase Update

In Firebase Console, for a patient user:

```json
{
  "users": {
    "patient_user_uid_here": {
      "linkedPatientId": "patient_record_id_here"
    }
  },
  "patients": {
    "patient_record_id_here": {
      "patientUserUid": "patient_user_uid_here",
      "clinicianId": "clinician_user_uid_here"
    }
  }
}
```

## Step 5: Link Caregiver to Patient

1. Login as clinician
2. Open patient detail
3. Tap "Assign Caregiver" or "Register Caregiver"
4. Fill form:
   - Name: `John Doe`
   - Phone: `+1234567890`
   - Email: (optional)
5. This creates caregiver record and links to patient

Then link caregiver user account:
- In Firebase Console:
  - `/caregivers/{caregiverId}/uid` = `{caregiverUserId}`
  - `/users/{caregiverUserId}/linkedPatientId` = `{patientId}`
  - `/patients/{patientId}/caregiverUserUid` = `{caregiverUserId}`

## Troubleshooting

### Issue: Patient Dashboard shows "No schedule available"
**Solution:** 
- Check that patient record exists in `/patients`
- Check that `patientUserUid` is set in patient record
- Check that `linkedPatientId` is set in user record

### Issue: Can't see patients in Clinician Dashboard
**Solution:**
- Verify `clinicianId` in patient records matches clinician's user UID
- Check Firebase rules allow reading `/patients`

### Issue: Follow-ups not showing
**Solution:**
- Check `/followUps/{clinicianId}` exists in Firebase
- Verify follow-up status is "pending"
- Check Firebase rules allow reading `/followUps`

### Issue: Chat not working
**Solution:**
- Verify both users exist
- Check `/chats` and `/userChats` are created
- Verify participants are added to chat

### Issue: Bookmarks not saving
**Solution:**
- Must be logged in
- Check Firebase rules for `/bookmarks/{uid}`
- Verify write permissions

## Quick Test Checklist

- [ ] Can register new users (all 3 roles)
- [ ] Can login with registered users
- [ ] Clinician can add patients
- [ ] Clinician can create appointments
- [ ] Patient can create daily logs
- [ ] Patient can request follow-ups
- [ ] Clinician sees follow-up notifications
- [ ] Chat works between users
- [ ] Awareness screen shows content
- [ ] Bookmarks work when logged in
- [ ] Real-time updates work (test by opening app on 2 devices)

## Firebase Console Quick Access

1. Go to: https://console.firebase.google.com/
2. Select your project: `healsphere-ffe5e`
3. Navigate to: Realtime Database
4. View/edit data directly

## Test Data Quick Import

You can manually copy-paste from `FIREBASE_DATA_EXAMPLES.json` into Firebase Console, but remember to:
- Replace placeholder UIDs with actual user UIDs
- Update timestamps to current time
- Ensure all references match

---

**Happy Testing!** 🚀

If you encounter any issues, check:
1. Firebase Console for data structure
2. App logs for error messages
3. Firebase rules for permission issues




