# Alternative: iOS Shortcuts Integration

Since Share Extensions require manual Xcode setup (can't be scripted), here are TWO easier alternatives:

## Option 1: iOS Shortcut (RECOMMENDED - Zero Code!)

Create a reusable iOS Shortcut that users can add once:

### User Setup (One Time, ~30 seconds):
1. Open **Shortcuts app** on iPhone
2. Tap **+** to create new shortcut
3. Name it: **"RevBo"**
4. Add these actions:
   - **Share** → Get input (type: Images)
   - **Wait to Return** → OFF
   - **Send [Image] in an email to [your RevBo email]**
     - To: `brain+{their-token}@revbo.ai` (shown in Settings)
     - Subject: "Share"
5. Tap **•••** (more options)
6. Enable: **Show in Share Sheet**
7. Restrict to: **Images**
8. Tap **Done**

### Usage:
Screenshot → Share → **RevBo** shortcut → Auto-emails to brain

**Pros:**
- Zero development needed
- Works immediately
- Can customize per user
- Appears in share sheet alongside native options

**Cons:**
- Users must set up once (but very easy)
- Requires email to be configured on device

---

## Option 2: Share Extension (What I Coded - Requires Xcode Setup)

The Share Extension I built gives the BEST UX:
- Native "RevBo" button in every share sheet
- Direct upload (no email)
- Instant confirmation
- Professional integration

**But it requires manual Xcode setup** because Xcode targets can't be created via command line.

Follow the instructions in `ADD_SHARE_EXTENSION.md` if you want the native extension.

Estimated setup time: **5-10 minutes** in Xcode

---

## Recommendation

**For MVP/Beta:** Tell users to create the iOS Shortcut (Option 1). Include screenshots in your onboarding email.

**For v1.0 Production:** Set up the Share Extension (Option 2) for the polished native experience.

The Share Extension code is ready to go in `RevBoShareExtension/` - you just need to add the target in Xcode when you have 10 minutes.

---

## Quick Start: Shortcut Template for Users

Include this in your beta tester email:

```
📸 Quick Setup: Add "RevBo" to Your Share Menu

1. Open the Shortcuts app
2. Create a new Shortcut called "RevBo"  
3. Add these steps:
   • Receive Images from Share Sheet
   • Send Email
     - To: [your RevBo email from Settings]
     - Subject: Share
     - Body: [Shortcut Input]
4. In shortcut settings (•••):
   • Show in Share Sheet: ON
   • Accepted Types: Images

Done! Now you can share any screenshot directly to RevBo.
```

Most beta testers can set this up in under a minute.
